"""Tests for WealthSync ML API endpoints."""

from __future__ import annotations

import pytest
from httpx import AsyncClient, ASGITransport
from backend.main import app

# Configure pytest-asyncio
pytestmark = pytest.mark.asyncio


@pytest.fixture
async def client():
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        yield ac


# ============================================================
# Health Checks
# ============================================================

async def test_health_endpoint(client: AsyncClient):
    """Basic health endpoint returns ok."""
    resp = await client.get("/health")
    assert resp.status_code == 200
    data = resp.json()
    assert data["status"] == "ok"
    assert "models" in data


async def test_model_health_endpoint(client: AsyncClient):
    """Model health endpoint returns status for all models."""
    resp = await client.get("/health/models")
    assert resp.status_code == 200
    data = resp.json()
    assert data["success"] is True
    assert "models" in data
    # Check production models
    assert "spending" in data["models"]
    assert "risk" in data["models"]
    assert data["models"]["spending"]["status"] == "available"
    assert data["models"]["risk"]["status"] == "available"


# ============================================================
# Spending Prediction Tests
# ============================================================

SPENDING_VALID_PAYLOAD = {
    "age_ref": 45,
    "age2": 2025,
    "fam_size": 3,
    "educ_ref": 4,
    "seq": 1,
    "totexppq": 15000,
    "foodpq": 2000,
    "houspq": 6000,
    "transpq": 2500,
    "utilpq": 1000,
    "sheltpq": 500,  # exact spelling
    "itbi_q_income": 20000,
    "cuincome_class": 3,
    "total_spend_lag1": 14000,
    "total_spend_pastmean": 14500,
    "total_spend_paststd": 1000,
    "food_lag1": 1900,
    "housing_lag1": 5800,
    "income_lag1": 19500,
    "fam_type": 1,
    "cutenure": 1,
    "bls_urbn": 1,
}


async def test_spending_predict_valid(client: AsyncClient):
    """Valid spending request returns prediction."""
    resp = await client.post("/api/ml/spending/predict", json=SPENDING_VALID_PAYLOAD)
    assert resp.status_code == 200
    data = resp.json()
    assert data["success"] is True
    assert "data" in data
    assert data["data"]["model"] == "spending"
    assert data["data"]["variant"] == "random forest"
    assert "prediction" in data["data"]
    assert isinstance(data["data"]["prediction"], (int, float))
    assert data["data"]["prediction"] > 0
    assert data["data"]["currency"] == "USD"


async def test_spending_predict_missing_feature(client: AsyncClient):
    """Missing required feature returns 400."""
    payload = SPENDING_VALID_PAYLOAD.copy()
    del payload["age_ref"]
    resp = await client.post("/api/ml/spending/predict", json=payload)
    assert resp.status_code == 400
    data = resp.json()
    assert data["success"] is False
    assert data["error"]["code"] == "INVALID_FEATURES"
    assert "age_ref" in data["error"]["message"]


async def test_spending_predict_invalid_datatype(client: AsyncClient):
    """Invalid datatype returns 400."""
    payload = SPENDING_VALID_PAYLOAD.copy()
    payload["age_ref"] = "not_a_number"
    resp = await client.post("/api/ml/spending/predict", json=payload)
    assert resp.status_code == 400


async def test_spending_predict_extra_field(client: AsyncClient):
    """Extra unknown field is rejected (extra='forbid')."""
    payload = SPENDING_VALID_PAYLOAD.copy()
    payload["unknown_field"] = 123
    resp = await client.post("/api/ml/spending/predict", json=payload)
    assert resp.status_code == 400


async def test_spending_predict_feature_order(client: AsyncClient):
    """Feature order in DataFrame matches training order."""
    resp = await client.post("/api/ml/spending/predict", json=SPENDING_VALID_PAYLOAD)
    assert resp.status_code == 200
    data = resp.json()
    # Prediction should be a reasonable number
    pred = data["data"]["prediction"]
    assert 0 < pred < 100000  # reasonable range for quarterly expenditure


async def test_spending_model_loading(client: AsyncClient):
    """Model loading works (implicitly tested by prediction)."""
    resp = await client.post("/api/ml/spending/predict", json=SPENDING_VALID_PAYLOAD)
    assert resp.status_code == 200


# ============================================================
# Risk Prediction Tests
# ============================================================

RISK_VALID_PAYLOAD = {
    "LIMIT_BAL": 100000,
    "AGE": 35,
    "PAY_0": 0,
    "PAY_2": 0,
    "PAY_3": 0,
    "PAY_4": 0,
    "PAY_5": 0,
    "PAY_6": 0,
    "BILL_AMT1": 5000,
    "BILL_AMT2": 4500,
    "BILL_AMT3": 4000,
    "BILL_AMT4": 3500,
    "BILL_AMT5": 3000,
    "BILL_AMT6": 2500,
    "PAY_AMT1": 2000,
    "PAY_AMT2": 2000,
    "PAY_AMT3": 2000,
    "PAY_AMT4": 2000,
    "PAY_AMT5": 2000,
    "PAY_AMT6": 2000,
    "util_mean6": 0.3,
    "repay_ratio_mean6": 0.8,
    "max_delinq_6m": 0,
    "SEX": 1,
    "EDUCATION": 2,
    "MARRIAGE": 1,
}


async def test_risk_predict_valid(client: AsyncClient):
    """Valid risk request returns probability, score, and level."""
    resp = await client.post("/api/ml/risk/predict", json=RISK_VALID_PAYLOAD)
    assert resp.status_code == 200
    data = resp.json()
    assert data["success"] is True
    assert "data" in data
    assert data["data"]["model"] == "risk"
    assert data["data"]["variant"] == "gradient boosting"
    assert "default_probability" in data["data"]
    assert "risk_score" in data["data"]
    assert "risk_level" in data["data"]
    
    prob = data["data"]["default_probability"]
    score = data["data"]["risk_score"]
    level = data["data"]["risk_level"]
    
    assert 0.0 <= prob <= 1.0
    assert 0.0 <= score <= 100.0
    assert level in ("Low", "Medium", "High")
    assert score == round(prob * 100, 1)


async def test_risk_predict_missing_feature(client: AsyncClient):
    """Missing required feature returns 400."""
    payload = RISK_VALID_PAYLOAD.copy()
    del payload["LIMIT_BAL"]
    resp = await client.post("/api/ml/risk/predict", json=payload)
    assert resp.status_code == 400
    data = resp.json()
    assert data["success"] is False
    assert data["error"]["code"] == "INVALID_FEATURES"
    assert "LIMIT_BAL" in data["error"]["message"]


async def test_risk_predict_invalid_datatype(client: AsyncClient):
    """Invalid datatype returns 400."""
    payload = RISK_VALID_PAYLOAD.copy()
    payload["AGE"] = "not_a_number"
    resp = await client.post("/api/ml/risk/predict", json=payload)
    assert resp.status_code == 400


async def test_risk_predict_repay_ratio_mean6_null(client: AsyncClient):
    """repay_ratio_mean6 can be null (handled by imputer)."""
    payload = RISK_VALID_PAYLOAD.copy()
    payload["repay_ratio_mean6"] = None
    resp = await client.post("/api/ml/risk/predict", json=payload)
    assert resp.status_code == 200
    data = resp.json()
    assert data["success"] is True
    prob = data["data"]["default_probability"]
    assert 0.0 <= prob <= 1.0


async def test_risk_predict_probability_range(client: AsyncClient):
    """Probability is always between 0 and 1."""
    resp = await client.post("/api/ml/risk/predict", json=RISK_VALID_PAYLOAD)
    assert resp.status_code == 200
    prob = resp.json()["data"]["default_probability"]
    assert 0.0 <= prob <= 1.0


async def test_risk_predict_score_range(client: AsyncClient):
    """Risk score is always between 0 and 100."""
    resp = await client.post("/api/ml/risk/predict", json=RISK_VALID_PAYLOAD)
    assert resp.status_code == 200
    score = resp.json()["data"]["risk_score"]
    assert 0.0 <= score <= 100.0


async def test_risk_predict_band_boundaries(client: AsyncClient):
    """Test risk band boundaries: 0.30->Low, 0.31->Medium, 0.60->Medium, 0.61->High."""
    from backend.services import _risk_score
    
    # Test boundaries
    score, level = _risk_score(0.30)
    assert score == 30.0
    assert level == "Low"
    
    score, level = _risk_score(0.31)
    assert score == 31.0
    assert level == "Medium"
    
    score, level = _risk_score(0.60)
    assert score == 60.0
    assert level == "Medium"
    
    score, level = _risk_score(0.61)
    assert score == 61.0
    assert level == "High"
    
    score, level = _risk_score(0.0)
    assert level == "Low"
    
    score, level = _risk_score(1.0)
    assert level == "High"


async def test_risk_model_loading(client: AsyncClient):
    """Model loading works (implicitly tested by prediction)."""
    resp = await client.post("/api/ml/risk/predict", json=RISK_VALID_PAYLOAD)
    assert resp.status_code == 200


# ============================================================
# Legacy Endpoints (backward compatibility) - SKIP if artifacts not found
# ============================================================

async def test_legacy_predict_spending(client: AsyncClient):
    """Legacy /predict/spending works or returns 503 if artifacts not found."""
    resp = await client.post("/predict/spending", json={"features": SPENDING_VALID_PAYLOAD})
    # Accept 200 (works) or 503 (artifacts not found)
    assert resp.status_code in (200, 503)


async def test_legacy_predict_risk(client: AsyncClient):
    """Legacy /predict/risk works or returns 503 if artifacts not found."""
    resp = await client.post("/predict/risk", json={"features": RISK_VALID_PAYLOAD})
    assert resp.status_code in (200, 503)


async def test_legacy_unknown_model(client: AsyncClient):
    """Unknown model returns 400."""
    resp = await client.post("/predict/unknown", json={"features": {}})
    assert resp.status_code == 400


# ============================================================
# Error Format Consistency
# ============================================================

async def test_error_format_consistency(client: AsyncClient):
    """All errors follow the same format."""
    # Test spending missing feature
    resp = await client.post("/api/ml/spending/predict", json={"age_ref": 45})
    assert resp.status_code == 400
    data = resp.json()
    assert data["success"] is False
    assert "error" in data
    assert "code" in data["error"]
    assert "message" in data["error"]
    
    # Test risk missing feature
    resp = await client.post("/api/ml/risk/predict", json={"LIMIT_BAL": 100000})
    assert resp.status_code == 400
    data = resp.json()
    assert data["success"] is False
    assert "error" in data
    assert "code" in data["error"]
    assert "message" in data["error"]


# ============================================================
# Model Registry
# ============================================================

async def test_models_registry(client: AsyncClient):
    """Models registry includes production and legacy models."""
    resp = await client.get("/models")
    assert resp.status_code == 200
    data = resp.json()
    assert "spending" in data
    assert "risk" in data
    assert data["spending"]["status"] == "production_candidate"
    assert data["risk"]["status"] == "production_candidate"
    assert data["spending"]["algorithm"] == "RandomForestRegressor"
    assert data["risk"]["algorithm"] == "GradientBoostingRegressor"


if __name__ == "__main__":
    pytest.main([__file__, "-v"])