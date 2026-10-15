# WealthSync - Machine Learning Models

Core ML models for the WealthSync financial-wealth application. Five models are
built.


## Dataset & cleaning

Source: `Dataset/budgetwise_finance_dataset.csv` (the only longitudinal dataset
available; 150 users x 48 months, 2021-01..2024-12).

- Not usable: `synthetic_personal_finance_dataset.csv` (single cross-section per
  user, not time series), `personal_finance_tracker_dataset.csv` (3k rows, no
  payment method), `master_credit_risk_pool.csv` (corrupted labels),
  `default of credit card clients.csv` (duplicated header row),
  `City_time_series.csv` (housing macro data).
- `data/prepare_data.py` maps messy date/category/payment-mode aliases, drops
  invalid rows and winsorizes `amount` at 500,000 (the synthetic anomalies of
  999,999,999 and 1,000,000 are clipped).
- Payment modes are canonical: UPI / Debit Card / Cash / Bank Transfer.
  The source stores a bare `card`, so credit vs debit cannot be distinguished;
  that variant is mapped to Debit Card.
- Outputs: `data/processed/transactions_clean.csv` (~12.6k txns) and
  `data/processed/user_monthly.csv` (~6k user-months).

## Feature & target construction

- `features/feature_engineering.py`:
  - Monthly features (models 1-4): income, expense, cash flow, ratios, rent
    burden, category spend, lags (income/expense/cash-flow/savings 1-2m),
    3-month rolling means, income/expense trends, spending/income stability,
    txn count, avg txn amount, month, year.
  - Transaction features (model 5): amount, calendar flags, month-to-date cash
    flow / income so far, historical payment-method counts, and cumulative
    category spend before the transaction (`cat_cum_*`).
- `features/target_generation.py`:
  - `future_expense`, `future_savings` = actual next-month values (true
    forecasting targets; model never sees the same month's income/expense).
  - `wellness_score` (0-100) and `risk_flag` (0/1) are **rule-derived labels**
    with documented rules. They are NOT real-world ground truth.
  - `payment_mode` = observed label (documented behavioural prediction).

## Model design

Time-aware split (no leakage): TRAIN 2021-01..2023-06, VAL 2023-07..2023-12,
TEST 2024-01..2024-12. Scalers are fitted on TRAIN only. Regression targets
train in signed-log1p space and are inverse-transformed for reporting.

Each model compares 2-3 algorithms on the validation window and the best is
refitted on train+val and scored on the unseen test window.

| # | Model | Target | Candidates compared (in 2-3 per requirement) | Best on validation |
|---|-------|--------|-----------------------------------------------|--------------------|
| 1 | Spending forecast | future expense | RF, GBM, XGB | XGB |
| 2 | Savings forecast | future savings | GBM, RF, XGB | XGB |
| 3 | Financial wellness | wellness 0-100 | XGB, RF, GBM | GBM |
| 4 | Risk detection | risk 0/1 | LogisticRegression, RF, XGB | RF |
| 5 | Payment-method | payment mode | XGB, RF, LogisticRegression | XGB |

## Results (test window)

| Model | Metric | Value |
|-------|--------|-------|
| Spending | MAE / RMSE / R2 | 21 493 / 81 833 / -0.06 |
| Savings | MAE / RMSE / R2 | 39 613 / 99 307 / ~0.00 |
| Wellness | MAE / RMSE / R2 | 0.10 / 0.39 / 0.9997 |
| Risk | ROC-AUC / F1-weighted / Acc | 0.971 / 0.950 / 0.963 |
| Payment | F1-weighted / Accuracy | 0.232 / 0.237 (chance ~0.25) |

Caveats, documented in each artifact's `model_metadata.json`:

- Spending/savings R2 ~ 0: verified no leakage; lags carry limited signal in
  this synthetic data, and the test window has heavy-winsorized outliers.
- Wellness R2 0.9997: expected circularity - the label is a documented rule
  over these same features; the model reproduces the rule. Replace rule labels
  with expert/manual labels in production.
- Risk test set is 96.1% high-risk (imbalance); ROC-AUC/F1 used as the primary
  metric. `Confusion_Matrix` in metrics.
- Payment ~ chance: payment methods are near-uniform random per user in this
  synthetic dataset (modal share 0.31), so no signal exists to learn.

## Artifacts

Each `artifacts/<model>/` contains `model.joblib`, `feature_columns.json`,
`training_metrics.json`, `model_metadata.json`, plus `scaler.pkl` and
`label_mapping.json` where applicable (risk, payment). The per-algorithm
validation comparison lives in `training_metrics.json` under
`algorithm_comparison`.

## Reports & explainability

- `evaluation/evaluate_models.py` -> `reports/model_performance_summary.json`
- `explainability/shap_explainer.py` -> `reports/shap_<model>.csv` + `.png`
