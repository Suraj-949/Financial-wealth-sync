# WealthSync — Frontend Business Document

## Role
The Flutter app is the **user-facing surface** of WealthSync: a dark, premium fintech mobile
dashboard. It presents the user's financial story — wellness score, spending, predictions,
insights, payments, goals — and turns the backend's ML outputs into trustworthy, explainable UI.

## Product surfaces built
1. **Five-tab shell** — Home / Transactions / Budget / Goals / More (`IndexedStack` keeps state).
2. **Dashboard** — greeting + date-range filter, income/expense/savings cards, Financial Wellness
   Score card, quick actions, spending donut, expense prediction chart, AI insights,
   smart payment suggestion, AI Copilot card, accounts band, recent transactions.
3. **Transactions** — filter chips (All/Income/Expense); **Budget** — per-category progress;
   **Goals** — target progress.
4. **Accounts** — masked balances; **Alerts** — read/unread; **Recommendations** — category filters.
5. **AI Copilot chat** — natural-language Q&A grounded in the user's data (renders replies from the
   grounding pipeline).
6. **"Why this score?" (XAI)** — wellness ring + SHAP factor bars + prediction-vs-explanation note.

## UX principles (business asks)
- Numbers must be **instantly scannable** (INR formatting, colored deltas, donut + legend).
- AI is everywhere but **never a black box**: confidence is shown, explanations link back to data.
- **Privacy by default**: balances/bank details are masked unless the user expands.
- Loading/error/empty states on every data view (mock repository adds ~650ms delay to exercise them).

## Status
- Full spec UI built: `flutter analyze` clean, widget tests green, debug APK builds.
- Data currently comes from `MockFinanceRepository` (labelled mock); production values flow from the
  backend API (`GET /api/dashboard` next).