# WealthSync Frontend — File Architecture

Flutter app, Android-first, dark premium fintech theme. Repository pattern: widgets consume data
objects; they never compute financial figures.

```
app/
├── pubspec.yaml                 # deps: fl_chart, http, intl
├── lib/
│   ├── main.dart                # entry: runApp(WealthSyncApp)
│   ├── config.dart              # API_BASE (default http://10.0.2.2:8000, --dart-define override)
│   │
│   ├── app/
│   │   ├── app.dart             # WealthSyncApp → MaterialApp(theme) → AppShell
│   │   ├── theme.dart           # AppColors (tokens), AppTheme (MaterialApp theme)
│   │   ├── constants.dart       # user name, dashboard date ranges (AppConstants)
│   │   └── routes.dart          # named-route constants (AppRoutes)
│   │
│   ├── utils/
│   │   └── formatters.dart      # Formatters: INR / % / date helpers
│   │
│   ├── widgets/
│   │   ├── common.dart          # shared UI: AppCard, SectionHeader, Pill, TagBadge,
│   │   │                        #   EmptyState, ErrorState, Skeleton, DashboardSkeleton
│   │   └── transaction_card.dart# TransactionTile (dashboard + transactions reuse)
│   │
│   ├── models/models.dart      # Transaction, Account, FinancialSummary, SpendingCategory,
│   │                           #   BudgetItem, Goal, AiInsight, PaymentOffer/Suggestion,
│   │                           #   Recommendation, AlertItem, ShapFactor, CopilotReply/Message,
│   │                           #   SpendingPrediction (BLS USD), InrForecast (monthly INR),
│   │                           #   RiskPrediction (UCI), ShapExplanation(Item),
│   │                           #   SmsClassification (spam + credit/debit/other)
│   │
│   ├── services/
│   │   ├── finance_repository.dart   # FinanceRepository (abstract) + DashboardData aggregate,
│   │   │                             #   MockFinanceRepository (setDelay), getRepository(),
│   │   │                             #   ApiClient (typed ML helpers), ApiFinanceRepository
│   │   │                             #   (live backend, mock fallback), getApiRepository()
│   │   └── mock_data.dart            # MockData (labelled) — dev only
│   │
│   └── screens/                       # one folder per feature/screen
│       ├── shell/app_shell.dart            # bottom NavigationBar + IndexedStack (5 tabs)
│       ├── dashboard/
│       │   ├── dashboard_screen.dart       # greeting, date-range sheet, slivers, states
│       │   └── widgets/
│       │       ├── dashboard_sections.dart # summary cards, quick actions, prediction card…
│       │       ├── dashboard_lists.dart    # insights, payment suggestion, copilot card,
│       │       │                           #   accounts band, recent transactions
│       │       └── charts.dart             # SpendingDonut, ExpensePredictionChart, ProgressBar
│       ├── transactions/transactions_screen.dart   # chips: All/Income/Expense
│       ├── budget/budget_screen.dart                # totals + per-category progress
│       ├── goals/goals_screen.dart                  # goal progress cards
│       ├── more/more_screen.dart                    # hub → stub features + Alerts/Copilot/Profile
│       ├── accounts/accounts_screen.dart            # masked accounts & cards
│       ├── alerts/alerts_screen.dart                # unread dot + mark-all-read
│       ├── recommendations/recommendations_screen.dart  # category filter + actions
│       ├── copilot/copilot_chat_screen.dart         # grounded chat UI (renders CopilotReply)
│       ├── xai/xai_screen.dart                      # wellness ring + SHAP bars
│       ├── sms/sms_classifier_screen.dart           # paste SMS → spam/category result
│       ├── profile/profile_screen.dart              # user card + rows
│       └── stub/stub_screen.dart                    # placeholder for upcoming features
├── test/
│   └── widget_test.dart        # boots app + verifies summary (delay=0)
└── doc/                         # frontend-scoped docs (BUSINESS, AGENTS, ARCHITECTURE)
```

## Data contract (everything flows from the repository)
`FinanceRepository`: `fetchDashboard`, `fetchTransactions`, `fetchBudget`, `fetchGoals`,
`fetchRecommendations`, `fetchAlerts`, `fetchAccounts`, `fetchXaiFactors`, `fetchPaymentOffers`,
`copilotAsk`, plus the ML surface: `fetchSpendingPrediction` (BLS USD),
`fetchInrForecast` (INR spending/savings/wellness bundle), `fetchRiskPrediction`
+ `fetchRiskExplanation` (UCI), and `classifySms` (two-stage SMS pipeline:
`POST /api/sms/classify`, with an on-device keyword fallback when offline).

`DashboardData` aggregates: `summary` (income/expenses/savings/wellness + deltas), `categories`
(donut), `historicExpense` + `predictedExpense` + `predictionConfidence` + `monthLabels`,
`insights`, `paymentSuggestion`, `accounts`, `recentTransactions`, plus best-effort
`mlPrediction` (BLS quarterly USD card) and `inrForecast` (monthly INR bundle that
also upgrades `summary.savings` / `summary.wellnessScore`).

## ML pipeline (three model families — do not mix their units)
| Family | Models | Endpoints | Units | Used by |
|---|---|---|---|---|
| BLS/UCI (`ml/models/`) | spending RF, risk GBM | `POST /api/ml/spending/predict`, `POST /api/ml/risk/predict` | USD quarterly / 0-100 score | PredictionCard, Risk screen |
| INR monthly (`ml/artifacts/`) | spending, savings, wellness, risk | `GET /sample/{model}` → `POST /predict/{model}` (+ `POST /explain/{model}`) | INR monthly / 0-100 | Dashboard summary, XAI screen |
| SMS text (`sms/`) | spam filter → category | `POST /api/sms/classify` (+ `/batch`, `/health`) | status + credit/debit/other + % | SMS Classifier screen |

`getRepository()` returns the offline mock (tests stay hermetic). Screens call
`getApiRepository()` best-effort and keep mock content on failure — never turn a
tab into an error just because the backend is down. `MockFinanceRepository.setDelay(0)`
skips timers entirely (a zero `Future.delayed` deadlocks `testWidgets` fake async).

## Adding a screen
1. `screens/<name>/<name>_screen.dart` (StatefulWidget + repo load, own loading/error empty states).
2. Push via `Navigator.push(MaterialPageRoute(...))` or add to `screens/shell/app_shell.dart` tabs.
3. Reuse theme/widgets (`app/theme.dart`, `widgets/common.dart`) + `Formatters`; never compute
   figures in the widget.
4. Verify: analyze → test → debug APK.