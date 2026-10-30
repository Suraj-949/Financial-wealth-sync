# WealthSync Mobile Client (`app/`)

WealthSync is a Flutter mobile application designed for personal wealth intelligence. It features a dark fintech user interface, automated SMS-based expense tracking, predictive machine learning forecasts, explainable AI (XAI) score breakdowns, and an AI financial copilot.

---

## Architectural Principles

1. **Repository Pattern as Single Source of Truth**:
   - Widgets consume data objects delivered by `FinanceRepository`.
   - Widgets **never** perform financial calculations, sums, or percentage arithmetic inside `build()`.
2. **Dual-Mode Data Layer**:
   - **Demo Mode**: Hermetic offline experience utilizing realistic sample financial data (`mock_data.dart`). Enabled by default on fresh installs.
   - **Live Mode**: Directly connected to the FastAPI backend and PostgreSQL persistence (`/api/data/{resource}`). Seamlessly switches data source across all screens via `demoModeListenable`.
3. **User Namespace Partitioning**:
   - Each app installation maintains a stable identifier (`local-user` by default, customizable in Settings).
   - Passed via query parameter `?user_id=` or `X-User-Id` HTTP header to partition data in PostgreSQL.
4. **Resilient Offline Fallback**:
   - Screens attempt to load live ML predictions and backend data via `getApiRepository()`, gracefully falling back to offline defaults if the backend is unreachable.
5. **No Black Boxes (Explainable AI)**:
   - Financial wellness and risk predictions are backed by SHAP factor attributions so users can understand *why* their score was calculated.

---

## Screen & Feature Walkthrough

### 1. Dashboard (`screens/dashboard/`)
- **Financial Summary Cards**: Monthly income, total expenses, documented savings, and financial wellness score (0–100) with colored delta pills.
- **Spending Donut & Legend**: Category breakdown using `fl_chart`.
- **Expense Prediction Chart**: 6-month historical expense trend overlaid with next-month forecast and confidence band.
- **Production ML Prediction Card**: Displays next-quarter household expenditure forecast from the backend's BLS Random Forest model.
- **Smart Payment Suggestion**: AI recommendation for credit card vs. UPI optimization.
- **AI Insights & Copilot Card**: Context-aware tips and one-tap entry to Copilot chat.
- **Accounts & Recent Transactions**: Masked account balances and transaction quick tiles.

### 2. Transactions Ledger (`screens/transactions/`)
- Transaction list with search and filter chips (**All**, **Income**, **Expense**).
- Add Transaction bottom sheet with category, account, payment method, date picker, and note support.
- Delete transactions with automatic reactive refresh across the dashboard and budget tabs.

### 3. Budget & Goals (`screens/budget/`, `screens/goals/`)
- **Budget**: Overall monthly spending progress against limits and per-category budget bars.
- **Goals**: Target amount, saved so far, target completion date, and visual percentage indicators.

### 4. SMS Transaction Tracker & Timeline (`screens/sms/`)
- **Tab 1: Manual Classifier**: Paste or test sample SMS messages to see stage-1 spam detection and stage-2 categorization (Credit / Debit / Other).
- **Tab 2: SMS Timeline**:
  - Automatically queries device inbox messages via `flutter_sms_inbox`.
  - Filters bank transaction keywords (`credited`, `debited`, `transfer`, `UPI`, `ATM`, etc.) and discards spam.
  - Interactive month picker showing which historical months have transaction messages.
  - One-click **Import to Ledger** using `SmsTransactionImporter`, extracting amount, merchant/sender, date, and transaction type via regex.

### 5. Credit Risk Assessment (`screens/risk/`)
- Live integration with the UCI Credit Card Default Gradient Boosting model (`POST /api/ml/risk/predict`).
- Displays default probability, 0–100 risk score, and band assignment (Low / Medium / High).
- Feature attribution drawer linking to the SHAP XAI breakdown.

### 6. Explainable AI (XAI) — "Why this score?" (`screens/xai/`)
- Radial score gauge displaying the user's financial health score.
- Ranked SHAP feature impact bars showing top positive and negative drivers (e.g. debt-to-income ratio, savings rate, credit utilization).

### 7. AI Copilot Chat (`screens/copilot/`)
- Conversational chat interface grounded in the user's live financial data.
- Structured replies with actionable financial recommendations.

### 8. Settings & Profile (`screens/more/`)
- Toggle **Demo Mode** on/off.
- Inspect and change user data namespace identifier.
- Backend and PostgreSQL connectivity diagnostics.

---

## Directory Structure

```
app/lib/
|-- main.dart                     # App entry point (runApp)
|-- config.dart                   # API_BASE configuration (--dart-define support)
|-- app/
|   |-- app.dart                  # WealthSyncApp widget and MaterialApp setup
|   |-- constants.dart            # Constant strings, date ranges, defaults
|   |-- routes.dart               # Named route definitions
|   `-- theme.dart                # AppColors token palette and AppTheme
|-- models/
|   `-- models.dart               # Complete domain models (Transaction, Account, Prediction, etc.)
|-- services/
|   |-- finance_repository.dart   # Abstract repository, ApiClient, live & mock implementations
|   |-- mock_data.dart            # Labelled mock datasets for offline mode
|   |-- finance_refresh.dart      # Reactive mixins for data change notifications
|   |-- sms_inbox_service.dart    # Android inbox scanner with bank heuristics & pagination
|   `-- sms_transaction_importer.dart # Regex parser converting SMS to ledger transactions
|-- utils/
|   `-- formatters.dart           # Currency (INR), date, percentage helpers
|-- widgets/
|   |-- common.dart               # AppCard, SectionHeader, Pill, TagBadge, Skeletons
|   `-- transaction_card.dart     # Reusable transaction list tile
`-- screens/
    |-- shell/app_shell.dart      # 5-tab root shell with IndexedStack
    |-- dashboard/                # Dashboard screen and modular widgets
    |-- transactions/             # Ledger list and Add Transaction sheet
    |-- budget/                   # Budget tracking screen
    |-- goals/                    # Financial goals screen
    |-- more/                     # More hub, Settings, and Stub screens
    |-- accounts/                 # Masked accounts overview
    |-- alerts/                   # Financial alerts and notifications
    |-- recommendations/          # Personalized AI recommendation cards
    |-- copilot/                  # AI Copilot chat screen
    |-- risk/                     # Credit risk assessment screen
    |-- xai/                      # Explainable AI (SHAP) factor view
    |-- sms/                      # SMS classifier and timeline screen
    `-- profile/                  # User profile and settings
```

---

## Setup & Running

### Dependencies
Run in the `app/` directory:
```bash
flutter pub get
```

### Running on Device / Emulator
```bash
# Standard run (connects to default backend at http://10.0.2.2:8000 for Android emulator):
flutter run

# Specify custom backend host (e.g. for physical devices or desktop):
flutter run --dart-define=API_BASE=http://192.168.1.100:8000
```

### Android Permissions
For SMS reading functionality, ensure permissions are declared in `android/app/src/main/AndroidManifest.xml`:
```xml
<uses-permission android:name="android.permission.READ_SMS"/>
<uses-permission android:name="android.permission.RECEIVE_SMS"/>
```
Runtime permission requests are automatically handled via `permission_handler`.

---

## Testing & Quality Assurance

Run the test suite from the `app/` folder:
```bash
# Run unit and widget tests:
flutter test

# Run static code analysis:
flutter analyze
```

### Test Suite Breakdown:
- `test/live_dashboard_test.dart`: Verifies PostgreSQL row aggregation and zeroes handling.
- `test/api_client_test.dart`: Validates async deserialization and response attachment.
- `test/prediction_card_test.dart`: Tests display of production ML prediction cards.
- `test/sms_classifier_test.dart`: Validates two-stage SMS classification approval and spam filtering.
- `test/sms_timeline_test.dart`: Tests inbox date grouping and month-picker highlighting.
- `test/widget_test.dart`: Verifies root app boot, shell navigation, and summary cards.
