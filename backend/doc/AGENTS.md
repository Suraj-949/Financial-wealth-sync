# AGENTS.md — WealthSync Backend Guidelines

Scope: `backend/` (FastAPI service), its PostgreSQL document persistence layer, and the `ml/` and `sms/` pipelines it consumes.

---

## Environment & Commands

- **Python Interpreter**: Use the Anaconda Python interpreter (`C:\Users\SURAJ\anaconda3\python.exe`). System `python` might lack required packages or have permissions issues.
- **Run Backend**:
  ```powershell
  # Using the PowerShell launcher:
  powershell -File backend\run_backend.ps1

  # Or manually from the repository root:
  C:\Users\SURAJ\anaconda3\python.exe -m uvicorn backend.main:app --host 0.0.0.0 --port 8000 --reload
  ```
- **Run Database Helper**:
  ```powershell
  powershell -File backend\start_database.ps1
  ```
- **Execute Pytest Suite (39 Tests)**:
  ```powershell
  $env:KMP_DUPLICATE_LIB_OK="TRUE"
  C:\Users\SURAJ\anaconda3\python.exe -m pytest backend/test_ml_api.py backend/test_sms_api.py -v
  ```
- **Verify Endpoints Manually**:
  ```powershell
  Invoke-RestMethod http://127.0.0.1:8000/health
  Invoke-RestMethod http://127.0.0.1:8000/health/models
  Invoke-RestMethod http://127.0.0.1:8000/models
  ```

---

## Golden Rules

1. **Backend Serves; ML Trains**:
   - Never implement model training, hyperparameter tuning, or dataset preprocessing loops inside `backend/`.
   - `ml/` and `sms/` produce artifacts (`model.joblib`, `preprocessor.joblib`, `feature_columns.json`, `metadata.json`); `backend/` only loads, caches, and scores.
2. **Keep the Contract Stable**:
   - Endpoints (`/health`, `/models`, `/api/ml/spending/predict`, `/api/ml/risk/predict`, `/api/sms/classify`, `/api/data/{resource}`) are consumed directly by the Flutter app.
   - Do not alter route paths, required fields, or response structures without synchronizing with `app/lib/services/finance_repository.dart`.
3. **Report Model Limits Honestly**:
   - Never artificially inflate predictions or confidences.
   - Endpoint `/models` exposes real test metrics directly from `metadata.json` (e.g. payment accuracy near random chance, synthetic circularity on wellness score, BLS spending USD scale).
4. **Relative Imports, Not sys.path Hacks**:
   - `backend/` is a structured Python package (`__init__.py` present).
   - Use package-relative imports: `from . import services, samples, sms_service, database`.
5. **No Synthetic Training Data in Production**:
   - Samples delivered via `/sample/{model}` must come from real test-window rows (`samples.py`), not randomly generated numbers.
6. **Resilient Persistence**:
   - The backend must start cleanly even if PostgreSQL is temporarily offline.
   - In case of database disconnection, `/health` reports `database: unavailable`, ML and SMS endpoints continue operating normally, and data endpoints return HTTP 503.

---

## Layout Reference

- `backend/main.py`: FastAPI app instance, CORS middleware, custom exception handlers, and route definitions.
- `backend/services.py`: Prediction service handling model caching, DataFrame construction, inference, and SHAP explainability.
- `backend/database.py`: SQLAlchemy engine, `FinanceRecord` model (JSONB document storage), and CRUD functions.
- `backend/sms_service.py`: Adapter wrapping the `sms` package (`sms_classifier.py`).
- `backend/schemas.py`: Pydantic v2 schemas enforcing strict request validation (`extra='forbid'`).
- `backend/samples.py`: Static sample feature vectors from the model test windows.
- `backend/test_ml_api.py`: 27 pytest tests validating ML endpoints, data types, and error codes.
- `backend/test_sms_api.py`: 12 pytest tests validating SMS classifier logic, batch handling, and error cases.
- `ml/models/`: Serialized production model pipelines (BLS spending and UCI risk).
- `ml/artifacts/`: Serialized longitudinal INR models (spending, savings, wellness, risk, payment).
- `sms/artifacts/`: Serialized two-stage SMS classification vectorizers and models.

---

## Verification Checklist

Before completing any changes to `backend/`:
1. Check that PostgreSQL is accessible (`Invoke-RestMethod http://127.0.0.1:8000/health`).
2. Run `pytest backend/test_ml_api.py backend/test_sms_api.py -v` — all 39 tests must pass.
3. Test one production prediction call (`POST /api/ml/spending/predict` or `POST /api/ml/risk/predict`).
4. Test one SMS classification call (`POST /api/sms/classify`).
5. Confirm standard error formatting (`{"success": false, "error": {"code": "...", "message": "..."}}`).
