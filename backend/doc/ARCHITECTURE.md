# WealthSync Backend — Architecture & System Design

The WealthSync backend is a high-performance **FastAPI** service serving as the prediction, explainability, and persistence engine for the platform. It serves three distinct families of machine learning models, exposes TreeSHAP/LinearSHAP explanations, runs a two-stage NLP SMS transaction classifier, and provides partitioned document persistence in PostgreSQL.

---

## Directory & File Architecture

```
backend/
|-- __init__.py          # Package marker for relative imports
|-- main.py              # FastAPI app: route definitions, CORS middleware, error handlers, lifespan
|-- services.py          # Model caching, inference pipelines, and SHAP explainability
|-- database.py          # PostgreSQL schema (JSONB document table), engine pooling, CRUD functions
|-- sms_service.py       # Adapter connecting FastAPI to the sms/ classification package
|-- schemas.py           # Pydantic v2 validation models for requests and responses
|-- samples.py           # Verified test-window payloads for try-me endpoints
|-- run_backend.ps1      # Launcher script: starts uvicorn on :8000 and opens /docs
|-- start_database.ps1   # Helper script: starts the PostgreSQL Windows service
|-- requirements.txt     # Python dependencies (fastapi, uvicorn, pydantic, sqlalchemy, psycopg, shap)
|-- .env                 # Active environment variables (gitignored)
|-- .env.example         # Template for environment configuration
|-- ML_API_DOCUMENTATION.md # Developer documentation for ML & SMS APIs
|-- POSTGRESQL.md        # Database setup and user partitioning guide
|-- test_ml_api.py       # Pytest test suite for ML & health endpoints (27 tests)
|-- test_sms_api.py      # Pytest test suite for SMS endpoints (12 tests)
`-- doc/                 # Backend documentation (AGENTS, ARCHITECTURE, BUSINESS)
```

---

## Endpoints Reference

| Method | Path | Request Body | Description |
|---|---|---|---|
| `GET` | `/health` | — | Basic liveness, database status (`connected`/`unavailable`), loaded models |
| `GET` | `/health/models` | — | Detailed health and availability of all production and legacy models |
| `GET` | `/models` | — | Model registry: algorithms, targets, feature lists, test metrics |
| `POST`| `/api/ml/spending/predict` | 22 BLS CE features | Production Random Forest next-quarter spend prediction (USD) |
| `POST`| `/api/ml/risk/predict` | 26 UCI credit features | Production Gradient Boosting default probability & 0–100 risk score |
| `GET` | `/sample/{model}` | — | 5 realistic test-window feature samples |
| `POST`| `/predict/{model}` | `{"features": {...}}` | Legacy scoring for 5 longitudinal INR models |
| `POST`| `/explain/{model}` | `{"features": {...}}` | SHAP factor attributions for a single feature vector |
| `GET` | `/api/sms/health` | — | SMS NLP model availability, categories, metadata |
| `POST`| `/api/sms/classify` | `{"text": "..."}` | Two-stage SMS check: spam filter -> category label |
| `POST`| `/api/sms/classify/batch` | `{"messages": [...]}` | Batch classification preserving message order |
| `GET` | `/api/data/{resource}` | — | List user documents (`?user_id=` or `X-User-Id` header) |
| `PUT` | `/api/data/{resource}/{id}` | `payload: {...}` | Upsert user document by resource and record ID |
| `DELETE`| `/api/data/{resource}/{id}` | — | Delete a user document by resource and record ID |

*Allowed finance resources: `transactions`, `accounts`, `budgets`, `goals`, `alerts`, `recommendations`.*

---

## PostgreSQL Persistence Layer (`database.py`)

WealthSync persists user financial records as JSONB documents in PostgreSQL:

```sql
CREATE TABLE finance_records (
    user_id     VARCHAR(120) NOT NULL,
    resource    VARCHAR(40) NOT NULL,
    record_id   VARCHAR(120) NOT NULL,
    payload     JSONB NOT NULL,
    updated_at  TIMESTAMP WITH TIME ZONE NOT NULL,
    PRIMARY KEY (user_id, resource, record_id)
);
```

### Persistence Features:
- **Partitioned User Namespaces**: Multi-tenant separation keyed on `user_id`. Clients specify the partition key via query parameter (`?user_id=local-user`) or the `X-User-Id` header (the header takes precedence).
- **Graceful Fault Tolerance**: During startup (`lifespan` in `main.py`), database connection is attempted. If PostgreSQL is unavailable, the application starts normally: ML and SMS endpoints remain fully operational, while data endpoints return `503 Service Unavailable`.
- **Connection Pooling**: Uses SQLAlchemy 2.0 with `psycopg` (v3 binary), pre-ping enabled, and connection pooling (`pool_size=5`, `max_overflow=5`).

---

## Serving Flows

### 1. Production Spending & Risk Prediction
```
Client Request -> POST /api/ml/{spending,risk}/predict
       |
       v
Pydantic Request Validation (SpendingPredictRequest / RiskPredictRequest)
       * Checks exact feature column names and order against feature_columns.json
       * Rejects unknown extra fields (extra='forbid')
       |
       v
Service Layer (services.py)
       * Lazy loads and caches complete fitted Pipeline (model.joblib)
       * Runs pipeline.predict(DataFrame) with integrated preprocessing
       |
       v
Format Response (SpendingPredictResponse / RiskPredictResponse)
```

### 2. Explainable AI (SHAP)
```
Client Request -> POST /explain/{model}
       |
       v
Service Layer (services.py)
       * Transforms features using fitted ColumnTransformer / Scaler
       * Runs TreeExplainer (Tree models) or LinearExplainer (Linear models)
       * Extracts raw SHAP attribution values
       |
       v
Sort by absolute impact and return top-12 ranked factors with direction (+/-)
```

### 3. Two-Stage SMS Classification
```
Client Request -> POST /api/sms/classify
       |
       v
Pydantic Validation (rejects empty/whitespace text)
       |
       v
sms_service.py -> sms.sms_classifier.SmsClassifier
       * Text normalization: lowercase, URL/phone token masking, punctuation removal
       * Stage 1: TF-IDF + MultinomialNB spam filter -> if spam: DISCARDED (SPAM/NOISE)
       * Stage 2: TF-IDF + MultinomialNB category classifier -> credit | debit | other
       |
       v
Return status, predicted category, and confidence percentages
```

---

## Error Handling & HTTP Status Standards

All errors conform to a unified error response envelope:
```json
{
  "success": false,
  "error": {
    "code": "INVALID_FEATURES",
    "message": "Detailed description of the error"
  }
}
```

| HTTP Status | Error Code | Circumstance |
|---|---|---|
| `400 Bad Request` | `INVALID_FEATURES` | Missing, extraneous, or invalid feature values in ML payload |
| `400 Bad Request` | `INVALID_SMS` | Empty or malformed text payload sent to SMS endpoints |
| `404 Not Found` | `NOT_FOUND` | Unknown finance resource or legacy model name |
| `503 Service Unavailable` | `MODEL_UNAVAILABLE` | Requested legacy model artifact not found on disk |
| `503 Service Unavailable` | `DATABASE_UNAVAILABLE` | PostgreSQL connection failure during user data operations |
| `500 Internal Error` | `PREDICTION_FAILED` | Internal computation error during model inference or SHAP |

---

## Conventions & Rules

1. **Backend Serves; ML Trains**: Never implement model fitting, training loops, or raw feature extraction inside `backend/`. Training belongs exclusively in `ml/` and `sms/`.
2. **Stable Contracts**: Do not change endpoint names or response payloads without coordinating with `app/lib/services/finance_repository.dart`.
3. **Honest Confidence**: Always report model limitations transparently as documented in `metadata.json`. Never report synthetic certainty.
4. **Python Interpreter**: Standard execution environment is Anaconda Python (`C:\Users\SURAJ\anaconda3\python.exe`).
