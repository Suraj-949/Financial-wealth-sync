"""WealthSync - SHAP explainability for all trained models.

For each artifact in ml/artifacts it loads the feature columns + model +
(optional) scaler, rebuilds the same time-aware test features, computes
SHAP values on a sample of the test window, and writes:
  - ml/reports/shap_<model>.csv        mean |SHAP| + top-15 feature importances
  - ml/reports/shap_<model>.png        horizontal bar chart of mean |SHAP|

Notes:
  - For tree models: shap.TreeExplainer (exact).
  - For linear models: shap.LinearExplainer with correlated masker.
  - Regression models predict in signed-log space; SHAP refers to that space.
  - (n*f) values are computed per class for classifiers; reports pool the
    absolute SHAP averaged across classes.
"""

from __future__ import annotations

import json
from pathlib import Path

import joblib
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import shap
from sklearn.preprocessing import LabelEncoder

from data import load_transactions, load_user_monthly
from features.feature_engineering import build_monthly_features, build_transaction_features
from features.target_generation import add_future_targets, risk_flag, wellness_score
from training.utils import (
    ARTIFACTS_DIR,
    classification_metrics,
    split_by_ym,
    split_transactions_by_date,
)

REPORTS = Path(__file__).resolve().parents[1] / "reports"
REPORTS.mkdir(parents=True, exist_ok=True)

N_SAMPLE = 400  # cap SHAP computation size for speed


def _columns(name: str) -> list[str]:
    return json.loads((ARTIFACTS_DIR / name / "feature_columns.json").read_text())


def _monthly(name: str, target_col: str | None) -> tuple[pd.DataFrame, list[str]]:
    monthly = load_user_monthly()
    feats = build_monthly_features(monthly)
    cols = _columns(name)
    if target_col:
        feats = add_future_targets(feats)
    else:
        feats["wellness_score"] = wellness_score(feats)
    keep = cols + ([target_col] if target_col else [])
    df = feats.dropna(subset=keep)
    return df, cols


def _test_frame(name: str) -> tuple[pd.DataFrame, list[str]]:
    label_df, cols = {
        "spending": lambda: _monthly(name, "future_expense"),
        "savings": lambda: _monthly(name, "future_savings"),
        "wellness": lambda: _monthly(name, None),
        "risk": lambda: _prep_risk(),
    }[name]()
    return label_df, cols


def _prep_risk() -> tuple[pd.DataFrame, list[str]]:
    monthly = load_user_monthly()
    feats = build_monthly_features(monthly)
    feats["risk"] = risk_flag(feats)
    feats = feats[feats.groupby("user_id", sort=False).cumcount() >= 5]
    cols = _columns("risk")
    return feats.dropna(subset=cols), cols


def _sample_test(df: pd.DataFrame, cols: list[str]) -> np.ndarray:
    _, _, te = split_by_ym(df)
    if len(te) > N_SAMPLE:
        rng = np.random.default_rng(42)
        te = te.sample(N_SAMPLE, random_state=42)
    return te[cols].to_numpy()


def _shap_values(model, X: np.ndarray):
    if hasattr(model, "get_booster") or model.__class__.__name__ in (
        "RandomForestClassifier", "GradientBoostingClassifier", "XGBClassifier",
        "RandomForestRegressor", "GradientBoostingRegressor", "XGBRegressor",
        "ExtraTreesClassifier", "ExtraTreesRegressor",
    ):
        exp = shap.TreeExplainer(model)
        return exp.shap_values(X, check_additivity=False)
    exp = shap.LinearExplainer(model, masker=X, feature_perturbation="interventional")
    return exp.shap_values(X, check_additivity=False)


def _mean_abs(values) -> np.ndarray:
    if isinstance(values, list):  # multi-class -> average absolute across classes
        return np.mean([np.abs(v) for v in values], axis=0).mean(axis=0)
    arr = np.asarray(values)
    if arr.ndim == 3:  # (n, f, classes) -> mean over classes and samples
        return np.abs(arr).mean(axis=(0, 2))
    return np.abs(arr).mean(axis=0)


def run_monthly(name: str, target_col: str | None, algorithm_hint: str | None = None) -> None:
    df, cols = _test_frame(name)
    X = _sample_test(df, cols)
    model = joblib.load(ARTIFACTS_DIR / name / "model.joblib")
    sc_path = ARTIFACTS_DIR / name / "scaler.pkl"
    scaler = joblib.load(sc_path) if sc_path.exists() else None
    X_eff = scaler.transform(X) if scaler is not None else X

    values = _shap_values(model, X_eff)
    importance = _mean_abs(values)
    order = np.argsort(importance)[::-1]
    ranks = [cols[i] for i in order]

    pd.DataFrame({"feature": ranks, "mean_abs_shap": importance[order]}).to_csv(
        REPORTS / f"shap_{name}_ranks.csv", index=False)

    mean_ser = pd.Series(importance, index=cols).sort_values(ascending=True)
    fig, ax = plt.subplots(figsize=(7, max(3, 0.32 * len(cols))))
    ax.barh(mean_ser.index, mean_ser.values)
    ax.set_xlabel("mean |SHAP|")
    ax.set_title(f"{name} ({algorithm_hint or 'best'})")
    fig.tight_layout()
    fig.savefig(REPORTS / f"shap_{name}.png", dpi=120)
    plt.close(fig)
    print(f"[{name}] top-5: {ranks[:5]}")


def run_payment() -> None:
    txn = load_transactions()
    f = build_transaction_features(txn)
    cat_dummies = pd.get_dummies(f["category"], prefix="txn_cat", dtype=int)
    f = f.join(cat_dummies)
    base_cols = [
        "amount", "month", "day_of_month", "is_weekend",
        "month_cash_flow_so_far", "month_income_so_far",
        "hist_UPI", "hist_Debit_Card", "hist_Cash", "hist_Bank_Transfer", "hist_total",
    ]
    cum_cat = sorted([c for c in f.columns if c.startswith("cat_cum_")])
    cols = base_cols + sorted(cat_dummies.columns) + cum_cat
    f["date"] = pd.to_datetime(f["date"])
    tr, va, te = split_transactions_by_date(f)
    if len(te) > N_SAMPLE:
        te = te.sample(N_SAMPLE, random_state=42)
    model = joblib.load(ARTIFACTS_DIR / "payment" / "model.joblib")
    scaler = joblib.load(ARTIFACTS_DIR / "payment" / "scaler.pkl")
    helper = json.loads((ARTIFACTS_DIR / "payment" / "label_mapping.json").read_text())
    le = LabelEncoder()
    le.classes_ = np.array([k for k in helper])  # keys are index strings
    X = scaler.transform(te[cols].to_numpy())

    values = _shap_values(model, X)
    importance = _mean_abs(values)
    order = np.argsort(importance)[::-1]
    pd.DataFrame({"feature": [cols[i] for i in order], "mean_abs_shap": importance[order]}).to_csv(
        REPORTS / "shap_payment_ranks.csv", index=False)
    mean_ser = pd.Series(importance, index=cols).sort_values(ascending=True)
    fig, ax = plt.subplots(figsize=(7, max(3, 0.32 * len(cols))))
    ax.barh(mean_ser.index, mean_ser.values)
    ax.set_xlabel("mean |SHAP| (pooled over classes)")
    ax.set_title("payment (XGB best)")
    fig.tight_layout()
    fig.savefig(REPORTS / "shap_payment.png", dpi=120)
    plt.close(fig)
    print(f"[payment] top-5: {[cols[i] for i in order[:5]]}")


def main() -> None:
    run_monthly("spending", "future_expense")
    run_monthly("savings", "future_savings")
    run_monthly("wellness", None)
    run_monthly("risk", None)
    run_payment()
    print(f"SHAP reports written to {REPORTS}")


if __name__ == "__main__":
    main()