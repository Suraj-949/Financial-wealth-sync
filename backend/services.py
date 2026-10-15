"""WealthSync backend - model prediction and SHAP explainability service.

Loads the trained artifacts (ml/models/*) and exposes:
  * predict_spending(features) -> spending prediction
  * predict_risk(features)     -> risk prediction
  * predict(name, features)    -> generic prediction for all 5 models (legacy)
  * explain(name, features)    -> SHAP contributions for a single prediction

All return plain JSON-friendly structures consumed by the FastAPI layer and,
later, by the mobile app over the same API.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import joblib
import numpy as np
import pandas as pd
import shap

# Model directory
ML_DIR = Path(__file__).resolve().parents[1] / "ml"
MODELS_DIR = ML_DIR / "models"

# Production candidate models
PRODUCTION_MODELS = {
    "spending": "random forest",
    "risk": "gradient boosting",
}

# Model info for metadata
MODEL_INFO = {
    "spending": {
        "target": "total_spend_t_plus_1",
        "kind": "regression",
        "desc": "Next-quarter total expenditure forecast (USD, 2004 dollars)",
        "currency": "USD",
        "output_unit": "dollars",
    },
    "risk": {
        "target": "default payment next month",
        "kind": "classification",
        "desc": "Predicted probability of default next month",
        "currency": None,
        "output_unit": "probability",
    },
}

# Legacy models (from ml/artifacts)
LEGACY_MODELS = ("spending", "savings", "wellness", "risk", "payment")
LEGACY_CLASSIFICATION = {
    "risk": {"label_mapping": {"0": "Low Risk", "1": "High Risk"}},
    "payment": None,
}

LEGACY_CURRENCY = "INR"
LEGACY_MODEL_INFO = {
    "spending": {"target": "future_expense", "kind": "regression",
                 "desc": "Next-month total spending forecast"},
    "savings": {"target": "future_savings", "kind": "regression",
                "desc": "Next-month documented savings forecast"},
    "wellness": {"target": "wellness_score", "kind": "regression",
                 "desc": "Financial wellness score (0-100), rule-derived label"},
    "risk": {"target": "risk", "kind": "classification",
             "desc": "High / low financial risk flag, rule-derived label"},
    "payment": {"target": "payment_mode", "kind": "classification",
                "desc": "Recommended payment method"},
}

# Cache for loaded artifacts
_cache: Dict[str, Dict[str, Any]] = {}


def _artifact_dir(model_name: str, variant: str = None) -> Path:
    """Get artifact directory for a model."""
    if variant:
        return MODELS_DIR / model_name / variant
    # Legacy path
    return ML_DIR / "artifacts" / model_name


def _load_model(model_name: str, variant: str = None) -> Any:
    """Load model from cache or disk."""
    cache_key = f"{model_name}/{variant}" if variant else model_name
    
    if cache_key not in _cache:
        _cache[cache_key] = {}
    
    if "model" not in _cache[cache_key]:
        path = _artifact_dir(model_name, variant) / "model.joblib"
        _cache[cache_key]["model"] = joblib.load(path)
    
    return _cache[cache_key]["model"]


def _load_preprocessor(model_name: str, variant: str = None) -> Optional[Any]:
    """Load preprocessor from cache or disk."""
    cache_key = f"{model_name}/{variant}" if variant else model_name
    
    if cache_key not in _cache:
        _cache[cache_key] = {}
    
    if "preprocessor" not in _cache[cache_key]:
        path = _artifact_dir(model_name, variant) / "preprocessor.joblib"
        _cache[cache_key]["preprocessor"] = joblib.load(path) if path.exists() else None
    
    return _cache[cache_key]["preprocessor"]


def _load_feature_columns(model_name: str, variant: str = None) -> List[str]:
    """Load raw input feature columns."""
    cache_key = f"{model_name}/{variant}" if variant else model_name
    
    if cache_key not in _cache:
        _cache[cache_key] = {}
    
    if "feature_columns" not in _cache[cache_key]:
        path = _artifact_dir(model_name, variant) / "feature_columns.json"
        if path.exists():
            data = json.loads(path.read_text())
            _cache[cache_key]["feature_columns"] = data.get("raw_input_columns", [])
        else:
            _cache[cache_key]["feature_columns"] = []
    
    return _cache[cache_key]["feature_columns"]


def _load_label_mapping(model_name: str, variant: str = None) -> Dict[str, str]:
    """Load label mapping for classification models."""
    cache_key = f"{model_name}/{variant}" if variant else model_name
    
    if cache_key not in _cache:
        _cache[cache_key] = {}
    
    if "label_mapping" not in _cache[cache_key]:
        path = _artifact_dir(model_name, variant) / "label_mapping.json"
        if path.exists():
            _cache[cache_key]["label_mapping"] = json.loads(path.read_text())
        else:
            _cache[cache_key]["label_mapping"] = {}
    
    return _cache[cache_key]["label_mapping"]


def _load_metadata(model_name: str, variant: str = None) -> Dict[str, Any]:
    """Load model metadata."""
    cache_key = f"{model_name}/{variant}" if variant else model_name
    
    if cache_key not in _cache:
        _cache[cache_key] = {}
    
    if "metadata" not in _cache[cache_key]:
        path = _artifact_dir(model_name, variant) / "metadata.json"
        if path.exists():
            _cache[cache_key]["metadata"] = json.loads(path.read_text())
        else:
            _cache[cache_key]["metadata"] = {}
    
    return _cache[cache_key]["metadata"]


def model_registry() -> Dict[str, Any]:
    """Return registry of all available models (legacy + production)."""
    registry = {}
    
    # Production models
    for name, variant in PRODUCTION_MODELS.items():
        meta = _load_metadata(name, variant)
        cols = _load_feature_columns(name, variant)
        registry[name] = {
            "model": name,
            "variant": variant,
            "algorithm": meta.get("model"),
            "target": MODEL_INFO[name]["target"],
            "kind": MODEL_INFO[name]["kind"],
            "description": MODEL_INFO[name]["desc"],
            "currency": MODEL_INFO[name]["currency"],
            "features": cols,
            "test_metrics": meta.get("test_mae", meta.get("test_brier")),
            "status": "production_candidate",
        }
    
    # Legacy models
    for name in LEGACY_MODELS:
        meta = _load_metadata(name)
        cols = _load_feature_columns(name)
        registry[f"{name}_legacy"] = {
            "model": name,
            "variant": None,
            "algorithm": meta.get("algorithm"),
            "target": LEGACY_MODEL_INFO[name]["target"],
            "kind": LEGACY_MODEL_INFO[name]["kind"],
            "description": LEGACY_MODEL_INFO[name]["desc"],
            "currency": LEGACY_CURRENCY,
            "features": cols,
            "test_metrics": meta.get("metrics", {}).get("test", {}),
            "status": "legacy",
        }
    
    return registry


def model_health() -> Dict[str, Any]:
    """Check health/status of all models."""
    health = {}
    
    # Production models
    for name, variant in PRODUCTION_MODELS.items():
        try:
            _load_model(name, variant)
            _load_preprocessor(name, variant)
            _load_feature_columns(name, variant)
            health[name] = {
                "status": "available",
                "variant": variant,
                "kind": MODEL_INFO[name]["kind"],
            }
        except Exception as e:
            health[name] = {
                "status": "unavailable",
                "variant": variant,
                "error": str(e),
            }
    
    # Legacy models (use different keys to avoid collision)
    for name in LEGACY_MODELS:
        legacy_key = f"{name}_legacy"
        try:
            _load_model(name)
            _load_preprocessor(name)
            _load_feature_columns(name)
            health[legacy_key] = {
                "status": "available",
                "variant": None,
                "kind": LEGACY_MODEL_INFO[name]["kind"],
            }
        except Exception as e:
            health[legacy_key] = {
                "status": "unavailable",
                "error": str(e),
            }
    
    return health


def _signed_expm1(y: float) -> float:
    """Inverse of signed log1p transformation."""
    return round(float(np.sign(y) * np.expm1(np.abs(y))), 2)


def _risk_score(probability: float) -> Tuple[float, str]:
    """Convert probability to risk score and band."""
    score = probability * 100
    if score <= 30:
        level = "Low"
    elif score <= 60:
        level = "Medium"
    else:
        level = "High"
    return round(score, 1), level


def predict_spending(features: Dict[str, float]) -> Dict[str, Any]:
    """Predict spending using the production Random Forest model."""
    model_name = "spending"
    variant = "random forest"
    
    cols = _load_feature_columns(model_name, variant)
    missing = [c for c in cols if c not in features]
    if missing:
        raise ValueError(f"Missing required features: {missing[:8]}")
    
    # Create DataFrame with correct column order
    X = pd.DataFrame([{c: float(features[c]) for c in cols}])
    
    model = _load_model(model_name, variant)
    # model is a full Pipeline with 'pre' (ColumnTransformer) + 'model' (RandomForestRegressor)
    # Pipeline predict() returns prediction in original target scale (dollars)
    prediction = float(model.predict(X)[0])
    
    meta = _load_metadata(model_name, variant)
    
    return {
        "model": model_name,
        "variant": variant,
        "target": MODEL_INFO[model_name]["target"],
        "algorithm": meta.get("model"),
        "kind": MODEL_INFO[model_name]["kind"],
        "prediction": round(prediction, 2),
        "currency": MODEL_INFO[model_name]["currency"],
        "unit": MODEL_INFO[model_name]["output_unit"],
        "note": "Predicted next-quarter total expenditure in USD (2004 dollars, TOTEXPPQ scale)",
    }


def predict_risk(features: Dict[str, float]) -> Dict[str, Any]:
    """Predict risk using the production Gradient Boosting model."""
    model_name = "risk"
    variant = "gradient boosting"
    
    cols = _load_feature_columns(model_name, variant)
    missing = [c for c in cols if c not in features and c != "repay_ratio_mean6"]
    if missing:
        raise ValueError(f"Missing required features: {missing[:8]}")
    
    # Create DataFrame with correct column order (include None for missing repay_ratio_mean6)
    X = pd.DataFrame([{c: float(features[c]) if c in features and features[c] is not None else np.nan for c in cols}])
    
    model = _load_model(model_name, variant)
    # model is a full Pipeline with 'pre' (ColumnTransformer) + 'model' (GradientBoostingRegressor)
    # So we call predict directly on the pipeline - it handles preprocessing internally
    probability = float(model.predict(X)[0])
    probability = max(0.0, min(1.0, probability))  # clamp
    
    risk_score_val, risk_level = _risk_score(probability)
    
    meta = _load_metadata(model_name, variant)
    
    return {
        "model": model_name,
        "variant": variant,
        "target": MODEL_INFO[model_name]["target"],
        "algorithm": meta.get("model"),
        "kind": MODEL_INFO[model_name]["kind"],
        "default_probability": round(probability, 4),
        "risk_score": risk_score_val,
        "risk_level": risk_level,
        "note": "Risk score = predicted probability × 100; bands: 0-30 Low, 31-60 Medium, 61-100 High",
    }


# ============================================================
# Legacy prediction (for backward compatibility with /predict/{model})
# ============================================================

LEGACY_CACHE: Dict[str, Dict[str, Any]] = {}


def _legacy_artifact(name: str, key: str):
    if name not in LEGACY_CACHE:
        LEGACY_CACHE[name] = {}
    if key not in LEGACY_CACHE[name]:
        path = ML_DIR / "artifacts" / name / key
        if key == "model_metadata":
            LEGACY_CACHE[name][key] = json.loads(path.with_suffix(".json").read_text("utf-8")) if path.with_suffix(".json").exists() else {}
        elif key in ("feature_columns", "label_mapping"):
            LEGACY_CACHE[name][key] = json.loads(path.with_suffix(".json").read_text("utf-8")) if path.with_suffix(".json").exists() else {}
        elif key == "models":
            LEGACY_CACHE[name][key] = joblib.load(ML_DIR / "artifacts" / name / "model.joblib")
        elif key == "scaler":
            p = ML_DIR / "artifacts" / name / "scaler.pkl"
            LEGACY_CACHE[name][key] = joblib.load(p) if p.exists() else None
        else:
            raise KeyError(key)
    return LEGACY_CACHE[name][key]


def predict(name: str, features: Dict[str, float]) -> Dict[str, Any]:
    """Legacy prediction for all 5 models (ml/artifacts)."""
    if name not in LEGACY_MODEL_INFO:
        raise ValueError(f"Unknown model '{name}' (expected one of {LEGACY_MODELS})")
    
    cols = _legacy_artifact(name, "feature_columns")
    missing = [c for c in (cols or []) if c not in features]
    if missing:
        raise ValueError(f"Missing features: {missing[:8]} ...")
    
    X = pd.DataFrame([{c: float(features[c]) for c in cols}])
    model = _legacy_artifact(name, "models")
    scaler = _legacy_artifact(name, "scaler")
    Xn = scaler.transform(X) if scaler is not None else X
    
    target = LEGACY_MODEL_INFO[name]["target"]
    base = {"model": name, "target": target,
            "algorithm": _legacy_artifact(name, "model_metadata").get("algorithm"),
            "currency": LEGACY_CURRENCY}
    
    if name in ("spending", "savings"):
        base.update({
            "kind": "regression",
            "prediction": _signed_expm1(float(model.predict(Xn)[0])),
            "note": "Prediction in INR (inverse of signed-log1p training space)",
        })
    elif name == "wellness":
        score = int(round(float(model.predict(Xn)[0])))
        score = max(0, min(100, score))
        base.update({"kind": "regression", "prediction": score,
                     "note": "0-100 score; label is rule-derived"})
    elif name == "risk":
        proba = model.predict_proba(Xn)[0]
        cls = int(model.predict(Xn)[0])
        lm = _legacy_artifact(name, "label_mapping")
        base.update({
            "kind": "classification",
            "prediction": lm[str(cls)] if lm else cls,
            "probability": float(proba[cls]),
            "probabilities": {lm[str(i)]: float(p) for i, p in enumerate(proba)} if lm else list(proba),
            "scaled_features": True,
        })
    elif name == "payment":
        proba = model.predict_proba(Xn)[0]
        cls = int(model.predict(Xn)[0])
        lm = _legacy_artifact(name, "label_mapping") or {}
        inv = {int(k): v for k, v in lm.items()}
        base.update({
            "kind": "classification",
            "prediction": inv.get(cls, str(cls)),
            "probability": float(proba[cls]),
            "probabilities": {inv.get(i, str(i)): float(p) for i, p in enumerate(proba)},
        })
    return base


def explain(name: str, features: Dict[str, float], top: int = 12) -> Dict[str, Any]:
    """SHAP explainability (works for both production and legacy models)."""
    # Try production first
    variant = PRODUCTION_MODELS.get(name)
    if variant:
        cols = _load_feature_columns(name, variant)
        model = _load_model(name, variant)
        preprocessor = _load_preprocessor(name, variant)
    else:
        cols = _legacy_artifact(name, "feature_columns")
        model = _legacy_artifact(name, "models")
        preprocessor = _legacy_artifact(name, "scaler")
    
    missing = [c for c in (cols or []) if c not in features]
    if missing:
        raise ValueError(f"Missing features: {missing[:8]} ...")
    
    X = pd.DataFrame([{c: float(features[c]) for c in cols}])
    Xn = preprocessor.transform(X) if preprocessor is not None else X.to_numpy()
    
    # Use appropriate explainer
    if hasattr(model, 'named_steps') and 'model' in model.named_steps:
        estimator = model.named_steps['model']
    else:
        estimator = model
    
    if name == "risk" and estimator.__class__.__name__ == "LogisticRegression":
        values = shap.LinearExplainer(estimator, masker=Xn).shap_values(Xn)
    else:
        values = shap.TreeExplainer(estimator).shap_values(Xn, check_additivity=False)
    
    # Handle multi-class / binary classification
    class_index = None
    if isinstance(values, list):
        if len(values) == 2 and name == "risk":
            class_index = 1
            row = values[class_index][0]
        else:
            proba = estimator.predict_proba(Xn)[0] if hasattr(estimator, 'predict_proba') else None
            class_index = int(np.argmax(proba)) if proba is not None else 0
            row = values[class_index][0]
    else:
        arr = np.asarray(values)
        if arr.ndim == 3:
            proba = estimator.predict_proba(Xn)[0] if hasattr(estimator, 'predict_proba') else None
            class_index = int(np.argmax(proba)) if proba is not None else 0
            row = arr[0, :, class_index]
        else:
            row = arr[0]
    
    rows = [{"feature": c, "value": float(features.get(c, 0.0)), "shap": float(v)}
            for c, v in zip(cols, row)]
    rows.sort(key=lambda r: abs(r["shap"]), reverse=True)
    
    return {
        "model": name,
        "variant": variant,
        "kind": MODEL_INFO.get(name, LEGACY_MODEL_INFO.get(name, {})).get("kind"),
        "class_index": class_index,
        "top": rows[:top],
    }