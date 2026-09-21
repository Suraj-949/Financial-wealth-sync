# WealthSync Backend — File Architecture

The backend is a thin scoring layer over ML artifacts. `ml/` produces those artifacts.

```
backend/
├── __init__.py          # makes the package importable (relative imports)
├── main.py              # FastAPI app: /health, /models, /sample/{model},
│                        # POST /predict/{model}, POST /explain/{model}; CORS
├── services.py          # PredictionService: loads model.joblib / scaler.pkl /
│                        #   feature_columns.json / label_mapping.json → predict + explain
├── samples.py           # test-window feature payloads per model
├── requirements.txt     # fastapi, uvicorn
├── run_backend.ps1      # uvicorn on :8000 + opens /docs
└── doc/                 # backend-scoped docs (BUSINESS, AGENTS, ARCHITECTURE)
```

## Endpoints

| Method | Path | Body | Response |
|---|---|---|---|
| GET | `/health` | – | service status |
| GET | `/models` | – | list of served models + metadata |
| GET | `/sample/{model}` | – | `{ "samples": [...] }` test-window features |
| POST | `/predict/{model}` | `features: {...}` | predictions |
| POST | `/explain/{model}` | `features: {...}` | SHAP explanation |

## Artifacts the backend consumes (`ml/artifacts/<model>/`)

Each of `spending`, `savings`, `wellness`, `risk`, `payment` has:
- `model.joblib` — serialized estimator (XGB/RF/GBM)
- `feature_columns.json` — exact feature ordering the model expects
- `label_mapping.json` — label → index (classifiers)
- `scaler.pkl` — fitted StandardScaler (used where applicable)
- `model_metadata.json` + `training_metrics.json` — honest metadata/limits
- `ml/reports/` — `model_performance_summary.json` + `shap_<model>.csv/.png` (consumed by `/explain`)

## Serving flow
```
client → POST /predict/{model}
       → main.py (validate body) → services.py (load artifact once, cache)
       → feature reorder via feature_columns.json → scaler (if any) → model.predict
       → JSON response

client → POST /explain/{model}
       → services.py → SHAP values → per-feature attribution → JSON response
```

## Conventions
- Python interpreter: `C:\Users\SURAJ\anaconda3\python.exe` (system `python` is blocked).
- Relative imports inside `backend\` (`from . import services`).
- No training code lives here — training stays in `ml/`.