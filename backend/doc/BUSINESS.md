# WealthSync — Backend Business & Product Document

## Role & Mission
The FastAPI backend service is the **intelligence, prediction, and persistence engine** of the WealthSync platform. It owns the trained machine learning models, runs the two-stage SMS transaction classifier, generates SHAP-based algorithmic explanations, and persists partitioned user financial documents in PostgreSQL. It acts as the bridge connecting analytical models to the Flutter client.

---

## Core Capabilities Delivered

1. **Production Machine Learning Serving**:
   - **Next-Quarter Expenditure Regressor**: Evaluates household spending trends using the BLS CE 2004 Random Forest model ($R^2 = 0.5367$).
   - **Credit Risk & Default Regressor**: Predicts 30-day default probability using the UCI Credit Default Gradient Boosting model (ROC-AUC = 0.7877), mapping output to an intuitive 0–100 risk score and standard risk bands (Low: 0–30, Medium: 31–60, High: 61–100).
2. **Explainable AI (XAI)**:
   - Eliminates black-box opacity by serving feature attribution via TreeSHAP and LinearSHAP (`POST /explain/{model}`).
   - Enables users to see exactly which financial metrics (savings rate, credit utilization, debt-to-income) are driving their scores.
3. **Automated SMS NLP Classification**:
   - Two-stage NLP pipeline turning messy incoming text into verified financial transactions.
   - Stage 1 filters out spam, promotions, and personal messages.
   - Stage 2 categorizes authentic financial transactions as `credit`, `debit`, or `other`.
4. **Partitioned User Finance Data Persistence**:
   - PostgreSQL JSONB document storage for transactions, accounts, budgets, goals, alerts, and recommendations.
   - Partitions data cleanly per user installation (`user_id` query param or `X-User-Id` header).
   - Allows users to switch seamlessly from offline Demo Mode to real-world persistent tracking.
5. **Model Registry & Try-Me Samples**:
   - Complete discovery of algorithms, targets, feature lists, and test metrics over `GET /models`.
   - Real test-window sample payloads over `GET /sample/{model}` for immediate verification.

---

## Honest Metrics & Model Integrity

WealthSync adheres to strict standards of transparency:
- **BLS Spending Model**: $R^2 = 0.5367$, MAE = \$2,452 USD on unseen test quarterly transitions.
- **UCI Credit Risk Model**: ROC-AUC = 0.7877, Brier Score = 0.1318. Calibrated default rates: Low Band: 12.6%, Medium Band: 40.3%, High Band: 73.6%.
- **Longitudinal INR Spending/Savings Models**: Weak $R^2$ on the volatile 2024 test window; models provide directional guidance rather than exact rupee predictions.
- **Payment Method Model**: Operates near chance accuracy ($\approx 25\%$) due to uniform distribution of payment modes in the synthetic source dataset.
- **Wellness Score**: High $R^2$ ($0.9997$) reflects accurate reproduction of a rule-derived formula, not independent external ground truth.

---

## Technical & Product Roadmap

1. **Authentication & Multi-Device Sync**:
   - Introduce JWT-based user authentication (replacing prototype `user_id` header partitioning).
   - End-to-end encryption for sensitive account balances and card identifiers.
2. **Copilot Grounding Pipeline**:
   - Full server-side LLM orchestration grounding user queries against live PostgreSQL records, model predictions, and SHAP factor weights.
3. **Automated Background SMS Sync**:
   - Background push notifications and automated transaction aggregation when new bank SMS messages arrive on Android.
