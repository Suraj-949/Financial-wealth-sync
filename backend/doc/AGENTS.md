# AGENTS.md — WealthSync Backend (opencode / agent instructions)

Scope: `backend/` (FastAPI service) + the `ml/` pipeline it consumes.

## Environment & Commands

- **Python:** use the Anaconda interpreter. `fastapi 0.141.1` + `uvicorn 0.53.0` are installed.
- **Run the API:** `powershell run_backend.ps1` (from `backend\`) — uvicorn on `:8000`, opens `/docs`.
- **Verify endpoints:** `Invoke-RestMethod http://127.0.0.1:8000/health`, `/models`, then sample
  predict/explain on at least one model per change.
- **Re-train / evaluate ML:** run with the Anaconda python, e.g.
  - `ml\training\train_spending.py` (and savings/wellness/risk/payment)
  - `ml\evaluation\evaluate_models.py`
  - `ml\explainability\shap_explainer.py`
- Model artifacts live in `ml\artifacts\<model>\`; the backend reads them at startup (lazily cache).

## Golden Rules

1. **Backend serves; ML trains.** Never put feature engineering / training logic in `backend/`.
   `ml/` produces artifacts (`model.joblib`, `scaler.pkl`, `feature_columns.json`,
   `label_mapping.json`, `model_metadata.json`); `backend/` only loads and scores.
2. **Keep the contract stable.** `main.py` endpoints `/health`, `/models`, `/sample/{model}`,
   `/predict/{model}`, `/explain/{model}` are consumed by the Flutter app — do not rename/remove
   without updating `app/lib/services/finance_repository.dart`.
3. **Report model limits honestly.** Never return inflated confidence. Debug/`/models` metadata
   reflects real training metrics (payment near-random; spending/savings R² weak; wellness label
   is rule-derived).
4. **Relative imports, not sys.path hacks.** `backend/` is a package (`__init__.py` exists):
   use `from . import services`.
5. **No synthetic data.** Predictions come from models; samples come from real test-window rows.

## Layout (backend + consumed ml artifacts)
- `backend/main.py` — routes + CORS + `/docs` wiring.
- `backend/services.py` — `PredictionService`: artifact loading + predict/explain.
- `backend/samples.py` — test-window sample payloads per model.
- `backend/requirements.txt` / `run_backend.ps1` — deps + run script.
- `ml/artifacts/<model>/*` — the files the backend serves (see `ml/README.md`).

## Verify before finishing
Every change to `backend/`: restart uvicorn, hit `/health` and `/models`, then run one
`/predict/{model}` + `/explain/{model}` and confirm the response shape is unchanged.

## Status
- All 5 models trained, evaluated, SHAP'd; backend serving on `:8000`.
- Next: `GET /api/dashboard` aggregate + copilot grounding pipeline.
