"""WealthSync - shared training utilities.

Responsibilities:
  * reproducible, TIME-AWARE train/validation/test splits (no future leakage)
  * per-candidate hyper-parameter search evaluated on the validation window
  * metric computation for regression & classification
  * serialisation of models + preprocessing + metadata artifacts
"""

from __future__ import annotations

import itertools
import json
from datetime import date
from pathlib import Path
from typing import Any

import joblib
import numpy as np
import pandas as pd
from sklearn.metrics import (
    accuracy_score,
    confusion_matrix,
    f1_score,
    mean_absolute_error,
    mean_squared_error,
    precision_score,
    recall_score,
    r2_score,
    roc_auc_score,
)
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler

ARTIFACTS_DIR = Path(__file__).resolve().parents[1] / "artifacts"

# ---------------------------------------------------------------- splits ---

# Time windows for the budgetwise dataset (2021-01 .. 2024-12).
# Sample month = the month whose data the features describe.
TRAIN_MONTHS = ("2021-01", "2023-06")  # inclusive
VAL_MONTHS = ("2023-07", "2023-12")
TEST_MONTHS = ("2024-01", "2024-12")


def split_by_ym(df: pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame]:
    """Split monthly frames by the SAMPLE month (feature time), time-ordered."""
    ym = df["ym_dt"].dt.strftime("%Y-%m")

    def window(lo: str, hi: str) -> pd.Series:
        return (ym >= lo) & (ym <= hi)

    train = df[window(*TRAIN_MONTHS)]
    val = df[window(*VAL_MONTHS)]
    test = df[window(*TEST_MONTHS)]
    return train, val, test


def split_transactions_by_date(df: pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame]:
    """Split transaction frames by transaction date (time-ordered)."""
    d = pd.to_datetime(df["date"])

    def window(lo: str, hi: str) -> pd.Series:
        return (d >= pd.Timestamp(lo)) & (d <= pd.Timestamp(hi))

    # train/val/test months mirror the monthly calendar splits above.
    test = df[window("2024-01-01", "2024-12-31")]
    val = df[window("2023-07-01", "2023-12-31")]
    train = df[window("2021-01-01", "2023-06-30")]
    return train, val, test


# ----------------------------------------------------------------- metrics --

def regression_metrics(y_true, y_pred) -> dict[str, float]:
    mse = mean_squared_error(y_true, y_pred)
    return {
        "MAE": round(float(mean_absolute_error(y_true, y_pred)), 3),
        "RMSE": round(float(np.sqrt(mse)), 3),
        "R2": round(float(r2_score(y_true, y_pred)), 4),
    }


def classification_metrics(y_true, y_pred, y_prob=None) -> dict[str, float]:
    n_classes = len(set(y_true))
    metrics = {
        "Accuracy": round(float(accuracy_score(y_true, y_pred)), 4),
        "Precision_weighted": round(float(precision_score(y_true, y_pred, average="weighted", zero_division=0)), 4),
        "Recall_weighted": round(float(recall_score(y_true, y_pred, average="weighted", zero_division=0)), 4),
        "F1_weighted": round(float(f1_score(y_true, y_pred, average="weighted", zero_division=0)), 4),
    }
    if n_classes == 2 and y_prob is not None:
        try:
            metrics["ROC_AUC"] = round(float(roc_auc_score(y_true, y_prob)), 4)
        except ValueError:
            pass
    try:
        metrics["Confusion_Matrix"] = confusion_matrix(y_true, y_pred).tolist()
    except Exception:
        pass
    return metrics


# ------------------------------------------------------------------ tuning --

def search_params(estimator, param_grid: dict[str, list], X: pd.DataFrame, y, X_val, y_val,
                  metric_fn, maximize=True, predict_fn=None):
    """Exhaustive small-grid search evaluated on the (time-aware) validation set.

    predict_fn: callable(model, X) -> predictions (defaults to model.predict;
    pass e.g. ``lambda m, X: m.predict_proba(X)[:, 1]`` for ROC-AUC).

    Returns (best_estimator, best_params, best_score).
    """
    if predict_fn is None:
        predict_fn = lambda m, X: m.predict(X)
    keys = list(param_grid)
    best_score, best = None, None
    for combo in itertools.product(*param_grid.values()):
        params = dict(zip(keys, combo))
        model = estimator(**params)
        model.fit(X, y)
        pred = predict_fn(model, X_val)
        score = metric_fn(y_val, pred)
        if best_score is None or (score > best_score if maximize else score < best_score):
            best_score, best = score, (model, params)
    return best[0], best[1], best_score


# -------------------------------------------------------------- artifacts --

def save_predict_api_meta(name: str, model: Any, features: list[str], art_dir: Path, metrics: dict,
                          algorithm: str, version: str, target: str, target_desc: str,
                          scaler=None, label_mapping: dict | None = None, extra: dict | None = None):
    """Persist all artifacts for one trained model (Requirements section 16)."""
    art_dir.mkdir(parents=True, exist_ok=True)
    joblib.dump(model, art_dir / "model.joblib")
    if scaler is not None:
        joblib.dump(scaler, art_dir / "scaler.pkl")
    (art_dir / "feature_columns.json").write_text(json.dumps(features, indent=2), encoding="utf-8")
    metrics_path = art_dir / "training_metrics.json"
    metrics_path.write_text(json.dumps(metrics, indent=2, default=str), encoding="utf-8")

    meta = {
        "model_name": name,
        "algorithm": algorithm,
        "version": version,
        "features": features,
        "target": target,
        "target_description": target_desc,
        "training_date": date.today().isoformat(),
        "metrics": metrics,
        "label_mapping": label_mapping,
        "notes": extra,
    }
    (art_dir / "model_metadata.json").write_text(json.dumps(meta, indent=2, default=str), encoding="utf-8")
    if label_mapping is not None:
        (art_dir / "label_mapping.json").write_text(json.dumps(label_mapping, indent=2), encoding="utf-8")
    print(f"artifacts saved -> {art_dir}")


def get_scaler_fitted(X_train: pd.DataFrame) -> Pipeline:
    """Scaler fitted ONLY on training data (Requirement 12.5 / 12.6)."""
    return Pipeline([("scale", StandardScaler())]).fit(X_train)


# ------------------------------------------------------- signed log space --
# Heavy-tailed financial targets (spending, savings) are trained in signed
# log1p space: sign(y)*log1p(|y|). Predictions are inverse-transformed before
# scoring/reporting, which keeps metrics interpretable in raw currency units.

def signed_log1p(y) -> np.ndarray:
    y = np.asarray(y, dtype=float)
    return np.sign(y) * np.log1p(np.abs(y))


def signed_expm1(y) -> np.ndarray:
    return np.sign(y) * np.expm1(np.abs(y))


def scaled_predict(pipe: Pipeline, X: pd.DataFrame):
    return pipe.predict(X)