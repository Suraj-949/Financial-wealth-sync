# WealthSync — Frontend Business & Product Document

## Product Vision & Role
The Flutter mobile application is the user-facing interface of the WealthSync platform. It presents personal wealth data through an intuitive, dark fintech design language. The app translates complex machine learning predictions, risk probabilities, and natural language SMS messages into actionable, explainable, and trustworthy financial guidance.

---

## Completed Product Capabilities

1. **Core Five-Tab Navigation (`AppShell`)**:
   - **Home (Dashboard)**: Holistic financial overview with income/expense/savings metrics, wellness score, spending category donut chart, 6-month historical trends, and production ML forecast cards.
   - **Transactions**: Full ledger view with category icons, search, type filtering (All/Income/Expense), manual transaction creation, and transaction deletion.
   - **Budget**: Visual tracking of overall spending against monthly targets and per-category budget utilization.
   - **Goals**: Target milestones for emergency funds, vacations, investments, and home down payments with real-time progress indicators.
   - **More Hub**: Central gateway to advanced tools, credit cards, loans/EMIs, reports, settings, and profile.

2. **Automated SMS Expense Tracking & Timeline**:
   - Seamlessly scans incoming and archived bank SMS on Android devices.
   - Filters out non-financial messages and overt spam before classification.
   - Uses a two-stage NLP model to verify transaction authenticity and categorize it as Credit, Debit, or Other.
   - Features a visual **SMS Timeline** with a month-by-month picker and 1-click import to convert SMS into ledger entries.

3. **Production Credit Risk Assessment**:
   - Evaluates credit risk using a trained Gradient Boosting model on historical payment behaviors.
   - Renders default probability, a calibrated 0–100 risk score, and transparent risk band classifications (Low, Medium, High).
   - Direct link to SHAP feature attributions so users know which credit habits are helping or hurting their score.

4. **Explainable AI (XAI) — "Why this score?"**:
   - Guarantees transparency: every machine learning output is accompanied by feature attribution waterfall and bar charts.
   - Clarifies the exact factors driving changes in the Financial Wellness Score and Credit Risk level.

5. **AI Financial Copilot**:
   - Conversational AI chat grounded in the user's actual transactions, budget limits, and risk profiles.
   - Offers actionable financial tips, payment recommendations, and savings strategies.

6. **Dual Mode (Demo vs. Live Mode)**:
   - **Demo Mode**: Allows risk-free evaluation and sales demonstrations with rich, labelled sample data without requiring a database connection.
   - **Live Mode**: Connects directly to PostgreSQL document storage, partitioning records by user ID so users can track their real finances.

---

## Core UX Principles

- **Zero Cognitive Overhead**: High-contrast typography, recognizable financial symbols, and clear color semantics (green for income, coral/red for expenses, blue/cyan for AI, gold for warnings).
- **Explainability Over Black Boxes**: Predictions are accompanied by plain-language drivers and SHAP explanations; confidence levels are transparently displayed.
- **Privacy First**: Sensitive bank account numbers and card identifiers are masked by default. SMS processing operates locally on-device and through secure user-scoped backend endpoints.
- **Graceful Fault Tolerance**: Every view incorporates custom loading skeletons, empty state illustrations, and actionable error messages with offline fallback.
