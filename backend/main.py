"""WealthSync - FastAPI backend exposing the 5 trained ML models + SHAP explainer.

Run from repo root:
    C:/Users/SURAJ/anaconda3/python.exe -m uvicorn backend.main:app --host 0.0.0.0 --port 8000

or:
    powershell -File backend\run_backend.ps1

Endpoints:
  GET  /health
  GET  /models        registry: algorithms, test metrics, feature lists
  GET  /sample/{model}  realistic test-window feature payloads (try-me inputs)
  POST /predict/{model}  score one feature vector
  POST /explain/{model}  SHAP contributions for one feature vector

Interactive docs: GET /docs  (the mobile app consumes this API)
"""

from __future__ import annotations

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware

from . import services, samples

app = FastAPI(title="WealthSync ML API", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # dev only; restrict in production
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

STATIC = None

@app.get("/health")
def health() -> dict:
    return {"status": "ok", "models": list(services.MODELS)}


@app.get("/models")
def models() -> dict:
    return services.model_registry()


@app.get("/sample/{model}")
async def sample(model: str) -> dict:
    try:
        payloads = samples.sample_payloads(model)
    except ValueError as e:
        raise HTTPException(404, str(e))
    return {"model": model, "count": len(payloads), "samples": payloads}


@app.post("/predict/{model}")
async def predict(model: str, payload: dict) -> dict:
    try:
        result = services.predict(model, payload.get("features", payload))
    except ValueError as e:
        raise HTTPException(400, str(e))
    except Exception as e:  # defensive: never leak stack traces to client
        raise HTTPException(500, f"prediction failed: {e}")
    return result


@app.post("/explain/{model}")
async def explain(model: str, payload: dict) -> dict:
    try:
        result = services.explain(model, payload.get("features", payload))
    except ValueError as e:
        raise HTTPException(400, str(e))
    except Exception as e:
        raise HTTPException(500, f"explain failed: {e}")
    return result