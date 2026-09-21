"""WealthSync backend - model prediction and SHAP explainability service.

Loads the trained artifacts (ml/artifacts/*) and exposes:
  * predict(name, features)  -> one-call scoring for all 5 models
  * explain(name, features)  -> SHAP contributions for a single prediction

Both return plain JSON-friendly structures consumed by the FastAPI layer and,
later, by the mobile app over the same API.
"""

from __future__ import annotations

import json
from pathlib import Path

import joblib
import numpy as np
import pandas as pd
import shap

ML_DIR = Path(__file__).resolve().parents[1] / "ml"
ARTIFACTS = ML_DIR / "artifacts"

MODELS = ("spending", "savings", "wellness", "risk", "payment")

CLASSIFICATION = {
    "risk": {"label_mapping": {"0": "Low Risk", "1": "High Risk"}},
    "payment": None,  # label_mapping read from artifact
}

CURRENCY = "INR"
MODEL_INFO = {
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

_cache: dict = {}


def _artifact(name: str, key: str):
    if name not in _cache:
        _cache[name] = {}
    if key not in _cache[name]:
        path = ARTIFACTS / name / key
        if key == "model_metadata":
            _cache[name][key] = json.loads(path.with_suffix(".json").read_text("utf-8") if path.with_suffix(".json").exists() else "{}")
        elif key in ("feature_columns", "label_mapping"):
            _cache[name][key] = json.loads(path.with_suffix(".json").read_text("utf-8")) if path.with_suffix(".json").exists() else {}
        elif key == "models":
            _cache[name][key] = joblib.load(ARTIFACTS / name / "model.joblib")
        elif key == "scaler":
            p = ARTIFACTS / name / "scaler.pkl"
            _cache[name][key] = joblib.load(p) if p.exists() else None
        else:
            raise KeyError(key)
    return _cache[name][key]


def model_registry() -> dict:
    registry = {}
    for name in MODELS:
        meta = _artifact(name, "model_metadata")
        registry[name] = {
            "model": name,
            "algorithm": meta.get("algorithm"),
            "target": MODEL_INFO[name]["target"],
            "kind": MODEL_INFO[name]["kind"],
            "description": MODEL_INFO[name]["desc"],
            "features": _artifact(name, "feature_columns"),
            "test_metrics": meta.get("metrics", {}).get("test", {}),
            "note": meta.get("notes"),
        }
    return registry


def signed_expm1(y) -> float:
    return round(float(np.sign(y) * np.expm1(np.abs(y))), 2)


def _features(name: str) -> dict[str, float]:
    fm = _artifact(name, "feature_columns") or {}
    return {k: {"value": float(v)} for k, v in fm.items()}


def predict(name: str, features: dict) -> dict:
    if name not in MODEL_INFO:
        raise ValueError(f"unknown model '{name}' (expected one of {MODELS})")
    cols = _artifact(name, "feature_columns")
    missing = [c for c in (cols or []) if c not in features]
    if missing:
        raise ValueError(f"missing features: {missing[:8]} ...")

    X = pd.DataFrame([{c: float(features[c]) for c in cols}])
    model = _artifact(name, "models")
    scaler = _artifact(name, "scaler")
    if scaler is not None:
        Xn = scaler.transform(X)
    else:
        Xn = X

    target = MODEL_INFO[name]["target"]
    base = {"model": name, "target": target,
            "algorithm": _artifact(name, "model_metadata").get("algorithm"),
            "currency": CURRENCY}

    if name in ("spending", "savings"):
        base.update({
            "kind": "regression",
            "prediction": signed_expm1(float(model.predict(Xn)[0])),
            "note": "prediction in INR (inverse of signed-log1p training space)",
        })
    elif name == "wellness":
        score = int(round(float(model.predict(Xn)[0])))
        score = max(0, min(100, score))
        base.update({"kind": "regression", "prediction": score,
                     "note": "0-100 score; label is rule-derived (see model metadata)"})
    elif name == "risk":
        proba = model.predict_proba(Xn)[0]
        cls = int(model.predict(Xn)[0])
        lm = _artifact(name, "label_mapping")
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
        lm = _artifact(name, "label_mapping") or {}
        inv = {int(k): v for k, v in lm.items()}
        base.update({
            "kind": "classification",
            "prediction": inv.get(cls, str(cls)),
            "probability": float(proba[cls]),
            "probabilities": {inv.get(i, str(i)): float(p) for i, p in enumerate(proba)},
        })
    return base


def explain(name: str, features: dict, top: int = 12) -> dict:
    cols = _artifact(name, "feature_columns")
    missing = [c for c in (cols or []) if c not in features]
    if missing:
        raise ValueError(f"missing features: {missing[:8]} ...")
    X = pd.DataFrame([{c: float(features[c]) for c in cols}])
    model = _artifact(name, "models")
    scaler = _artifact(name, "scaler")
    Xn = scaler.transform(X) if scaler is not None else X.to_numpy()

    values = shap.TreeExplainer(model).shap_values(Xn, check_additivity=False) \
        if name != "risk" or model.__class__.__name__ != "LogisticRegression" \
        else shap.LinearExplainer(model, masker=Xn).shap_values(Xn)

    class_index = None
    if isinstance(values, list):
        if len(values) == 2 and name == "risk":
            class_index = 1
            row = values[class_index][0]
        else:  # multiclass (payment) -> predicted class
            proba = model.predict_proba(Xn)[0]
            class_index = int(np.argmax(proba))
            row = values[class_index][0]
    else:
        arr = np.asarray(values)
        if arr.ndim == 3:
            proba = model.predict_proba(Xn)[0] if hasattr(model, "predict_proba") else None
            class_index = int(np.argmax(proba)) if proba is not None else 0
            row = arr[0, :, class_index]
        else:
            row = arr[0]

    rows = [{"feature": c, "value": float(features.get(c, 0.0)), "shap": float(v)}
            for c, v in zip(cols, row)]
    rows.sort(key=lambda r: abs(r["shap"]), reverse=True)
    return {
        "model": name,
        "kind": MODEL_INFO[name]["kind"],
        "class_index": class_index,
        "class_label": _class_label(name, class_index),
        "scaled_features": name == "risk",
        "top": rows[:top],
    }


def _class_label(name: str, idx: int | None) -> str | None:
    if idx is None:
        return None
    lm = _artifact(name, "label_mapping")
    if lm:
        return lm.get(str(idx), str(idx))
    return None