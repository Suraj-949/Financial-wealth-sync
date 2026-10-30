# WealthSync Frontend — Architecture & Design

The WealthSync frontend is a Flutter mobile application designed for Android, iOS, and Web with a dark, premium fintech theme. It enforces a strict **Repository Pattern**: UI widgets consume immutable data objects and never perform financial calculations, sums, or percentage arithmetic directly.

---

## Directory & File Structure

```
app/
|-- pubspec.yaml                 # Dependencies: fl_chart, http, intl, flutter_sms_inbox,
|                                #   permission_handler, shared_preferences, flutter_lints
|-- lib/
|   |-- main.dart                # Application entry point: initializes prefs & runs WealthSyncApp
|   |-- config.dart              # API_BASE config (default http://10.0.2.2:8000, --dart-define support)
|   |
|   |-- app/
|   |   |-- app.dart             # WealthSyncApp -> MaterialApp(theme) -> AppShell
|   |   |-- theme.dart           # AppColors (design tokens), AppTheme (Material 3 dark theme)
|   |   |-- constants.dart       # User name, default date ranges (AppConstants)
|   |   `-- routes.dart          # Named-route constants (AppRoutes)
|   |
|   |-- utils/
|   |   `-- formatters.dart      # Formatters: INR currency, percentages, date/time helpers
|   |
|   |-- widgets/
|   |   |-- common.dart          # Shared UI: AppCard, SectionHeader, Pill, TagBadge,
|   |   |                        #   EmptyState, ErrorState, Skeleton, DashboardSkeleton
|   |   `-- transaction_card.dart# Reusable TransactionTile (used in dashboard & transactions)
|   |
|   |-- models/models.dart       # Core domain types: Transaction, Account, FinancialSummary,
|   |                            #   SpendingCategory, BudgetItem, Goal, AiInsight, PaymentOffer,
|   |                            #   Recommendation, AlertItem, ShapFactor, CopilotReply,
|   |                            #   SpendingPrediction (BLS USD), InrForecast (monthly INR),
|   |                            #   RiskPrediction (UCI), ShapExplanation, SmsClassification
|   |
|   |-- services/
|   |   |-- finance_repository.dart   # Abstract FinanceRepository, DashboardData aggregate,
|   |   |                             #   MockFinanceRepository, ApiFinanceRepository (live PostgreSQL
|   |   |                             #   persistence & ML), ApiClient, demoModeEnabled & user namespace
|   |   |-- mock_data.dart            # Labelled mock datasets for offline mode
|   |   |-- finance_refresh.dart      # FinanceDataListener mixin for reactive UI updates
|   |   |-- sms_inbox_service.dart    # Reads device SMS inbox, filters bank transactions & paginates
|   |   `-- sms_transaction_importer.dart # Regex parser extracting amount, merchant & adding to ledger
|   |
|   `-- screens/                      # One folder per feature screen
|       |-- shell/app_shell.dart      # Bottom NavigationBar + IndexedStack (5 main tabs)
|       |-- dashboard/
|       |   |-- dashboard_screen.dart # Financial summary, date filter sheet, refresh listener
|       |   `-- widgets/
|       |       |-- dashboard_sections.dart # Summary cards, quick actions, ML prediction card
|       |       |-- dashboard_lists.dart    # Insights, payment suggestions, copilot card, accounts
|       |       `-- charts.dart             # SpendingDonut, ExpensePredictionChart, ProgressBar
|       |-- transactions/
|       |   |-- transactions_screen.dart    # Filter chips (All/Income/Expense) & transaction deletion
|       |   `-- add_transaction_sheet.dart  # Bottom sheet modal to add new transactions
|       |-- budget/budget_screen.dart       # Budget limits and per-category progress bars
|       |-- goals/goals_screen.dart         # Savings goals progress cards
|       |-- more/
|       |   |-- more_screen.dart            # Hub navigation to sub-features and settings
|       |   `-- settings_screen.dart        # Demo mode switch, user id editor, backend diagnostics
|       |-- accounts/accounts_screen.dart   # Masked account & card balances
|       |-- alerts/alerts_screen.dart       # Financial notifications with unread dot indicators
|       |-- recommendations/recommendations_screen.dart # AI recommendations with category filters
|       |-- copilot/copilot_chat_screen.dart# Natural language Q&A chat grounded in user data
|       |-- risk/risk_screen.dart           # Credit risk assessment (UCI Gradient Boosting + SHAP)
|       |-- xai/xai_screen.dart             # Explainable AI (SHAP) score breakdown and feature bars
|       |-- sms/sms_classifier_screen.dart  # Two tabs: Manual SMS Classifier + Live SMS Timeline
|       |-- profile/profile_screen.dart     # User profile card & financial preferences
|       `-- stub/stub_screen.dart           # Placeholder view for upcoming modules
|
|-- test/                                   # Automated test suite (20 tests passing)
|   |-- api_client_test.dart                # Deserialization and response binding
|   |-- live_dashboard_test.dart            # Aggregates live PostgreSQL rows into dashboard figures
|   |-- prediction_card_test.dart           # Production BLS prediction card widget rendering
|   |-- sms_classifier_test.dart            # Two-stage classification approval and spam rejection
|   |-- sms_timeline_test.dart              # SMS date grouping and month-picker highlights
|   `-- widget_test.dart                    # App boot, navigation shell, and dashboard state tests
`-- doc/                                    # Frontend documentation (AGENTS, ARCHITECTURE, BUSINESS)
```

---

## Data Layer & Persistence Architecture

The app is built around the `FinanceRepository` abstract contract:

```
                  +-----------------------------------+
                  |      FinanceRepository (IFace)    |
                  +-----------------+-----------------+
                                    |
          +-------------------------+-------------------------+
          |                                                   |
          v                                                   v
+-----------------------+                   +-----------------------------------+
| MockFinanceRepository |                   |       ApiFinanceRepository        |
|  (Hermetic dev data)  |                   |  (Live FastAPI + PostgreSQL + ML) |
+-----------------------+                   +-----------------+-----------------+
                                                              |
                                               +--------------+--------------+
                                               |                             |
                                               v                             v
                                     +-------------------+         +-------------------+
                                     |   ApiClient       |         | Fallback to Mock  |
                                     | (PostgreSQL CRUD  |         | (If backend is    |
                                     |  & ML Endpoints)  |         |  unreachable)     |
                                     +-------------------+         +-------------------+
```

### 1. Dual Mode (Demo vs. Live Mode)
- **Demo Mode (`demoModeEnabled = true`)**:
  - Uses `MockFinanceRepository` with realistic data defined in `mock_data.dart`.
  - Simulates network delay (configurable, skipped during tests).
  - Perfect for offline demonstrations and hermetic widget testing.
- **Live Mode (`demoModeEnabled = false`)**:
  - Uses `ApiFinanceRepository`. Reads from and writes to the user's PostgreSQL namespace via `/api/data/{resource}`.
  - Aggregates income, expenses, category spending, trends, and wellness score directly from live user records.
- **Dynamic Switching**:
  - The mode is controlled via `demoModeListenable`. When toggled in **Settings**, all mounted screens rebuild and fetch fresh data from the active data source.

### 2. User Namespace Partitioning
- The prototype uses a stable installation ID (`local-user` by default).
- Stored locally via `SharedPreferences`.
- Sent with every request as `?user_id=` or in the `X-User-Id` HTTP header.
- Users can view and switch namespaces under **More -> Settings -> Data Namespace**.

### 3. Reactive Refresh System
- When a transaction is added or deleted (via `AddTransactionSheet` or `SmsTransactionImporter`), `notifyFinanceDataChanged()` increments `financeDataRevision`.
- Screens mix in `FinanceDataListener` to automatically re-fetch data without manual user reloading.

---

## SMS Tracking Pipeline

The SMS integration is a two-tier hybrid system combining on-device scanning with backend NLP intelligence:

1. **Inbox Scanning (`SmsInboxService`)**:
   - Requests Android `READ_SMS` runtime permissions via `permission_handler`.
   - Queries inbox messages with pagination (`flutter_sms_inbox`).
   - Applies regex keyword filters to isolate financial messages (e.g. `credited`, `debited`, `transfer`, `UPI`, `ATM`) while stripping overt spam.
2. **Two-Stage Machine Learning Classification**:
   - Sends candidate SMS text to `POST /api/sms/classify`.
   - Stage 1 confirms message is legitimate financial text (not spam or personal chat).
   - Stage 2 classifies the transaction as `credit`, `debit`, or `other`.
3. **Regex Extraction & 1-Click Import (`SmsTransactionImporter`)**:
   - Parses the transaction amount (`₹`, `Rs.`, `INR`, `$`) and merchant/counterparty from the text.
   - Converts the approved SMS into a typed `Transaction` entity.
   - Injects the transaction directly into the user's active ledger with reactive UI refresh.

---

## ML Models Consumed by Frontend

| Model Family | Endpoint | Input | UI Consumer |
|---|---|---|---|
| **BLS Spending (Production)** | `POST /api/ml/spending/predict` | 22 demographic & economic features | `PredictionCard` on Dashboard (next-quarter USD forecast) |
| **UCI Credit Risk (Production)** | `POST /api/ml/risk/predict` | 26 payment history & credit features | `RiskAssessmentScreen` (0–100 risk score and level) |
| **Longitudinal INR Models** | `POST /predict/{model}` | Monthly financial feature vectors | Dashboard summary cards & trends (spending, savings, wellness) |
| **Explainable AI (SHAP)** | `POST /explain/{model}` | Feature vector | `XaiScreen` & `RiskAssessmentScreen` (waterfall & factor bars) |
| **Two-Stage SMS NLP** | `POST /api/sms/classify` | Raw SMS text message | `SmsClassifierScreen` & SMS Timeline import pipeline |

---

## Quality & Verification Standards

After modifying frontend code, always run:
1. `flutter analyze` — verify **0 issues**.
2. `flutter test` — verify all **20 tests** pass without regressions.
3. `flutter build apk --debug` — verify clean compilation.
