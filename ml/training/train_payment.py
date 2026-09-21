"""Model 5 - Best Payment Method Recommendation (Multiclass Classification).

Candidates compared on the time-aware validation split:
  1. XGBClassifier
  2. RandomForestClassifier
  3. LogisticRegression   (baseline GLM)
Best by validation weighted-F1 is retrained and scored on the unseen test
period (2024).

Target = payment mode used on the transaction (documented observed-behaviour
label, features/target_generation.payment_method_target). Soluble classes:
UPI, Debit Card, Cash, Bank Transfer (source data cannot separate credit/debit
cards and has no wallet entries -- see data/prepare_data.py).
"""

from __future__ import annotations

import numpy as np
import pandas as pd
from sklearn.ensemble import RandomForestClassifier
from sklearn.linear_model import LogisticRegression
from sklearn.preprocessing import StandardScaler
from xgboost import XGBClassifier

from data import load_transactions
from features.feature_engineering import build_transaction_features
from training.utils import (
    ARTIFACTS_DIR,
    classification_metrics,
    save_predict_api_meta,
    search_params,
    split_transactions_by_date,
)

RUN_NAME = "payment"
LABELS = ["UPI", "Debit Card", "Cash", "Bank Transfer"]


def _build() -> pd.DataFrame:
    txn = load_transactions()
    f = build_transaction_features(txn)

    # one-hot of the CURRENT transaction category (aligned across splits)
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
    feat_cols = base_cols + sorted(cat_dummies.columns) + cum_cat
    f["date"] = pd.to_datetime(f["date"])
    return f[feat_cols + ["date", "payment_mode"]]


def _roc_auc(y_true, y_pred_prob):
    from sklearn.metrics import roc_auc_score
    if len(set(y_true)) == 2:
        return roc_auc_score(y_true, y_pred_prob)
    return roc_auc_score(y_true, y_pred_prob, multi_class="ovr", average="weighted")


def main() -> None:
    f = _build()
    feats = [c for c in f.columns if c not in ("date", "payment_mode")]

    train, val, test = split_transactions_by_date(f)

    def _xy(sub):
        return sub[feats], sub["payment_mode"].astype(str)

    Xtr, ytr = _xy(train)
    Xva, yva = _xy(val)
    Xte, yte = _xy(test)

    # encode label strings -> ints (fit on TRAIN only)
    from sklearn.preprocessing import LabelEncoder
    le = LabelEncoder().fit(ytr)
    ytr_e, yva_e, yte_e = le.transform(ytr), le.transform(yva), le.transform(yte)
    label_mapping = {str(i): cls for i, cls in enumerate(le.classes_)}

    print(f"rows train/val/test: {len(train)}/{len(val)}/{len(test)}  features: {len(feats)}")
    print("label distribution (test):", pd.Series(yte).value_counts(normalize=True).round(3).to_dict())

    # scale numeric features (fits on TRAIN only)
    scaler = StandardScaler().fit(Xtr)
    Xtr_s, Xva_s, Xte_s = scaler.transform(Xtr), scaler.transform(Xva), scaler.transform(Xte)

    results = {}
    for name, est in CANDIDATES.items():
        model, params, f1 = search_params(
            est, GRID[name], Xtr_s, ytr_e, Xva_s, yva_e,
            metric_fn=lambda yt, yp: classification_metrics(yt, yp)["F1_weighted"], maximize=True,
        )
        results[name] = {"val_F1": f1, "params": params}
        print(f"  {name:>28s}  val F1 = {f1:6.4f}  params={params}")

    best_name = max(results, key=lambda k: results[k]["val_F1"])
    print(f"BEST candidate: {best_name}")

    params = results[best_name]["params"]
    model = CANDIDATES[best_name](**params)
    model.fit(np.vstack([Xtr_s, Xva_s]), np.concatenate([ytr_e, yva_e]))

    pred_e = model.predict(Xte_s)
    proba = model.predict_proba(Xte_s) if hasattr(model, "predict_proba") else None
    # map probabilities to label strings for the JSON response
    proba_map = {le.classes_[i]: p for i, p in enumerate(proba.T.tolist())} if proba is not None else None

    test_metrics = classification_metrics(yte_e, pred_e, None)
    del test_metrics["Confusion_Matrix"]
    from sklearn.metrics import classification_report
    report = classification_report(yte_e, pred_e, output_dict=True, zero_division=0, target_names=le.classes_)
    per_class = {k: {kk: round(vv, 4) for kk, vv in v.items() if isinstance(v, dict) and kk not in ("support",)}
                 for k, v in report.items() if k in le.classes_}

    print("TEST metrics:", test_metrics)
    print("TEST per-class:", per_class)
    print("TEST sample probs:", {k: [round(x, 3) for x in v[:3]] for k, v in proba_map.items()})

    comparison = {k: {"val_F1": v["val_F1"], "final_params": v["params"]} for k, v in results.items()}
    save_predict_api_meta(
        name=RUN_NAME,
        model=model,
        features=feats,
        art_dir=ARTIFACTS_DIR / RUN_NAME,
        metrics={"val": {"F1_weighted": results[best_name]["val_F1"]}, "test": test_metrics,
                 "test_per_class": per_class, "algorithm_comparison": comparison},
        algorithm=best_name,
        version="1.0",
        target="payment_mode",
        target_desc="RULE-DERIVED (observed-behaviour) label: payment mode actually used on a transaction.",
        scaler=scaler,
        label_mapping=label_mapping,
        extra={
            "chosen_algorithm_note": f"Best of {list(results)} by validation F1.",
            "label_order_in_model": le.classes_.tolist(),
        },
    )


CANDIDATES = {
    "XGBClassifier": XGBClassifier,
    "RandomForestClassifier": RandomForestClassifier,
    "LogisticRegression": LogisticRegression,
}

GRID = {
    "XGBClassifier": {"n_estimators": [100, 200], "learning_rate": [0.05, 0.1], "max_depth": [3, 4], "subsample": [0.8, 1.0]},
    "RandomForestClassifier": {"n_estimators": [100, 250], "max_depth": [None, 10], "min_samples_leaf": [1, 4]},
    "LogisticRegression": {"C": [0.1, 1.0, 10.0], "max_iter": [2000], "solver": ["lbfgs"]},
}


if __name__ == "__main__":
    main()