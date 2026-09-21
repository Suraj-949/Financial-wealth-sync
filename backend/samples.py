"""WealthSync backend - realistic sample feature payloads.

Rebuilds the exact test-time feature frames used during training and caches a
small random sample from the test window per model, so the dashboard / mobile
app can fetch a "try me" input with the correct feature set.

Sample payloads include the model's feature dict plus the actual target value
(known ground truth) for display.
"""

from __future__ import annotations

import sys
from pathlib import Path

ML_DIR = Path(__file__).resolve().parents[1] / "ml"
if str(ML_DIR) not in sys.path:
    sys.path.insert(0, str(ML_DIR))

import numpy as np
import pandas as pd

from data import load_transactions, load_user_monthly
from features.feature_engineering import build_monthly_features, build_transaction_features
from features.target_generation import add_future_targets, risk_flag, wellness_score
from training.utils import split_by_ym, split_transactions_by_date

N_SAMPLES = 5
RNG = np.random.default_rng(7)

_registry: dict = {}


def _build():
    if _registry:
        return _registry

    monthly = load_user_monthly()
    feats = build_monthly_features(monthly)

    # spending --------------------------------
    f = add_future_targets(feats.copy())
    cols = _cols("spending")
    df = f.dropna(subset=cols + ["future_expense"])
    _, _, te = split_by_ym(df)
    _registry["spending"] = _rows(te, cols, "future_expense", "future_expense")

    # savings ---------------------------------
    cols = _cols("savings")
    df = f.dropna(subset=cols + ["future_savings"])
    _, _, te = split_by_ym(df)
    _registry["savings"] = _rows(te, cols, "future_savings", "future_savings")

    # wellness --------------------------------
    fw = feats.copy()
    fw["wellness_score"] = wellness_score(feats)
    cols = _cols("wellness")
    _, _, te = split_by_ym(fw.dropna(subset=cols))
    _registry["wellness"] = _rows(te, cols, "wellness_score", "wellness_score")

    # risk ------------------------------------
    fr = feats.copy()
    fr["risk"] = risk_flag(feats)
    fr = fr[fr.groupby("user_id", sort=False).cumcount() >= 5]
    cols = _cols("risk")
    _, _, te = split_by_ym(fr.dropna(subset=cols))
    _registry["risk"] = _rows(te, cols, "risk", "risk", lambda v: "High Risk" if v == 1 else "Low Risk")

    # payment ---------------------------------
    txn = load_transactions()
    tf = build_transaction_features(txn)
    cat_dummies = pd.get_dummies(tf["category"], prefix="txn_cat", dtype=int)
    tf = tf.join(cat_dummies)
    base = [
        "amount", "month", "day_of_month", "is_weekend",
        "month_cash_flow_so_far", "month_income_so_far",
        "hist_UPI", "hist_Debit_Card", "hist_Cash", "hist_Bank_Transfer", "hist_total",
    ]
    cum_cat = sorted([c for c in tf.columns if c.startswith("cat_cum_")])
    cols = base + sorted(cat_dummies.columns) + cum_cat
    tf["date"] = pd.to_datetime(tf["date"])
    _, _, te = split_transactions_by_date(tf)
    _registry["payment"] = _rows(te, cols, "payment_mode", "payment_mode")

    return _registry


def _cols(model: str) -> list[str]:
    import json
    p = ML_DIR / "artifacts" / model / "feature_columns.json"
    return json.loads(p.read_text("utf-8"))


def _rows(frame: pd.DataFrame, cols: list[str], target_col: str, label_col: str,
          label_fn=None) -> list[dict]:
    sample = frame.sample(min(N_SAMPLES, len(frame)), random_state=int(RNG.integers(0, 999)))
    out = []
    for _, r in sample.iterrows():
        out.append({
            "features": {c: _num(r[c]) for c in cols},
            "actual_label": (label_fn(r[label_col]) if label_fn else _num(r[label_col])),
            "date": str(r.get("date", r.get("ym_dt", ""))),
            "user_id": str(r.get("user_id", "")),
        })
    return out


def _num(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return 0.0


def sample_payloads(model: str) -> list[dict]:
    registry = _build()
    if model not in registry:
        raise ValueError(f"unknown model '{model}'")
    return registry[model]