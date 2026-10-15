"""Model 2 - Savings Prediction (Regression).

Candidates compared on the time-aware validation window:
  1. GradientBoostingRegressor  (required algorithm)
  2. RandomForestRegressor
  3. XGBRegressor
Best by validation MAE is retrained on train+val and scored on unseen test.

Target = Future_Savings = next month's documented savings (income - expense).
This is a genuine forecasting target: the model never sees next month's
income/expense, only lagged features (so it is NOT the deterministic
reproduction Savings = Income - Expenses).
"""

from __future__ import annotations

import numpy as np
import pandas as pd
from sklearn.ensemble import GradientBoostingRegressor, RandomForestRegressor
from xgboost import XGBRegressor

from data import load_user_monthly
from features.feature_engineering import build_monthly_features
from features.target_generation import add_future_targets
from training.utils import (
    ARTIFACTS_DIR,
    regression_metrics,
    save_predict_api_meta,
    search_params,
    signed_expm1,
    signed_log1p,
    split_by_ym,
)

RUN_NAME = "savings"

FEATURES = [
    "income", "expense", "cash_flow", "expense_ratio", "savings_ratio",
    "savings_1m", "savings_3m_mean",
    "income_1m", "income_2m", "income_3m_mean",
    "expense_1m", "expense_2m", "expense_3m_mean",
    "cash_flow_1m", "cash_flow_3m_mean",
    "income_trend", "expense_trend",
    "spending_stability", "income_stability",
    "txn_count", "avg_txn_amount", "month", "year",
]

CANDIDATES = {
    "GradientBoostingRegressor": GradientBoostingRegressor,
    "RandomForestRegressor": RandomForestRegressor,
    "XGBRegressor": XGBRegressor,
}

GRID = {
    "GradientBoostingRegressor": {
        "n_estimators": [100, 200], "learning_rate": [0.05, 0.1], "max_depth": [3, 4],
    },
    "RandomForestRegressor": {
        "n_estimators": [100, 250], "max_depth": [None, 10], "min_samples_leaf": [1, 4],
    },
    "XGBRegressor": {
        "n_estimators": [100, 200], "learning_rate": [0.05, 0.1], "max_depth": [3, 4],
        "subsample": [0.8, 1.0],
    },
}


def build_training_frame() -> pd.DataFrame:
    monthly = load_user_monthly()
    feats = build_monthly_features(monthly)
    feats = add_future_targets(feats)
    return feats.dropna(subset=FEATURES + ["future_savings"])


def main() -> None:
    df = build_training_frame()
    train, val, test = split_by_ym(df)

    Xtr, ytr = train[FEATURES], signed_log1p(train["future_savings"])
    Xva, yva = val[FEATURES], signed_log1p(val["future_savings"])
    Xte, yte_orig = test[FEATURES], test["future_savings"].astype(float)

    print(f"rows train/val/test: {len(train)}/{len(val)}/{len(test)}  features: {len(FEATURES)}")

    results = {}
    for name, est in CANDIDATES.items():
        model, params, mae = search_params(
            est, GRID[name], Xtr, ytr, Xva, yva, metric_fn=lambda yt, yp: regression_metrics(yt, yp)["MAE"], maximize=False
        )
        results[name] = {"val_MAE_log": mae, "params": params}
        print(f"  {name:>28s}  val MAE (log space) = {mae:5.3f}  params={params}")

    best_name = min(results, key=lambda k: results[k]["val_MAE_log"])
    print(f"BEST candidate: {best_name}")

    params = results[best_name]["params"]
    model = CANDIDATES[best_name](**params)
    model.fit(pd.concat([Xtr, Xva], axis=0), np.concatenate([ytr, yva]))

    test_metrics = regression_metrics(yte_orig, signed_expm1(model.predict(Xte)))
    val_metrics = regression_metrics(signed_expm1(yva), signed_expm1(model.predict(Xva)))
    print("TEST metrics (original currency units):", test_metrics)

    comparison = {k: {"val_MAE_log": v["val_MAE_log"], "final_params": v["params"]} for k, v in results.items()}
    save_predict_api_meta(
        name=RUN_NAME,
        model=model,
        features=FEATURES,
        art_dir=ARTIFACTS_DIR / RUN_NAME,
        metrics={"val": val_metrics, "test": test_metrics, "algorithm_comparison": comparison},
        algorithm=best_name,
        version="1.0",
        target="future_savings",
        target_desc=(
            "Next month's documented savings = income - expense (no savings field in source). "
            "Forecast target from actual future data; NOT the deterministic income-expense of the same month."
        ),
        extra={
            "chosen_algorithm_note": f"Best of {list(results)} by validation MAE (log space).",
            "target_transform": "signed_log1p (inverse-transformed to currency units for reporting)",
        },
    )


if __name__ == "__main__":
    main()