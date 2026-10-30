# WealthSync — Machine Learning Intelligence Layer (`ml/`)

This directory contains the machine learning pipelines, datasets, feature engineering scripts, model artifacts, and evaluation reports for the WealthSync platform.

WealthSync utilizes a two-tier machine learning architecture:
1. **Production Candidate Models (`ml/models/`)**: High-accuracy supervised models trained on empirical US Bureau of Labor Statistics (BLS) and UCI Credit Default datasets.
2. **Longitudinal Monthly INR Models (`ml/artifacts/`)**: 5 monthly forecasting models trained on a 48-month panel dataset for personal finance tracking in INR.
3. **Deep Learning Exploration**: Multi-task neural network architectures (`train_all_with_dl.py`, `test_dl_models.py`).

---

## Model Inventory & Benchmarks

### Tier 1: Production Candidate Models (`ml/models/`)

These models power the primary predictive endpoints in the FastAPI backend:

| Model | Task / Target | Algorithm | Dataset | Primary Metrics | Status | Serving Endpoint |
|---|---|---|---|---|---|---|
| **Spending Regressor** | Next-quarter total expenditure (`total_spend_t_plus_1`) | `RandomForestRegressor` (300 trees, leaf size 5) | BLS CE Interview PUMD 2004 (20,378 transitions) | $R^2 = 0.5367$<br>MAE = \$2,452.25<br>RMSE = \$5,230.91 | Production Candidate | `POST /api/ml/spending/predict` |
| **Credit Risk Regressor** | 30-day credit card default probability (`default payment next month`) | `GradientBoostingRegressor` (300 trees, lr=0.05, depth=3) | UCI Default of Credit Card Clients (30,000 clients) | ROC-AUC = 0.7877<br>Brier = 0.1318<br>MAE = 0.26 | Production Candidate | `POST /api/ml/risk/predict` |

#### Spending Model Features (`ml/models/spending/random forest/feature_columns.json`)
Consumes 22 raw consumer-unit features:
- Demographics: `age_ref`, `age2`, `fam_size`, `educ_ref`, `fam_type`, `cutenure`, `bls_urbn`
- Historical quarterly spending: `totexppq`, `foodpq`, `houspq`, `transpq`, `utilpq`, `sheltpq`
- Lags & statistics: `total_spend_lag1`, `total_spend_pastmean`, `total_spend_paststd`, `food_lag1`, `housing_lag1`, `income_lag1`
- Income: `itbi_q_income`, `cuincome_class`, `seq`

#### Credit Risk Model Features (`ml/models/risk/gradient boosting/feature_columns.json`)
Consumes 26 raw client credit features:
- Credit limit: `LIMIT_BAL`
- Demographics: `AGE`, `SEX`, `EDUCATION`, `MARRIAGE`
- Past 6-month repayment status: `PAY_0`, `PAY_2`, `PAY_3`, `PAY_4`, `PAY_5`, `PAY_6`
- Past 6-month bill statements: `BILL_AMT1` through `BILL_AMT6`
- Past 6-month payment amounts: `PAY_AMT1` through `PAY_AMT6`
- Derived indicators: `util_mean6`, `repay_ratio_mean6` (can be null), `max_delinq_6m`

#### Calibrated Risk Score & Bands:
The model outputs a continuous probability $P(\text{default}) \in [0, 1]$. The API converts this to:
$$\text{RiskScore} = P(\text{default}) \times 100$$
- **Low (0–30)**: Observed test default rate of 12.6%
- **Medium (31–60)**: Observed test default rate of 40.3%
- **High (61–100)**: Observed test default rate of 73.6%

---

### Tier 2: Longitudinal INR Models (`ml/artifacts/`)

Source: `Dataset/budgetwise_finance_dataset.csv` (150 users $\times$ 48 months, chronological split: Train 2021-01..2023-06, Val 2023-07..2023-12, Test 2024-01..2024-12).

| # | Model | Target | Algorithm | Unit / Range | Test Metrics |
|---|---|---|---|---|---|
| 1 | **Spending Forecast** | Next-month expenses (`future_expense`) | XGBoost Regressor | INR (signed-log1p) | MAE: ₹21,493, RMSE: ₹81,833, $R^2 \approx -0.06$ |
| 2 | **Savings Forecast** | Next-month savings (`future_savings`) | XGBoost Regressor | INR (signed-log1p) | MAE: ₹39,613, RMSE: ₹99,307, $R^2 \approx 0.00$ |
| 3 | **Financial Wellness** | Financial wellness score (`wellness_score`) | Gradient Boosting Regressor | 0–100 score | MAE: 0.10, RMSE: 0.39, $R^2 = 0.9997$ |
| 4 | **Risk Detection** | High financial risk flag (`risk_flag`) | Random Forest Classifier | Binary (0: Low, 1: High) | ROC-AUC: 0.971, Weighted F1: 0.950, Acc: 96.3% |
| 5 | **Payment Mode** | Preferred transaction mode (`payment_mode`) | XGBoost Classifier | UPI, Debit Card, Cash, Bank Transfer | Accuracy: 23.7% (near chance ~25%) |

*Honest Caveats:*
- Spending and savings targets exhibit low $R^2$ on the volatile 2024 test window due to heavy-winsorized outliers in synthetic data.
- Wellness score $R^2 = 0.9997$ is expected circularity: the training label is rule-derived over the same engineered features.
- Payment method accuracy is bounded near random chance ($\approx 25\%$) because payment modes are uniformly distributed per user in the synthetic source.

---

## Directory Layout

```
ml/
|-- models/                      # Production Candidate Model artifacts
|   |-- spending/random forest/  # model.joblib (Pipeline), preprocessor.joblib, metadata.json
|   `-- risk/gradient boosting/  # model.joblib (Pipeline), preprocessor.joblib, metadata.json
|-- artifacts/                   # 5 longitudinal INR model artifacts
|   |-- spending/                # model.joblib, scaler.pkl, feature_columns.json, metadata.json
|   |-- savings/                 # model.joblib, scaler.pkl, feature_columns.json, metadata.json
|   |-- wellness/                # model.joblib, scaler.pkl, feature_columns.json, metadata.json
|   |-- risk/                    # model.joblib, label_mapping.json, scaler.pkl, metadata.json
|   `-- payment/                 # model.joblib, label_mapping.json, scaler.pkl, metadata.json
|-- features/                    # Feature transformation pipelines
|   |-- feature_engineering.py   # Monthly rolling aggregates, lags, ratios, stability metrics
|   `-- target_generation.py     # Forecasting lead targets and rule-derived wellness/risk labels
|-- training/                    # Model training scripts
|   |-- train_spending.py        # Trains spending forecast models
|   |-- train_savings.py         # Trains savings forecast models
|   |-- train_wellness.py        # Trains wellness score regressor
|   |-- train_risk.py            # Trains financial risk classifier
|   |-- train_payment.py         # Trains payment method classifier
|   `-- utils.py                 # Evaluation, splitting, and persistence helpers
|-- evaluation/                  # Offline evaluation scripts
|   `-- evaluate_models.py       # Computes metrics across test windows -> model_performance_summary.json
|-- explainability/              # Explainable AI (SHAP) generators
|   `-- shap_explainer.py        # Generates SHAP summary plots and feature importance rankings
|-- reports/                     # Output summaries and figures
|   |-- model_performance_summary.json # Combined JSON test metrics
|   `-- shap_*.png / shap_*.csv  # Visual SHAP plots and feature rank tables
|-- Dataset/                     # Source datasets
|   |-- budgetwise_finance_dataset.csv
|   `-- RAW DATA/                # Integrated user profiles and transaction datasets
|-- train_all_with_dl.py         # Deep Learning multi-task training script
`-- test_dl_models.py            # Deep Learning verification and test script
```

---

## Explainable AI (SHAP)

Every model in `ml/` supports feature attribution via SHAP:
- **Tree Models**: Evaluated via `shap.TreeExplainer`.
- **Linear Models**: Evaluated via `shap.LinearExplainer`.
- Reports generated in `ml/reports/`:
  - `shap_spending.png`, `shap_spending_ranks.csv`
  - `shap_savings.png`, `shap_savings_ranks.csv`
  - `shap_wellness.png`, `shap_wellness_ranks.csv`
  - `shap_risk.png`, `shap_risk_ranks.csv`
  - `shap_payment.png`, `shap_payment_ranks.csv`

The FastAPI backend consumes these explainers dynamically over `POST /explain/{model}`, returning the top-12 ranked features with positive or negative attribution scores.

---

## Retraining & Evaluation

To evaluate or retrain models:
```bash
# Evaluate models and generate performance summary:
python ml/evaluation/evaluate_models.py

# Generate SHAP plots:
python ml/explainability/shap_explainer.py

# Train specific model:
python ml/training/train_risk.py
```
*Note: In production serving (`backend/`), models are loaded as pre-fitted sklearn `Pipeline` objects. The backend never retrains or calls `.fit()`.*
