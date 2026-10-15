"""Model 4 - Financial Risk Detection (Binary Classification 0=low / 1=high).

Candidates compared on the time-aware validation window:
  1. LogisticRegression  (required algorithm)
  2. RandomForestClassifier
  3. XGBClassifier
Best by validation ROC-AUC is retrained on train+val and scored on the
unseen test window.

Target = Risk flag. This is a RULE-DERIVED LABEL (documented rules in
features/target_generation.risk_flag), NOT real-world default ground truth.
"""

from __future__ import annotations

import numpy as np
import pandas as pd
from sklearn.ensemble import RandomForestClassifier
from sklearn.linear_model import LogisticRegression
from sklearn.preprocessing import StandardScaler
from xgboost import XGBClassifier

from data import load_user_monthly
from features.feature_engineering import build_monthly_features
from features.target_generation import risk_flag
from training.utils import (
    ARTIFACTS_DIR,
    classification_metrics,
    save_predict_api_meta,
    search_params,
    split_by_ym,
)

RUN_NAME = "risk"

FEATURES = [
    "income", "expense", "cash_flow", "expense_ratio",
    "savings", "savings_ratio",
    "cash_flow_1m", "cash_flow_3m_mean",
    "income_1m", "income_2m", "income_3m_mean",
    "expense_1m", "expense_2m", "expense_3m_mean",
    "expense_trend", "income_trend",
    "spending_stability", "income_stability",
    "txn_count", "avg_txn_amount", "month", "year",
]

CANDIDATES = {
    "LogisticRegression": LogisticRegression,
    "RandomForestClassifier": RandomForestClassifier,
    "XGBClassifier": XGBClassifier,
}

GRID = {
    "LogisticRegression": {"C": [0.1, 1.0, 10.0], "class_weight": [None, "balanced"], "max_iter": [5000]},
    "RandomForestClassifier": {"n_estimators": [100, 250], "max_depth": [None, 10], "min_samples_leaf": [1, 4]},
    "XGBClassifier": {"n_estimators": [100, 200], "learning_rate": [0.05, 0.1], "max_depth": [3, 4], "subsample": [0.8, 1.0]},
}


def build_training_frame() -> pd.DataFrame:
    monthly = load_user_monthly()
    feats = build_monthly_features(monthly)
    feats["risk"] = risk_flag(feats)
    # drop the first 5 months per user so trailing-6-month risk rules see real history
    retained = feats.groupby("user_id", sort=False).cumcount() >= 5
    feats = feats[retained]
    return feats.dropna(subset=FEATURES)


def _roc_auc(y_true, y_pred_prob):
    from sklearn.metrics import roc_auc_score
    return roc_auc_score(y_true, y_pred_prob)


def main() -> None:
    df = build_training_frame()
    train, val, test = split_by_ym(df)

    Xtr, ytr = train[FEATURES], train["risk"].astype(int)
    Xva, yva = val[FEATURES], val["risk"].astype(int)
    Xte, yte = test[FEATURES], test["risk"].astype(int)

    # scale features (fitted on TRAIN only) so LogisticRegression converges
    scaler = StandardScaler().fit(Xtr)
    Xtr_s, Xva_s, Xte_s = scaler.transform(Xtr), scaler.transform(Xva), scaler.transform(Xte)

    print(f"rows train/val/test: {len(train)}/{len(val)}/{len(test)}  features: {len(FEATURES)}")
    print("risk balance test:", yte.value_counts(normalize=True).round(3).to_dict())

    results = {}
    proba_predict = lambda m, X: m.predict_proba(X)[:, 1]
    for name, est in CANDIDATES.items():
        model, params, auc = search_params(
            est, GRID[name], Xtr_s, ytr, Xva_s, yva,
            metric_fn=lambda yt, yp: _roc_auc(yt, yp), maximize=True, predict_fn=proba_predict,
        )
        results[name] = {"val_ROC_AUC": auc, "params": params}
        print(f"  {name:>28s}  val ROC-AUC = {auc:6.4f}  params={params}")

    best_name = max(results, key=lambda k: results[k]["val_ROC_AUC"])
    print(f"BEST candidate: {best_name}")

    params = results[best_name]["params"]
    model = CANDIDATES[best_name](**params)
    model.fit(np.vstack([Xtr_s, Xva_s]), np.concatenate([ytr, yva]))

    pred = model.predict(Xte_s)
    proba = model.predict_proba(Xte_s)[:, 1] if hasattr(model, "predict_proba") else None
    test_metrics = classification_metrics(yte, pred, proba)
    val_pred = model.predict(Xva_s)
    val_proba = model.predict_proba(Xva_s)[:, 1] if proba is not None else None
    val_metrics = classification_metrics(yva, val_pred, val_proba)
    print("TEST metrics:", test_metrics)

    comparison = {k: {"val_ROC_AUC": v["val_ROC_AUC"], "final_params": v["params"]} for k, v in results.items()}
    save_predict_api_meta(
        name=RUN_NAME,
        model=model,
        features=FEATURES,
        art_dir=ARTIFACTS_DIR / RUN_NAME,
        metrics={"val": val_metrics, "test": test_metrics, "algorithm_comparison": comparison},
        algorithm=best_name,
        version="1.0",
        target="risk",
        target_desc="RULE-DERIVED LABEL 0=low 1=high. Documented rules in features/target_generation.risk_flag.",
        label_mapping={"0": "Low Risk", "1": "High Risk"},
        scaler=scaler,
        extra={
            "chosen_algorithm_note": f"Best of {list(results)} by validation ROC-AUC.",
            "imbalance_note": "Class-sensitive metrics (ROC-AUC/F1) prioritised over accuracy.",
        },
    )


if __name__ == "__main__":
    main()