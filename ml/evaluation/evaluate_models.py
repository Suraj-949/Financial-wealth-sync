"""WealthSync - model evaluation summary.

Loads every trained artifact, re-runs it on the time-aware test split, and
writes a consolidated report to ml/reports/model_performance_summary.json and
a human-readable print-out.
"""

from __future__ import annotations

import json
from pathlib import Path

import joblib
import numpy as np
import pandas as pd
from sklearn.preprocessing import LabelEncoder, StandardScaler

from data import load_transactions, load_user_monthly
from features.feature_engineering import build_monthly_features, build_transaction_features
from features.target_generation import add_future_targets, risk_flag, wellness_score
from training.utils import (
    ARTIFACTS_DIR,
    TRAIN_MONTHS,
    VAL_MONTHS,
    TEST_MONTHS,
    classification_metrics,
    regression_metrics,
    signed_expm1,
    signed_log1p,
    split_by_ym,
    split_transactions_by_date,
)

REPORTS = Path(__file__).resolve().parents[1] / "reports"
REPORTS.mkdir(parents=True, exist_ok=True)

SPENDING_FEATURES, SAVINGS_FEATURES, WELLNESS_FEATURES, RISK_FEATURES = None, None, None, None


def _load_columns(name: str) -> list[str]:
    return json.loads((ARTIFACTS_DIR / name / "feature_columns.json").read_text())


def _monthly_base() -> tuple[pd.DataFrame, dict]:
    monthly = load_user_monthly()
    feats = build_monthly_features(monthly)
    feats = add_future_targets(feats)
    return monthly, feats


def evaluate_spending() -> dict:
    _, feats = _monthly_base()
    cols = _load_columns("spending")
    df = feats.dropna(subset=cols + ["future_expense"])
    tr, va, te = split_by_ym(df)
    m = joblib.load(ARTIFACTS_DIR / "spending" / "model.joblib")
    pred = signed_expm1(m.predict(te[cols]))
    return {"test_metrics": regression_metrics(te["future_expense"], pred),
            "n_test_rows": int(len(te)), "test_window": list(TEST_MONTHS)}


def evaluate_savings() -> dict:
    _, feats = _monthly_base()
    cols = _load_columns("savings")
    df = feats.dropna(subset=cols + ["future_savings"])
    tr, va, te = split_by_ym(df)
    m = joblib.load(ARTIFACTS_DIR / "savings" / "model.joblib")
    pred = signed_expm1(m.predict(te[cols]))
    return {"test_metrics": regression_metrics(te["future_savings"], pred),
            "n_test_rows": int(len(te)), "test_window": list(TEST_MONTHS)}


def evaluate_wellness() -> dict:
    _, feats = _monthly_base()
    feats["wellness_score"] = wellness_score(feats)
    cols = _load_columns("wellness")
    df = feats.dropna(subset=cols)
    tr, va, te = split_by_ym(df)
    m = joblib.load(ARTIFACTS_DIR / "wellness" / "model.joblib")
    pred = m.predict(te[cols]).round(0).astype(int)
    pred_cont = m.predict(te[cols])
    return {"test_metrics": regression_metrics(te["wellness_score"], pred_cont),
            "n_test_rows": int(len(te)), "test_window": list(TEST_MONTHS)}


def evaluate_risk() -> dict:
    _, feats = _monthly_base()
    feats["risk"] = risk_flag(feats)
    retained = feats.groupby("user_id", sort=False).cumcount() >= 5
    feats = feats[retained]
    cols = _load_columns("risk")
    df = feats.dropna(subset=cols)
    tr, va, te = split_by_ym(df)
    m = joblib.load(ARTIFACTS_DIR / "risk" / "model.joblib")
    scaler = joblib.load(ARTIFACTS_DIR / "risk" / "scaler.pkl")
    Xte = scaler.transform(te[cols])
    pred = m.predict(Xte)
    proba = m.predict_proba(Xte)[:, 1]
    return {"test_metrics": classification_metrics(te["risk"], pred, proba),
            "n_test_rows": int(len(te)),
            "test_window": list(TEST_MONTHS),
            "test_label_distribution": te["risk"].value_counts(normalize=True).round(4).to_dict()}


def evaluate_payment() -> dict:
    txn = load_transactions()
    f = build_transaction_features(txn)
    cat_dummies = pd.get_dummies(f["category"], prefix="txn_cat", dtype=int)
    for c in sorted(cat_dummies.columns):
        f[c] = 0
    for c in cat_dummies.columns:
        f.loc[cat_dummies.index, c] = cat_dummies.loc[cat_dummies.index, c]
    base_cols = [
        "amount", "month", "day_of_month", "is_weekend",
        "month_cash_flow_so_far", "month_income_so_far",
        "hist_UPI", "hist_Debit_Card", "hist_Cash", "hist_Bank_Transfer", "hist_total",
    ]
    cum_cat = sorted([c for c in f.columns if c.startswith("cat_cum_")])
    cols = base_cols + sorted(cat_dummies.columns) + cum_cat
    f["date"] = pd.to_datetime(f["date"])

    tr, va, te = split_transactions_by_date(f)
    m = joblib.load(ARTIFACTS_DIR / "payment" / "model.joblib")
    scaler = joblib.load(ARTIFACTS_DIR / "payment" / "scaler.pkl")
    le = LabelEncoder().fit(tr["payment_mode"])
    Xte = scaler.transform(te[cols])
    pred_e = m.predict(Xte)
    pred = le.inverse_transform(pred_e)
    return {"test_metrics": classification_metrics(le.transform(te["payment_mode"]), pred_e, None),
            "n_test_rows": int(len(te)),
            "test_label_distribution": te["payment_mode"].value_counts(normalize=True).round(4).to_dict(),
            "n_chance_accuracy": round(1 / tr["payment_mode"].nunique(), 3),
            }


def main() -> None:
    evaluators = {
        "spending": evaluate_spending,
        "savings": evaluate_savings,
        "wellness": evaluate_wellness,
        "risk": evaluate_risk,
        "payment": evaluate_payment,
    }
    summary = {}
    for name, fn in evaluators.items():
        try:
            res = fn()
            summary[name] = res
            print(f"[{name}] {res['test_metrics']}")
        except Exception as e:
            summary[name] = {"error": str(e)}
            print(f"[{name}] ERROR: {e}")

    out = REPORTS / "model_performance_summary.json"
    out.write_text(json.dumps(summary, indent=2, default=str), encoding="utf-8")
    print(f"summary -> {out}")


if __name__ == "__main__":
    main()