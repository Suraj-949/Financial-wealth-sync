# WealthSync Frontend — File Architecture

Flutter app, Android-first, dark premium fintech theme. Repository pattern: widgets consume data
objects; they never compute financial figures.

```
app/
├── pubspec.yaml                 # deps: fl_chart, http, intl
├── lib/
│   ├── main.dart                # entry: WealthSyncApp → MaterialApp(theme) → AppShell
│   ├── config.dart              # API_BASE (default http://10.0.2.2:8000, --dart-define override)
│   │
│   ├── core/
│   │   ├── constants/app_constants.dart   # user name, dashboard date ranges
│   │   ├── routes/app_routes.dart         # named-route constants
│   │   ├── theme/app_theme.dart           # AppColors, AppTheme, AppCard, SectionHeader,
│   │   │                                   #   Pill, TagBadge, EmptyState, ErrorState,
│   │   │                                   #   Skeleton, DashboardSkeleton
│   │   └── utils/formatters.dart          # INR / % / date helpers
│   │
│   ├── models/models.dart      # Transaction, Account, FinancialSummary, SpendingCategory,
│   │                           #   BudgetItem, Goal, AiInsight, PaymentOffer/Suggestion,
│   │                           #   Recommendation, AlertItem, ShapFactor, CopilotReply/Message
│   │
│   ├── services/
│   │   ├── finance_repository.dart   # FinanceRepository (abstract) + DashboardData aggregate,
│   │   │                             #   MockFinanceRepository (setDelay), getRepository(),
│   │   │                             #   ApiClient for ML endpoints
│   │   └── mock_data.dart            # MockData (labelled) — dev only
│   │
│   └── features/
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
│       ├── profile/profile_screen.dart              # user card + rows
│       └── stub/stub_screen.dart                    # placeholder for upcoming features
├── test/
│   └── widget_test.dart        # boots app + verifies summary (delay=0)
└── doc/                         # frontend-scoped docs (BUSINESS, AGENTS, ARCHITECTURE)
```

## Data contract (everything flows from the repository)
`FinanceRepository`: `fetchDashboard`, `fetchTransactions`, `fetchBudget`, `fetchGoals`,
`fetchRecommendations`, `fetchAlerts`, `fetchAccounts`, `fetchXaiFactors`, `fetchPaymentOffers`,
`copilotAsk`.

`DashboardData` aggregates: `summary` (income/expenses/savings/wellness + deltas), `categories`
(donut), `historicExpense` + `predictedExpense` + `predictionConfidence` + `monthLabels`,
`insights`, `paymentSuggestion`, `accounts`, `recentTransactions`.

## Adding a screen
1. `features/<name>/<name>_screen.dart` (StatefulWidget + repo load, own loading/error empty states).
2. Push via `Navigator.push(MaterialPageRoute(...))` or add to `features/shell/app_shell.dart` tabs.
3. Reuse theme widgets + `Formatters`; never compute figures in the widget.
4. Verify: analyze → test → debug APK.