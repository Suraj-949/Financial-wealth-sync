# WealthSync — AI-Powered Personal Wealth & Financial Intelligence Platform

WealthSync is an intelligent personal finance platform that bridges real-world transaction management, automated SMS expense tracking, machine learning forecasts, and explainable AI (XAI) insights. Built with a **Flutter** mobile client (dark fintech theme), a **FastAPI** Python intelligence backend, **PostgreSQL** partitioned document persistence, and scikit-learn/XGBoost machine learning pipelines.

---

## Architecture Overview

```
                                      +-------------------------------------------------+
                                      |            WealthSync Flutter Mobile App        |
                                      |   (Android / iOS / Web - Dark Fintech UI)       |
                                      +------------------------+------------------------+
                                                               |
                                   HTTP / REST (JSON)          |  Dual-Mode: Demo / Live
                                   API Requests                |  User Partitioning
                                                               v
                                      +-------------------------------------------------+
                                      |             FastAPI Backend Service             |
                                      |          (Uvicorn / Python 3.13 / :8000)        |
                                      +----+-------------------+-------------------+----+
                                           |                   |                   |
                     +---------------------+                   |                   +---------------------+
                     v                                         v                                         v
   +------------------------------------+    +------------------------------------+    +------------------------------------+
   |        PostgreSQL Database         |    |      Production ML Pipelines       |    |       Two-Stage SMS NLP            |
   |   `finance_records` (JSONB)        |    |   * BLS Spending (RandomForest)    |    |   * Stage 1: Spam/Noise Filter     |
   |   User-partitioned transactions,   |    |   * UCI Credit Risk (GradBoost)    |    |   * Stage 2: Category Classifier   |
   |   accounts, budgets, goals, alerts |    |   * 5 INR Longitudinal Models      |    |     (credit / debit / other)       |
   |   and smart recommendations        |    |   * SHAP Explainability (XAI)      |    |   TF-IDF + Multinomial Naive Bayes |
   +------------------------------------+    +------------------------------------+    +------------------------------------+
```

---

## Core Capabilities

1. **Personal Financial Dashboard**
   - Real-time aggregation of income, expenses, documented savings, and financial wellness score (0–100).
   - Six-month historical expense trends with forecast overlay and category breakdown donut charts.
   - Smart AI insights, payment optimization suggestions, and masked account balances.

2. **Automated SMS Transaction Tracking**
   - Device inbox scanning (`flutter_sms_inbox`) with banking heuristic filters and pagination.
   - Two-stage NLP pipeline (Spam Filter -> Category Classifier: Credit / Debit / Other).
   - Regex-based transaction extraction (amount, merchant, date) with 1-click ledger import.
   - Interactive SMS Timeline with month-by-month historical review.

3. **Machine Learning & Predictive Forecasting**
   - **Production Spending Model**: Random Forest regressor trained on BLS CE 2004 survey data predicting next-quarter household expenditure ($TOTEXPPQ scale, $R^2 = 0.5367$).
   - **Production Credit Risk Model**: Gradient Boosting regressor on UCI Credit Card Default predicting 30-day default probability mapped to 0–100 risk score and bands (Low/Medium/High, ROC-AUC = 0.7877).
   - **Longitudinal INR Models**: 5 models (spending, savings, wellness, risk, payment) trained on a 48-month panel with chronological split.

4. **Explainable AI (XAI)**
   - TreeSHAP and LinearSHAP attribution for every ML prediction.
   - Visual contribution waterfall and bar charts answering *"Why this score?"* for maximum transparency.

5. **Multi-Tenant Persistence & Demo Mode**
   - Toggle seamlessly between offline hermetic **Demo Mode** and live **PostgreSQL** storage.
   - Partitioned by user namespace (`user_id` query param or `X-User-Id` header).
   - Reactive UI refresh across all tabs when data changes or demo mode toggles.

6. **AI Copilot**
   - Natural language financial assistance grounded in user transaction history, ML forecasts, and SHAP factor attributions.

---

## Technology Stack

| Layer | Technologies |
|---|---|
| **Mobile Frontend** | Flutter 3.38.9, Dart 3.10.8, `fl_chart`, `http`, `intl`, `shared_preferences`, `flutter_sms_inbox`, `permission_handler` |
| **Backend API** | FastAPI 0.115+, Uvicorn, Pydantic v2, Python 3.13 (Anaconda) |
| **Database & ORM** | PostgreSQL 15+, SQLAlchemy 2.0+, `psycopg` (v3 binary) |
| **Machine Learning** | Scikit-learn 1.6.1, XGBoost 2.0+, SHAP 0.45+, NumPy, Pandas, Joblib |
| **NLP & Text** | Scikit-learn TF-IDF Vectorizer + Multinomial Naive Bayes |
| **Testing & CI** | `pytest`, `pytest-asyncio`, `flutter test` (20 unit/widget tests), `flutter analyze` |

---

## Project Directory Layout

```
Financial wealth sync/
|-- app/                             # Flutter mobile frontend
|   |-- lib/
|   |   |-- app/                     # App configuration, theme tokens, routes, constants
|   |   |-- models/                  # Domain models (Transaction, Account, Prediction, etc.)
|   |   |-- screens/                 # UI screens (dashboard, sms, risk, xai, copilot, budget...)
|   |   |-- services/                # FinanceRepository, ApiClient, SmsInboxService, Importer
|   |   |-- utils/                   # Formatters (INR, percentages, dates)
|   |   `-- widgets/                 # Reusable UI components (AppCard, Pill, TagBadge, etc.)
|   |-- test/                        # Flutter widget and unit test suite
|   |-- doc/                         # Frontend architecture, agent instructions, business docs
|   `-- README.md                    # Mobile client guide
|-- backend/                         # FastAPI Python intelligence server
|   |-- main.py                      # Route definitions, CORS, error handling, lifespan
|   |-- services.py                  # Model caching, prediction logic, SHAP attribution
|   |-- database.py                  # PostgreSQL schema (JSONB document store) & CRUD
|   |-- sms_service.py               # Adapter for the two-stage SMS classifier
|   |-- schemas.py                   # Pydantic v2 request/response validation schemas
|   |-- samples.py                   # Verified test-window payloads
|   |-- run_backend.ps1              # Backend launch script (uvicorn on port 8000)
|   |-- start_database.ps1           # PostgreSQL service helper script
|   |-- requirements.txt             # Python dependencies
|   |-- ML_API_DOCUMENTATION.md      # Exhaustive API reference
|   |-- POSTGRESQL.md                # Database setup instructions
|   |-- test_ml_api.py               # ML endpoint pytest test suite
|   |-- test_sms_api.py              # SMS endpoint pytest test suite
|   `-- doc/                         # Backend architecture, agent instructions, business docs
|-- ml/                              # Machine learning training & artifacts
|   |-- models/                      # Production models (spending Random Forest, risk GradBoost)
|   |-- artifacts/                   # 5 longitudinal INR model artifacts
|   |-- Dataset/                     # Raw and integrated datasets
|   |-- features/                    # Feature engineering & target generation modules
|   |-- training/                    # Model training scripts
|   |-- evaluation/                  # Model evaluation scripts
|   |-- explainability/              # SHAP calculation scripts
|   |-- reports/                     # Model performance summaries and SHAP plots
|   `-- README.md                    # ML documentation and validation metrics
|-- sms/                             # SMS NLP classification package
|   |-- sms_classifier.py            # Two-stage classifier implementation
|   |-- artifacts/                   # Persisted vectorizers and Naive Bayes models
|   `-- README.md                    # SMS classification guide
`-- README.md                        # Master project documentation (this file)
```

---

## Quickstart Guide

### Prerequisites
- **Python**: Python 3.13 (Anaconda distribution recommended)
- **Flutter SDK**: Flutter 3.38.9+ / Dart 3.10.8+
- **PostgreSQL**: PostgreSQL 15+ running locally or via Docker
- **OS**: Windows / Linux / macOS (Windows PowerShell scripts included)

---

### 1. Database Setup (PostgreSQL)

WealthSync uses PostgreSQL to persist user ledger documents as JSONB.

1. Ensure the PostgreSQL service is running:
   ```powershell
   powershell -File backend/start_database.ps1
   ```
2. Configure credentials in `backend/.env` (or copy from `backend/.env.example`):
   ```env
   POSTGRES_DB=wealthsync
   POSTGRES_USER=wealthsync
   POSTGRES_PASSWORD=wealthsync_dev
   POSTGRES_HOST=127.0.0.1
   POSTGRES_PORT=5432
   ```
3. The database tables (`finance_records`) are created automatically when the backend launches.

---

### 2. Backend API Setup

1. Install backend dependencies:
   ```bash
   pip install -r backend/requirements.txt
   ```
2. Launch the backend server:
   ```powershell
   # Using the PowerShell launcher:
   powershell -File backend/run_backend.ps1

   # Or directly with Uvicorn:
   python -m uvicorn backend.main:app --host 0.0.0.0 --port 8000 --reload
   ```
3. Interactive API documentation is available at:
   - Swagger UI: `http://127.0.0.1:8000/docs`
   - ReDoc: `http://127.0.0.1:8000/redoc`

---

### 3. Mobile App Setup (Flutter)

1. Navigate to the `app/` directory and install dependencies:
   ```bash
   cd app
   flutter pub get
   ```
2. Run code analysis:
   ```bash
   flutter analyze
   ```
3. Run the Flutter test suite:
   ```bash
   flutter test
   ```
4. Launch the application:
   ```bash
   # Run on connected Android device or emulator:
   flutter run

   # Connect to custom backend host (default is http://10.0.2.2:8000 for Android emulator):
   flutter run --dart-define=API_BASE=http://192.168.1.100:8000
   ```

---

## API Summary

| Category | Method | Endpoint | Description |
|---|---|---|---|
| **Health** | `GET` | `/health` | Service liveness, PostgreSQL status, loaded models |
| **Health** | `GET` | `/health/models` | Detailed health of all production and legacy models |
| **Registry** | `GET` | `/models` | Model algorithms, feature sets, targets, and metrics |
| **Production ML** | `POST` | `/api/ml/spending/predict` | Predict next-quarter spending (BLS USD) |
| **Production ML** | `POST` | `/api/ml/risk/predict` | Predict default probability & 0–100 risk score (UCI) |
| **Longitudinal ML** | `GET` | `/sample/{model}` | Realistic test-window feature samples |
| **Longitudinal ML** | `POST` | `/predict/{model}` | Score feature vector for 5 INR models |
| **Explainability** | `POST` | `/explain/{model}` | Top ranked SHAP feature contributions |
| **SMS Classifier** | `GET` | `/api/sms/health` | SMS model pipeline status and category metadata |
| **SMS Classifier** | `POST` | `/api/sms/classify` | Classify single SMS: spam check + category label |
| **SMS Classifier** | `POST` | `/api/sms/classify/batch` | Batch classification for multiple SMS messages |
| **User Data** | `GET` | `/api/data/{resource}` | List user documents (`transactions`, `accounts`, etc.) |
| **User Data** | `PUT` | `/api/data/{resource}/{id}` | Insert or update a user resource document |
| **User Data** | `DELETE`| `/api/data/{resource}/{id}` | Remove a resource document |

*Detailed request/response schemas are documented in [`backend/ML_API_DOCUMENTATION.md`](file:///c:/Users/SURAJ/Desktop/Financial%20wealth%20sync/backend/ML_API_DOCUMENTATION.md).*

---

## Verification & Test Status

Both backend and frontend test suites are fully automated and verified:

- **Backend Pytest**: `39 passed` (100% success rate across ML prediction, input validation, SMS NLP classification, error envelopes, and registry).
  ```bash
  python -m pytest backend/test_ml_api.py backend/test_sms_api.py -v
  ```
- **Flutter Test Suite**: `20 passed` (100% success rate across API client, live PostgreSQL aggregation, SMS timeline, classification screens, and widget tree).
  ```bash
  cd app && flutter test
  ```
- **Static Code Analysis**: Clean with `0 issues` (`flutter analyze`).

---

## License & Notes

WealthSync is developed for research and educational fintech engineering. Machine learning predictions represent statistical decision-support proxies and should not replace professional financial advice.

