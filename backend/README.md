# WealthSync Backend Service (`backend/`)

The WealthSync backend is a high-performance **FastAPI** service that serves as the intelligence, prediction, and persistence engine of the platform. It manages three families of machine learning models, exposes explainable AI (SHAP) attributions, provides natural language SMS transaction classification, and persists user finance documents in **PostgreSQL**.

---

## Key Features

1. **Production ML Prediction APIs**:
   - Next-quarter household spending regressor (BLS CE 2004 Random Forest, $R^2 = 0.5367$).
   - Credit default probability and 0–100 risk score regressor (UCI Credit Default Gradient Boosting, ROC-AUC = 0.7877).
2. **Longitudinal Monthly INR Models**:
   - 5 monthly forecasting models: spending, savings, wellness score (0–100), risk flag, and payment method recommendation.
   - Realistic try-me test samples via `/sample/{model}`.
3. **SHAP Explainability (XAI)**:
   - Feature attribution via TreeSHAP and LinearSHAP exposed over `POST /explain/{model}` for auditable algorithmic decisions.
4. **Two-Stage SMS NLP Classifier**:
   - Stage 1: Spam and noise filter (TF-IDF + Naive Bayes).
   - Stage 2: Transaction categorization into `credit`, `debit`, or `other`.
   - Single message (`/api/sms/classify`) and batch classification (`/api/sms/classify/batch`).
5. **PostgreSQL Document Persistence**:
   - High-performance JSONB document storage in table `finance_records`.
   - Scoped by user namespace (`user_id` parameter or `X-User-Id` header).
   - Resources: `transactions`, `accounts`, `budgets`, `goals`, `alerts`, `recommendations`.
   - Graceful offline fallback: ML and SMS routes remain operational if PostgreSQL is offline.

---

## Directory Layout

```
backend/
|-- main.py                      # FastAPI app entry point, routes, CORS, lifespan & error handlers
|-- services.py                  # Model caching, inference logic, SHAP explainer service
|-- database.py                  # PostgreSQL schema (JSONB document table), engine & CRUD functions
|-- sms_service.py               # Adapter for the two-stage SMS classification pipeline
|-- schemas.py                   # Pydantic v2 validation models for requests and responses
|-- samples.py                   # Verified test-window sample payloads for try-me endpoints
|-- run_backend.ps1              # PowerShell runner: starts uvicorn on :8000 and opens /docs
|-- start_database.ps1           # PowerShell helper to start the local PostgreSQL service
|-- requirements.txt             # Backend Python dependencies
|-- .env.example                 # Environment configuration template
|-- ML_API_DOCUMENTATION.md      # Detailed developer API documentation
|-- POSTGRESQL.md                # PostgreSQL setup and troubleshooting guide
|-- test_ml_api.py               # ML API pytest test suite (27 tests)
|-- test_sms_api.py              # SMS API pytest test suite (12 tests)
`-- doc/                         # Backend-scoped architecture, agent rules, and business docs
```

---

## Setup & Running

### 1. Requirements
- Python 3.13 (Anaconda recommended)
- PostgreSQL 15+ running locally or in Docker

### 2. Environment Configuration
Create a `.env` file in `backend/` (or copy from `.env.example`):
```env
POSTGRES_DB=wealthsync
POSTGRES_USER=wealthsync
POSTGRES_PASSWORD=wealthsync_dev
POSTGRES_HOST=127.0.0.1
POSTGRES_PORT=5432
# Or specify full SQLAlchemy URL:
# DATABASE_URL=postgresql+psycopg://wealthsync:wealthsync_dev@127.0.0.1:5432/wealthsync
```

### 3. Install Dependencies
```bash
pip install -r backend/requirements.txt
```

### 4. Start PostgreSQL
```powershell
powershell -File backend/start_database.ps1
```

### 5. Start the Server
```powershell
# Using PowerShell runner:
powershell -File backend/run_backend.ps1

# Or with Uvicorn directly:
python -m uvicorn backend.main:app --host 0.0.0.0 --port 8000 --reload
```
Interactive documentation will open automatically at `http://127.0.0.1:8000/docs`.

---

## API Endpoints Reference

### Health & Registry
| Method | Endpoint | Description |
|---|---|---|
| `GET` | `/health` | Liveness probe, database connection status, loaded models |
| `GET` | `/health/models` | Detailed availability status for all models |
| `GET` | `/models` | Model registry with algorithms, metrics, and feature lists |

### Production ML Endpoints
| Method | Endpoint | Input | Output |
|---|---|---|---|
| `POST` | `/api/ml/spending/predict` | 22 BLS CE demographic/economic features | Next-quarter expenditure in USD |
| `POST` | `/api/ml/risk/predict` | 26 UCI credit features | Default probability, 0–100 risk score, level |

### Longitudinal Models & Explainability
| Method | Endpoint | Input | Output |
|---|---|---|---|
| `GET` | `/sample/{model}` | — | 5 realistic test-window feature samples |
| `POST` | `/predict/{model}` | `{ "features": {...} }` | INR / 0–100 / class prediction |
| `POST` | `/explain/{model}` | `{ "features": {...} }` | Top-12 ranked SHAP feature contributions |

### SMS Classification
| Method | Endpoint | Input | Output |
|---|---|---|---|
| `GET` | `/api/sms/health` | — | SMS model status and supported categories |
| `POST` | `/api/sms/classify` | `{ "text": "..." }` | Spam filter status, category, confidence |
| `POST` | `/api/sms/classify/batch` | `{ "messages": ["..."] }` | Batch results preserving input ordering |

### User Finance Data (PostgreSQL)
| Method | Endpoint | Description |
|---|---|---|
| `GET` | `/api/data/{resource}` | List all documents for the authenticated user |
| `PUT` | `/api/data/{resource}/{id}` | Upsert a document with the given resource ID |
| `DELETE` | `/api/data/{resource}/{id}` | Delete a document by resource ID |

*Supported resources: `transactions`, `accounts`, `budgets`, `goals`, `alerts`, `recommendations`.*

---

## Testing

Run the full pytest suite (39 tests):
```bash
# Set OpenMP environment variable on Windows if needed:
$env:KMP_DUPLICATE_LIB_OK="TRUE"

# Run tests:
python -m pytest backend/test_ml_api.py backend/test_sms_api.py -v
```

All 39 tests cover:
- Endpoint health checks & database liveness.
- Production spending and risk model validation, missing features, invalid data types, extra forbidden fields, and probability bounds.
- Legacy INR model predictions and SHAP explainability attributions.
- SMS classifier single-message credit/debit/spam checks, batch preserves ordering, and whitespace rejection.

