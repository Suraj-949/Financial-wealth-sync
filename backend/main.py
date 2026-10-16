"""WealthSync - FastAPI backend exposing the 5 trained ML models + SHAP explainer.

Run from repo root:
    C:/Users/SURAJ/anaconda3/python.exe -m uvicorn backend.main:app --host 0.0.0.0 --port 8000

or:
    powershell -File backend\run_backend.ps1

Endpoints:
  GET  /health                    - basic health check
  GET  /health/models             - detailed model health status
  GET  /models                    - registry: algorithms, test metrics, feature lists
  GET  /sample/{model}            - realistic test-window feature payloads (try-me inputs)
  POST /api/ml/spending/predict   - predict next-quarter total expenditure
  POST /api/ml/risk/predict       - predict default probability + risk score
  POST /predict/{model}           - legacy: score one feature vector (all 5 models)
  POST /explain/{model}           - SHAP contributions for one feature vector

Interactive docs: GET /docs  (the mobile app consumes this API)
"""

from __future__ import annotations

from fastapi import FastAPI, HTTPException, Request, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse

from . import services, samples, sms_service
from .schemas import (
    SpendingPredictRequest, SpendingPredictResponse,
    RiskPredictRequest, RiskPredictResponse,
    SmsClassifyRequest, SmsBatchClassifyRequest, SmsClassifyResponse,
    ModelHealthResponse, ErrorResponse
)


# ---- Exception Handler Functions (defined before app creation) ----

def _validation_exception_handler(request: Request, exc: RequestValidationError):
    """Convert Pydantic validation errors (422) to our standard 400 format."""
    errors = exc.errors()
    if errors:
        err = errors[0]
        field = ".".join(str(x) for x in err["loc"]) if err["loc"] else "unknown"
        msg = f"Invalid value for '{field}': {err['msg']}"
        code = "INVALID_FEATURES"
    else:
        msg = "Invalid request payload"
        code = "INVALID_FEATURES"
    
    return JSONResponse(
        status_code=status.HTTP_400_BAD_REQUEST,
        content={"success": False, "error": {"code": code, "message": msg}}
    )


def _value_error_handler(request: Request, exc: ValueError):
    """Handle ValueError from services as 400."""
    return JSONResponse(
        status_code=status.HTTP_400_BAD_REQUEST,
        content={"success": False, "error": {"code": "INVALID_FEATURES", "message": str(exc)}}
    )


def _generic_exception_handler(request: Request, exc: Exception):
    """Catch-all for unexpected errors."""
    import logging
    logging.error(f"Unhandled error: {exc}", exc_info=True)
    return JSONResponse(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        content={"success": False, "error": {"code": "INTERNAL_ERROR", "message": "Service temporarily unavailable"}}
    )


# ---- App Setup ----

app = FastAPI(title="WealthSync ML API", version="1.0.0")

# Override default exception handlers (must be done after app creation)
from fastapi.exceptions import RequestValidationError
app.add_exception_handler(RequestValidationError, lambda r, e: _validation_exception_handler(r, e))
app.add_exception_handler(ValueError, lambda r, e: _value_error_handler(r, e))
app.add_exception_handler(Exception, lambda r, e: _generic_exception_handler(r, e))

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ---- Health ----

@app.get("/health")
def health() -> dict:
    return {"status": "ok", "models": list(services.PRODUCTION_MODELS.keys()) + ["sms"]}


@app.get("/health/models", response_model=ModelHealthResponse)
def model_health() -> dict:
    """Detailed model health status."""
    try:
        health = services.model_health()
        return {"success": True, "models": health}
    except Exception as e:
        raise HTTPException(500, f"Health check failed: {e}")


# ---- Model Registry ----

@app.get("/models")
def models() -> dict:
    return services.model_registry()


# ---- Sample Payloads (Legacy) ----

@app.get("/sample/{model}")
async def sample(model: str) -> dict:
    try:
        payloads = samples.sample_payloads(model)
    except ValueError as e:
        raise HTTPException(404, str(e))
    return {"model": model, "count": len(payloads), "samples": payloads}


# ---- Production Spending Prediction ----

@app.post("/api/ml/spending/predict", response_model=SpendingPredictResponse)
async def predict_spending(request: SpendingPredictRequest) -> dict:
    """Predict next-quarter total expenditure using the production Random Forest model.
    
    Input: exact raw features from spending/random_forest/feature_columns.json
    Output: predicted expenditure in USD (2004 dollars, TOTEXPPQ scale)
    """
    try:
        features = request.model_dump()
        result = services.predict_spending(features)
        return {"success": True, "data": result}
    except ValueError as e:
        return JSONResponse(status_code=400, content={"success": False, "error": {"code": "INVALID_FEATURES", "message": str(e)}})
    except Exception as e:
        import logging
        logging.error(f"Spending prediction failed: {e}")
        raise HTTPException(500, {"code": "PREDICTION_FAILED", "message": "Spending prediction service temporarily unavailable"})


# ---- Production Risk Prediction ----

@app.post("/api/ml/risk/predict", response_model=RiskPredictResponse)
async def predict_risk(request: RiskPredictRequest) -> dict:
    """Predict default probability and risk score using the production Gradient Boosting model.
    
    Input: exact raw features from risk/gradient_boosting/feature_columns.json
    Output: default_probability (0-1), risk_score (0-100), risk_level (Low/Medium/High)
    """
    try:
        features = request.model_dump()
        result = services.predict_risk(features)
        return {"success": True, "data": result}
    except ValueError as e:
        return JSONResponse(status_code=400, content={"success": False, "error": {"code": "INVALID_FEATURES", "message": str(e)}})
    except Exception as e:
        import logging
        logging.error(f"Risk prediction failed: {e}")
        raise HTTPException(500, {"code": "PREDICTION_FAILED", "message": "Risk prediction service temporarily unavailable"})


# ---- Legacy Generic Prediction (all 5 models) ----

@app.post("/predict/{model}")
async def predict(model: str, payload: dict) -> dict:
    """Legacy endpoint for all 5 models (ml/artifacts)."""
    try:
        result = services.predict(model, payload.get("features", payload))
    except ValueError as e:
        return JSONResponse(status_code=400, content={"success": False, "error": {"code": "INVALID_FEATURES", "message": str(e)}})
    except FileNotFoundError:
        raise HTTPException(503, {"code": "MODEL_UNAVAILABLE", "message": f"Legacy model '{model}' artifacts not found"})
    except Exception as e:
        raise HTTPException(500, {"code": "PREDICTION_FAILED", "message": f"Prediction failed: {e}"})
    return result


# ---- Legacy Explain ----

@app.post("/explain/{model}")
async def explain(model: str, payload: dict) -> dict:
    try:
        result = services.explain(model, payload.get("features", payload))
    except ValueError as e:
        return JSONResponse(status_code=400, content={"success": False, "error": {"code": "INVALID_FEATURES", "message": str(e)}})
    except Exception as e:
        raise HTTPException(500, {"code": "EXPLAIN_FAILED", "message": f"Explain failed: {e}"})
    return result


# ---- SMS Transaction Classifier (two-stage text pipeline) ----

@app.get("/api/sms/health")
def sms_health() -> dict:
    """Availability + metadata for the SMS spam/category pipeline."""
    try:
        return {"success": True, "sms": sms_service.sms_health()}
    except Exception as e:
        raise HTTPException(500, {"code": "SMS_UNAVAILABLE", "message": f"SMS model unavailable: {e}"})


@app.post("/api/sms/classify", response_model=SmsClassifyResponse)
async def sms_classify(request: SmsClassifyRequest) -> dict:
    """Classify one raw SMS: spam/noise filter, then credit/debit/other category."""
    try:
        return {"success": True, "data": sms_service.classify_sms(request.text)}
    except ValueError as e:
        return JSONResponse(status_code=400, content={"success": False, "error": {"code": "INVALID_SMS", "message": str(e)}})
    except Exception as e:
        import logging
        logging.error(f"SMS classification failed: {e}")
        raise HTTPException(500, {"code": "SMS_FAILED", "message": "SMS classification service temporarily unavailable"})


@app.post("/api/sms/classify/batch", response_model=SmsClassifyResponse)
async def sms_classify_batch(request: SmsBatchClassifyRequest) -> dict:
    """Classify a batch of raw SMS messages (order preserved)."""
    try:
        results = sms_service.classify_sms_batch(request.messages)
        return {"success": True, "data": {"count": len(results), "results": results}}
    except ValueError as e:
        return JSONResponse(status_code=400, content={"success": False, "error": {"code": "INVALID_SMS", "message": str(e)}})
    except Exception as e:
        import logging
        logging.error(f"SMS batch classification failed: {e}")
        raise HTTPException(500, {"code": "SMS_FAILED", "message": "SMS classification service temporarily unavailable"})