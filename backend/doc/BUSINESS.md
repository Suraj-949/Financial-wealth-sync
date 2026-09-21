# WealthSync — Backend Business Document

## Role
The FastAPI service is the **intelligence layer** of WealthSync. It owns the trained ML
models and serves predictions + explanations to clients. It does not train models; it loads
the artifacts produced by the ML pipeline and exposes them over HTTP.

## What the backend delivers
1. **Model serving** — workspace for 5 trained models: spending, savings, wellness, risk, payment.
2. **Predictions** — `POST /predict/{model}` returns the model's output for a feature payload.
3. **Explanations** — `POST /explain/{model}` returns SHAP-based attribution so every prediction
   is auditable ("why?" is a product promise, not a nice-to-have).
4. **Discovery** — `/models` advertises capabilities/metadata; `/sample/{model}` returns
   test-window payloads for clients and human verification.

## API contract
| Method | Path | Purpose |
|---|---|---|
| GET | `/health` | liveness probe |
| GET | `/models` | served models + metadata |
| GET | `/sample/{model}` | test-window sample features |
| POST | `/predict/{model}` | `{"features": {...}}` → predictions |
| POST | `/explain/{model}` | `{"features": {...}}` → SHAP explanation |

Base URL: `http://127.0.0.1:8000` (dev). Interactive docs at `/docs`.

## Honest metrics (do not inflate)
- Spending/savings: weak R² on the volatile 2024 test window — directional, not precise.
- Payment mode: accuracy ≈ chance (source data's modes are near-random).
- Wellness: strong R² but the target is rule-derived — treat as proxy until real labels exist.
- Risk: strong (ROC-AUC 0.971); note test window skew (96% high-risk).

## Roadmap (backend side)
1. `GET /api/dashboard` aggregate endpoint replacing the frontend mock repository.
2. Copilot grounding pipeline (query → user data + ML + XAI + recommendations → reply).
3. Auth, rate limiting, and per-user privacy boundaries (masked data, no raw account numbers).