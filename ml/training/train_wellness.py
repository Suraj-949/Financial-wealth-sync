"""Model 3 - Financial Wellness Prediction (Regression, score 0-100).

Candidates compared on the time-aware validation window:
  1. XGBRegressor   (required algorithm)
  2. RandomForestRegressor
  3. GradientBoostingRegressor

Target = Financial_Wellness_Score (0-100). This is a RULE-DERIVED LABEL:
see features/target_generation.wellness_score for the documented scoring
rules. It is NOT real-world ground truth (Requirements section 7).
"""

from __future__ import annotations

import pandas as pd
from sklearn.ensemble import GradientBoostingRegressor, RandomForestRegressor
from xgboost import XGBRegressor

from data import load_user_monthly
from features.feature_engineering import build_monthly_features
from features.target_generation import wellness_score
from training.utils import (
    ARTIFACTS_DIR,
    regression_metrics,
    save_predict_api_meta,
    search_params,
    split_by_ym,
)

RUN_NAME = "wellness"

FEATURES = [
    "income", "expense", "cash_flow",
    "expense_ratio", "savings_ratio", "rent_burden",
    "spending_stability", "income_stability",
    "savings_3m_mean", "cash_flow_3m_mean",
    "income_3m_mean", "expense_3m_mean",
    "income_trend", "expense_trend",
    "txn_count", "avg_txn_amount", "month", "year",
]

CANDIDATES = {
    "XGBRegressor": XGBRegressor,
    "RandomForestRegressor": RandomForestRegressor,
    "GradientBoostingRegressor": GradientBoostingRegressor,
}

GRID = {
    "XGBRegressor": {
        "n_estimators": [100, 200], "learning_rate": [0.05, 0.1], "max_depth": [3, 4],
        "subsample": [0.8, 1.0],
    },
    "RandomForestRegressor": {
        "n_estimators": [100, 250], "max_depth": [None, 10], "min_samples_leaf": [1, 4],
    },
    "GradientBoostingRegressor": {
        "n_estimators": [100, 200], "learning_rate": [0.05, 0.1], "max_depth": [3, 4],
    },
}


def build_training_frame() -> pd.DataFrame:
    annual = load_user_monthly()
    feats = build_monthly_features(annual)
    feats["wellness_score"] = wellness_score(feats)
    return feats.dropna(subset=FEATURES)


def main() -> None:
    df = build_training_frame()
    train, val, test = split_by_ym(df)

    Xtr, ytr = train[FEATURES], train["wellness_score"].astype(int)
    Xva, yva = val[FEATURES], val["wellness_score"].astype(int)
    Xte, yte = test[FEATURES], test["wellness_score"].astype(int)

    print(f"rows train/val/test: {len(train)}/{len(val)}/{len(test)}  features: {len(FEATURES)}")

    results = {}
    for name, est in CANDIDATES.items():
        model, params, mae = search_params(
            est, GRID[name], Xtr, ytr, Xva, yva, metric_fn=lambda yt, yp: regression_metrics(yt, yp)["MAE"], maximize=False
        )
        results[name] = {"val_MAE": mae, "params": params}
        print(f"  {name:>28s}  val MAE = {mae:8.2f}  params={params}")

    best_name = min(results, key=lambda k: results[k]["val_MAE"])
    print(f"BEST candidate: {best_name}")

    params = results[best_name]["params"]
    model = CANDIDATES[best_name](**params)
    model.fit(pd.concat([Xtr, Xva]), pd.concat([ytr, yva]))

    test_metrics = regression_metrics(yte, model.predict(Xte))
    val_metrics = regression_metrics(yva, model.predict(Xva))
    print("TEST metrics:", test_metrics)

    comparison = {k: {"val_MAE": v["val_MAE"], "final_params": v["params"]} for k, v in results.items()}
    save_predict_api_meta(
        name=RUN_NAME,
        model=model,
        features=FEATURES,
        art_dir=ARTIFACTS_DIR / RUN_NAME,
        metrics={"val": val_metrics, "test": test_metrics, "algorithm_comparison": comparison},
        algorithm=best_name,
        version="1.0",
        target="wellness_score",
        target_desc="RULE-DERIVED LABEL (0-100). Documented scoring rules in features/target_generation.wellness_score.",
        extra={
            "chosen_algorithm_note": f"Best of {list(results)} by validation MAE.",
            "circularity_note": (
                "The wellness score is a documented rule computed from these very features, so near-perfect fit is "
                "expected: the trained model reproduces the documented rule (R2 ~ 1.0, MAE ~ 0.1). In production, "
                "replace rule-derived labels with expert/manual labels to obtain a genuinely independent target."
            ),
        },
    )


if __name__ == "__main__":
    main()