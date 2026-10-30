# WealthSync ML Prediction API - Developer Documentation

## Overview

This document describes the ML prediction API layer for the WealthSync project. The API serves **three model families** — never mix their units:

1. **BLS/UCI production models** (`ml/models/`): spending Random Forest (next-quarter USD)
   and risk Gradient Boosting (default probability → 0-100 score).
2. **INR monthly models** (`ml/artifacts/`): spending, savings, wellness and risk
   (budgetwise monthly features, INR + 0-100 wellness), served by the generic
   `GET /sample/{model}` → `POST /predict/{model}` (+ `POST /explain/{model}`) pipeline
   that the Flutter dashboard consumes.
3. **SMS text classifier** (`sms/`): a two-stage TF-IDF + Naive Bayes pipeline
   (spam/noise filter → credit/debit/other), served by `/api/sms/*`.

Endpoints at a glance:

| Family | Endpoint | Input | Output |
|---|---|---|---|
| BLS | `POST /api/ml/spending/predict` | 22 CE raw features | quarterly USD |
| UCI | `POST /api/ml/risk/predict` | 26 UCI raw features | probability + 0-100 score/level |
| INR | `GET /sample/{spending,savings,wellness,risk}` | — | 5 test-window feature rows + actuals |
| INR | `POST /predict/{spending,savings,wellness,risk}` | `{features: {...}}` | prediction (INR / 0-100 / label) |
| INR | `POST /explain/{spending,savings,wellness,risk}` | `{features: {...}}` | ranked SHAP factors |
| SMS | `POST /api/sms/classify` | `{text}` | status + category + confidences |
| SMS | `POST /api/sms/classify/batch` | `{messages: [...]}` | `{count, results: [...]}` |
| SMS | `GET /api/sms/health` | — | pipeline availability + metadata |
| Data | `GET /api/data/{resource}` | `?user_id=...` or `X-User-Id` | `{success: true, data: [...]}` |
| Data | `PUT /api/data/{resource}/{id}` | JSON payload document | `{success: true, data: {...}}` |
| Data | `DELETE /api/data/{resource}/{id}` | `?user_id=...` or `X-User-Id` | `{success: true, deleted: true}` |

## Model Locations

| Model | Path | Algorithm | Status |
|-------|------|-----------|--------|
| Spending | `ml/models/spending/random forest/` | RandomForestRegressor | Production Candidate |
| Risk | `ml/models/risk/gradient boosting/` | GradientBoostingRegressor | Production Candidate |

Each model directory contains:
- `model.joblib` - Complete fitted sklearn Pipeline (preprocessor + estimator)
- `preprocessor.joblib` - Fitted ColumnTransformer (for inspection)
- `feature_columns.json` - Raw input feature names and metadata
- `metadata.json` - Model metadata, metrics, and caveats

## API Endpoints

### Production Endpoints

#### POST `/api/ml/spending/predict`
Predict next-quarter total expenditure.

**Request:** JSON object with exact raw features from `spending/random forest/feature_columns.json`

```json
{
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
  "sheltpq": 500,
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
  "bls_urbn": 1
}
```

**Response:**
```json
{
  "success": true,
  "data": {
    "model": "spending",
    "variant": "random forest",
    "target": "total_spend_t_plus_1",
    "algorithm": "RandomForestRegressor",
    "kind": "regression",
    "prediction": 15516.58,
    "currency": "USD",
    "unit": "dollars",
    "note": "Predicted next-quarter total expenditure in USD (2004 dollars, TOTEXPPQ scale)"
  }
}
```

#### POST `/api/ml/risk/predict`
Predict default probability and risk score.

**Request:** JSON object with exact raw features from `risk/gradient boosting/feature_columns.json`

```json
{
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
  "MARRIAGE": 1
}
```

**Response:**
```json
{
  "success": true,
  "data": {
    "model": "risk",
    "variant": "gradient boosting",
    "target": "default payment next month",
    "algorithm": "GradientBoostingRegressor",
    "kind": "classification",
    "default_probability": 0.1278,
    "risk_score": 12.8,
    "risk_level": "Low",
    "note": "Risk score = predicted probability × 100; bands: 0-30 Low, 31-60 Medium, 61-100 High"
  }
}
```

### Legacy Endpoints (Backward Compatibility)

#### POST `/predict/{model}`
Generic prediction for all 5 legacy models (ml/artifacts).

#### POST `/explain/{model}`
SHAP explanations for any model.

#### GET `/sample/{model}`
Realistic test payloads from training test window.

#### GET `/models`
Model registry with algorithms, metrics, and feature lists.

#### GET `/health` / `/health/models`
Health checks and model availability status.

## Important Feature Details

### Spending Model
- **Exact column name:** `sheltpq` (NOT `shelterpq`)
- **Required but all-NaN in train:** `total_spend_paststd` - must be present in input; the train-fitted imputer drops it internally
- **Categorical features:** `fam_type`, `cutenure`, `bls_urbn` (integer-coded, one-hot encoded in pipeline)
- **Missing indicators:** Automatically generated for numeric columns with missing values in training (age2, cuincome_class, total_spend_lag1, total_spend_pastmean, total_spend_paststd, food_lag1, housing_lag1, income_lag1)

### Risk Model
- **Do NOT include:** `repay_ratio_mean6_missing` - this indicator is generated internally by the pipeline from missingness in `repay_ratio_mean6`
- **Can be null:** `repay_ratio_mean6` - legitimate NaN (zero billed total); handled by pipeline's median imputation + missing indicator
- **Categorical features:** `SEX`, `EDUCATION`, `MARRIAGE` (integer-coded, one-hot encoded in pipeline)

## Model Loading

Models are loaded **once at startup** and cached in memory:

```
Application startup
       ↓
Load spending model.joblib (Pipeline)
       ↓
Load risk model.joblib (Pipeline)
       ↓
Keep models in memory
       ↓
API request
       ↓
Validate input against feature_columns.json
       ↓
model.predict(DataFrame)
       ↓
Response
```

Models are loaded lazily on first use and cached in `_cache` dictionary. The cache key includes model name and variant (e.g., "spending/random forest").

## Validation

### Request Validation
- All required features must be present (checked against `feature_columns.json`)
- Extra fields are rejected (`extra='forbid'` in Pydantic models)
- Type validation for all numeric fields
- `repay_ratio_mean6` can be `null`/`None` (handled by pipeline imputer)

### Error Responses
All errors follow a consistent format:

```json
{
  "success": false,
  "error": {
    "code": "INVALID_FEATURES",
    "message": "Missing required features: ['age_ref', 'age2', ...]"
  }
}
```

| Code | HTTP Status | Description |
|------|-------------|-------------|
| `INVALID_FEATURES` | 400 | Missing, extra, or invalid feature values |
| `MODEL_UNAVAILABLE` | 503 | Legacy model artifacts not found |
| `PREDICTION_FAILED` | 500 | Internal prediction error |
| `INTERNAL_ERROR` | 500 | Unexpected server error |

### Validation Error Codes
- **400** - Invalid features (missing, extra, wrong type)
- **404** - Unknown model (legacy endpoints)
- **503** - Legacy model artifacts not found
- **500** - Internal server error

## Risk Score Calculation

The risk model outputs a **default probability** in [0, 1]. The API converts this to:

```
risk_score = default_probability × 100
```

Risk bands:
| Score Range | Level | Observed Default Rate |
|-------------|-------|----------------------|
| 0–30 | Low | 12.6% |
| 31–60 | Medium | 40.3% |
| 61–100 | High | 73.6% |

Band boundaries are inclusive at the lower bound:
- 0.30 → Low (score 30.0)
- 0.31 → Medium (score 31.0)
- 0.60 → Medium (score 60.0)
- 0.61 → High (score 61.0)

## Running the API

### Prerequisites
- Python 3.13+ (Anaconda recommended)
- Dependencies: `fastapi`, `uvicorn`, `pydantic`, `joblib`, `numpy`, `pandas`, `scikit-learn==1.6.1`, `xgboost`, `shap`

### Start Server
```bash
# From repo root
C:/Users/SURAJ/anaconda3/python.exe -m uvicorn backend.main:app --host 0.0.0.0 --port 8000

# Or using the PowerShell script
powershell -File backend/run_backend.ps1
```

The API will be available at `http://127.0.0.1:8000` with interactive docs at `http://127.0.0.1:8000/docs`.

### Environment
- `KMP_DUPLICATE_LIB_OK=TRUE` (required for OpenMP on Windows with scikit-learn)

## Running Tests

```bash
# From backend directory
$env:KMP_DUPLICATE_LIB_OK="TRUE"
C:/Users/SURAJ/anaconda3/python.exe -m pytest backend/test_ml_api.py -v
```

### Test Coverage
- Health checks (basic + model-specific)
- Spending prediction: valid, missing features, invalid types, extra fields, feature order
- Risk prediction: valid, missing features, invalid types, null repay_ratio_mean6, probability/score ranges, band boundaries
- Legacy endpoints (graceful 503 if artifacts missing)
- Error format consistency
- Model registry

## Important Notes

### No Retraining
- **Never call `.fit()` or `.fit_transform()`** on loaded models
- The `model.joblib` contains the complete fitted pipeline
- Use `model.predict(DataFrame)` directly - the pipeline handles preprocessing internally
- `preprocessor.joblib` is for inspection only, not the primary inference path

### Feature Assumptions
- Never hardcode feature assumptions
- Always read `feature_columns.json` for the exact raw feature names and order
- The request validation uses the exact raw feature names from the JSON
- Do not silently rename features (e.g., `sheltpq` ≠ `shelterpq`)

### Security
- No authentication currently implemented (dev only)
- CORS allows all origins (restrict in production)
- No filesystem paths exposed in responses
- No model internals exposed
- No arbitrary model paths from request parameters

### Model Artifacts
The legacy models in `ml/artifacts/` are not included in this repo. The legacy endpoints (`/predict/{model}`, `/explain/{model}`, `/sample/{model}`) return 503 if artifacts are not found.

## SMS Transaction Classifier (`/api/sms/*`)

A two-stage text pipeline (see `sms/README.md`). Stage 1 is a spam/noise filter
(binary), stage 2 labels legitimate transactions `credit` / `debit` / `other`.
Both stages are `TfidfVectorizer(ngram_range=(1, 2))` + `MultinomialNB(alpha=0.1)`.
Artifacts are trained once and persisted to `sms/artifacts/`; the backend loads
them lazily and **never retrains** on request.

#### POST `/api/sms/classify`
**Request:** `{ "text": "ALERT: Acct *112 has been credited with USD 450.00." }`

**Response:**
```json
{
  "success": true,
  "data": {
    "text": "ALERT: Acct *112 has been credited with USD 450.00.",
    "is_spam": false,
    "is_transaction": true,
    "status": "APPROVED (TRANSACTION)",
    "category": "credit",
    "display_category": "Credit",
    "confidence": 94.56,
    "spam_probability": 0.95,
    "category_probabilities": {"credit": 94.56, "debit": 3.4, "other": 2.04}
  }
}
```

- `status` is `APPROVED (TRANSACTION)` or `DISCARDED (SPAM/NOISE)`.
- `category` is `credit` / `debit` / `other`, or `N/A` when discarded.
- `confidence` is the decisive stage's percentage; `spam_probability` is P(spam)
  from stage 1 regardless of the prediction (a legitimate SMS shows a low value).
- `category_probabilities` is empty when the message is discarded.

#### POST `/api/sms/classify/batch`
**Request:** `{ "messages": ["...", "..."] }` → `{ "data": { "count": 2, "results": [ ... ] } }` (order preserved).

#### GET `/api/sms/health`
Returns `{ "sms": { "status": "available", "categories": ["credit","debit","other"], ... } }`.

Empty / whitespace-only text and empty batches return `400` with the standard
`{ "success": false, "error": { "code", "message" } }` envelope.

## User Finance Data Persistence (`/api/data/*`)

WealthSync persists user ledger documents directly to PostgreSQL JSONB storage, partitioned cleanly by user identity.

### Supported Resources
- `transactions` — Financial income/expense ledger entries
- `accounts` — Bank accounts, savings balances, and credit cards
- `budgets` — Spending limits and category targets
- `goals` — Savings milestones and target deadlines
- `alerts` — System notifications and financial triggers
- `recommendations` — AI-generated actionable advice

### User Namespace Identification
Requests identify their partition namespace via:
- Query parameter: `?user_id=local-user`
- HTTP header: `X-User-Id: local-user` (takes precedence when both are provided)
If omitted, defaults to `"demo-user"`.

#### GET `/api/data/{resource}`
List all records for a given resource in the user's namespace.

**Request:** `GET /api/data/transactions?user_id=local-user`

**Response:**
```json
{
  "success": true,
  "data": [
    {
      "id": "tx-101",
      "merchant": "Supermarket",
      "category": "groceries",
      "type": "expense",
      "amount": 2450.0,
      "date": "2026-10-28T14:30:00Z",
      "note": "Weekly grocery shopping"
    }
  ]
}
```

#### PUT `/api/data/{resource}/{record_id}`
Upsert (insert or overwrite) a single document by record ID.

**Request:**
`PUT /api/data/transactions/tx-101?user_id=local-user`
```json
{
  "merchant": "Supermarket",
  "category": "groceries",
  "type": "expense",
  "amount": 2550.0,
  "date": "2026-10-28T14:30:00Z",
  "note": "Weekly grocery shopping (updated)"
}
```

**Response:**
```json
{
  "success": true,
  "data": {
    "id": "tx-101",
    "merchant": "Supermarket",
    "category": "groceries",
    "type": "expense",
    "amount": 2550.0,
    "date": "2026-10-28T14:30:00Z",
    "note": "Weekly grocery shopping (updated)"
  }
}
```

#### DELETE `/api/data/{resource}/{record_id}`
Delete a record from the user's namespace.

**Request:** `DELETE /api/data/transactions/tx-101?user_id=local-user`

**Response:**
```json
{
  "success": true,
  "deleted": true
}
```

## Architecture

```
API Route (/api/ml/... or /api/sms/...)
    ↓
Request Schema / Validation (Pydantic)
    ↓
ML Service (services.py) / SMS Service (sms_service.py)
    ↓
Loaded Model (cached Pipeline) / Cached SMS pipeline (sms/artifacts)
    ↓
Prediction
    ↓
Response Schema
```

Key files:
- `backend/main.py` - FastAPI routes, CORS, lifespan, and exception handlers
- `backend/services.py` - Model loading, caching, prediction, and SHAP explainability logic
- `backend/database.py` - PostgreSQL SQLAlchemy engine, JSONB document model, and CRUD operations
- `backend/sms_service.py` - SMS two-stage classifier adapter (`sms/` package)
- `backend/schemas.py` - Pydantic request/response schemas
- `backend/test_ml_api.py` / `backend/test_sms_api.py` - Test suites
- `ml/models/{spending,risk}/...` - Model artifacts
- `sms/artifacts/...` - SMS pipeline artifacts