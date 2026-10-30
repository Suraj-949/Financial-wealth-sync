# AGENTS.md — WealthSync Frontend Guidelines

Scope: `app/` — The Flutter mobile application (Android-first, dark premium fintech theme).

---

## Environment & Commands

- **Flutter SDK**: `C:\flutter\bin\flutter.bat` (Flutter 3.38.9, Dart 3.10.8).
- **Mandatory Verification Workflow** (run from `app\`):
  1. `flutter analyze` — must report **0 issues**.
  2. `flutter test` — all **20 tests** must pass green.
  3. `flutter build apk --debug` — verify clean build compilation.
- **Dependency Management**:
  - Run `flutter pub get` after updating `pubspec.yaml`.
  - State management uses built-in Flutter primitives (`StatefulWidget`, `ValueNotifier`, `ListenableBuilder`) — do not introduce heavy state packages (Bloc, Riverpod, Redux) without explicit direction.

---

## Architecture Rules (Golden Rules)

1. **Widgets Never Calculate Financial Figures**:
   - Every financial number, sum, delta, or percentage must be calculated in the model or repository layer (`lib/services/finance_repository.dart` or `models.dart`).
   - `build()` methods must only render data objects; never perform business arithmetic inline.
2. **Never Fake Production Confidence or Values**:
   - `MockData` in `mock_data.dart` is explicitly marked as mock data for offline prototype mode.
   - Production screens must use `ApiFinanceRepository` which queries real endpoints (`/api/ml/*`, `/api/data/*`, `/api/sms/*`) and provides graceful fallbacks.
3. **Respect Theming and Component Standards**:
   - Colors and styles come exclusively from `AppColors` and `AppTheme` in `lib/app/theme.dart`.
   - Reusable widgets live in `lib/widgets/common.dart` (`AppCard`, `SectionHeader`, `Pill`, `TagBadge`, `EmptyState`, `ErrorState`, `Skeleton`).
   - ⚠️ **Important**: Use `TagBadge`, never Material 3's built-in `Badge` widget (which collides with our badge design).
4. **Strict Modular Folder Layout**:
   - Each major screen lives in its own dedicated directory under `lib/screens/<feature>/`.
   - Screen-specific sub-widgets belong in `lib/screens/<feature>/widgets/`. Shared widgets belong in `lib/widgets/`.
5. **Dual Mode & Reactive Data Flow**:
   - Respect `demoModeEnabled` and `demoModeListenable`. When demo mode is toggled, all screens must reload from the active source.
   - After adding or deleting records, call `notifyFinanceDataChanged()` to trigger reactive refresh via `FinanceDataListener`.
6. **Flutter 3.38 Testing Constraints**:
   - Avoid `pumpAndSettle()` on screens with infinite looping animations (such as skeletons); use `pump()` with fixed durations.
   - `MockFinanceRepository.setDelay(0)` is required in widget tests to avoid timer deadlocks.

---

## Key Files Reference

- `lib/main.dart`: App bootstrapper loading SharedPreferences preferences and running `WealthSyncApp`.
- `lib/app/app.dart`: App root setting up the MaterialApp, routing, and `AppShell`.
- `lib/screens/shell/app_shell.dart`: 5-tab shell (Home, Transactions, Budget, Goals, More) preserving state with `IndexedStack`.
- `lib/services/finance_repository.dart`: Core repository definitions, `DashboardData` aggregate, `MockFinanceRepository`, `ApiFinanceRepository`, and `ApiClient`.
- `lib/services/sms_inbox_service.dart`: Android SMS inbox reader with permission handling, banking keywords regex, and pagination.
- `lib/services/sms_transaction_importer.dart`: Automated transaction extraction from bank SMS into ledger entries.
- `lib/screens/sms/sms_classifier_screen.dart`: Two-tab SMS screen featuring single-message testing and full SMS timeline with month picker.
- `lib/screens/risk/risk_screen.dart`: Live UCI credit risk assessment screen with SHAP XAI breakdown.
- `lib/screens/xai/xai_screen.dart`: Explainable AI screen showing SHAP factor contribution bars.

---

## Test Inventory (20 Passing Tests)

- `test/api_client_test.dart`: Verifies async deserialization for predict and explain API calls.
- `test/live_dashboard_test.dart`: Verifies live PostgreSQL row aggregation and handling of empty accounts.
- `test/prediction_card_test.dart`: Verifies BLS ML forecast card rendering on dashboard.
- `test/sms_classifier_test.dart`: Validates two-stage SMS classification approval and spam rejection.
- `test/sms_timeline_test.dart`: Validates inbox message date formatting and month-picker highlights.
- `test/widget_test.dart`: Tests root app bootstrap, financial summary cards, and navigation.
