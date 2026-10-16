"""Tests for the WealthSync SMS transaction classifier API.

Mirrors the notebook's validation suite: a valid credit is approved + labelled
credit, spam is discarded, a debit is approved + labelled debit, and a chat
message with no financial markers is discarded.
"""

from __future__ import annotations

import pytest
from httpx import AsyncClient, ASGITransport
from backend.main import app

pytestmark = pytest.mark.asyncio


@pytest.fixture
async def client():
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        yield ac


# ============================================================
# Health
# ============================================================

async def test_health_lists_sms(client: AsyncClient):
    resp = await client.get("/health")
    assert resp.status_code == 200
    assert "sms" in resp.json()["models"]


async def test_sms_health(client: AsyncClient):
    resp = await client.get("/api/sms/health")
    assert resp.status_code == 200
    body = resp.json()
    assert body["success"] is True
    assert body["sms"]["status"] == "available"
    assert set(body["sms"]["categories"]) == {"credit", "debit", "other"}


# ============================================================
# Single classification
# ============================================================

async def test_classify_credit(client: AsyncClient):
    resp = await client.post(
        "/api/sms/classify",
        json={"text": "ALERT: Acct *112 has been credited with USD 450.00."},
    )
    assert resp.status_code == 200
    data = resp.json()["data"]
    assert data["status"] == "APPROVED (TRANSACTION)"
    assert data["category"] == "credit"
    assert data["is_transaction"] is True
    assert data["is_spam"] is False
    assert data["confidence"] > 50
    assert set(data["category_probabilities"]) == {"credit", "debit", "other"}


async def test_classify_debit(client: AsyncClient):
    resp = await client.post(
        "/api/sms/classify",
        json={"text": "You spent USD 4.50 at McDonalds."},
    )
    assert resp.status_code == 200
    data = resp.json()["data"]
    assert data["status"] == "APPROVED (TRANSACTION)"
    assert data["category"] == "debit"


async def test_classify_spam(client: AsyncClient):
    resp = await client.post(
        "/api/sms/classify",
        json={"text": "Congratulations! You won a lottery of $1,000,000! Call now."},
    )
    assert resp.status_code == 200
    data = resp.json()["data"]
    assert data["status"] == "DISCARDED (SPAM/NOISE)"
    assert data["category"] == "N/A"
    assert data["is_spam"] is True
    assert data["is_transaction"] is False
    assert data["spam_probability"] > 50
    assert data["category_probabilities"] == {}


async def test_classify_non_financial_chat_is_discarded(client: AsyncClient):
    resp = await client.post(
        "/api/sms/classify",
        json={"text": "Hey, let's catch up over coffee tonight."},
    )
    assert resp.status_code == 200
    assert resp.json()["data"]["status"] == "DISCARDED (SPAM/NOISE)"


async def test_classify_legitimate_has_low_spam_probability(client: AsyncClient):
    resp = await client.post(
        "/api/sms/classify",
        json={"text": "Your bank account XX445 has been credited with USD 120.00."},
    )
    data = resp.json()["data"]
    assert data["is_transaction"] is True
    assert data["spam_probability"] < 50


# ============================================================
# Batch classification
# ============================================================

async def test_classify_batch_preserves_order(client: AsyncClient):
    messages = [
        "ALERT: Acct *112 has been credited with USD 450.00.",
        "Congratulations! You won a lottery of $1,000,000! Call now.",
        "You spent USD 4.50 at McDonalds.",
    ]
    resp = await client.post("/api/sms/classify/batch", json={"messages": messages})
    assert resp.status_code == 200
    data = resp.json()["data"]
    assert data["count"] == 3
    results = data["results"]
    assert [r["text"] for r in results] == messages
    assert results[0]["category"] == "credit"
    assert results[1]["is_spam"] is True
    assert results[2]["category"] == "debit"


# ============================================================
# Validation / error handling
# ============================================================

async def test_empty_text_rejected(client: AsyncClient):
    resp = await client.post("/api/sms/classify", json={"text": "   "})
    assert resp.status_code == 400
    body = resp.json()
    assert body["success"] is False
    assert "error" in body


async def test_missing_text_rejected(client: AsyncClient):
    resp = await client.post("/api/sms/classify", json={})
    assert resp.status_code == 400
    assert resp.json()["success"] is False


async def test_extra_field_rejected(client: AsyncClient):
    resp = await client.post(
        "/api/sms/classify",
        json={"text": "Salary credited USD 3000.00", "extra": 1},
    )
    assert resp.status_code == 400
    assert resp.json()["success"] is False


async def test_empty_batch_rejected(client: AsyncClient):
    resp = await client.post("/api/sms/classify/batch", json={"messages": []})
    assert resp.status_code == 400
    assert resp.json()["success"] is False
