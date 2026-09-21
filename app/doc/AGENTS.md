# AGENTS.md — WealthSync Frontend (opencode / agent instructions)

Scope: `app/` — the Flutter mobile app (Android-first, dark fintech theme).

## Environment & Commands

- **Flutter:** `C:\flutter\bin\flutter.bat` (Flutter 3.38.9, Dart 3.10.8).
- **Verification — ALWAYS run after UI changes (from `app\`):**
  1. `flutter analyze`
  2. `flutter test`
  3. `flutter build apk --debug`
- State management is plain `StatefulWidget` — no extra packages beyond the current deps
  (`fl_chart`, `http`, `intl`). Run `flutter pub get` after adding deps.

## Architecture rules (golden)

1. **Widgets must never calculate financial figures.** Every number comes from a data object
   delivered by `lib/services/finance_repository.dart`. Use `MockFinanceRepository` for dev only.
2. **Never fake confidence/values.** `MockData` is labelled mock (e.g. `predictionConfidence`
   comment). Production values come from the backend — no fabricated figures in release code.
3. **Share the theme, don't invent styles.** `AppColors`, `AppCard`, `SectionHeader`, `Pill`,
   `TagBadge`, `EmptyState`, `ErrorState`, `Skeleton` from `core/theme/app_theme.dart`.
   ⚠️ Use `TagBadge`, not `Badge` (Material 3's `Badge` widget collides).
4. **One feature, one folder.** `features/<name>/<name>_screen.dart`, wired via `Navigator.push`;
   shell tabs live in `features/shell/app_shell.dart`. Sub-widgets go in `features/<name>/widgets/`.
5. **No arithmetic in build().** Sums/percentages belong in the repository/models layer.
6. **Flutter 3.38 gotchas:** Material 3 `Badge` exists → use `TagBadge`. Avoid `const` around
   widgets whose children are runtime values (callbacks/methods) — the analyzer rejects it.

## Key files
- `lib/main.dart` → `lib/features/shell/app_shell.dart` (entry + tabs).
- `lib/services/finance_repository.dart` — repo IFace, `DashboardData`, `MockFinanceRepository`,
  `getRepository()`, `ApiClient` (ML endpoints; swap mocks for `GET /api/dashboard` next).
- `lib/services/mock_data.dart` — demo data (labelled).
- `lib/models/models.dart` — all domain types.
- Screens: `features/dashboard/`, `transactions/`, `budget/`, `goals/`, `more/`, `accounts/`,
  `alerts/`, `recommendations/`, `copilot/`, `xai/`, `profile/`, `stub/`.
- Tests: `test/widget_test.dart` (set `MockFinanceRepository.setDelay(0)` in `setUpAll`).

## Verify before finishing
`flutter analyze` (0 issues) → `flutter test` (all pass — avoid `pumpAndSettle` on infinite
skeleton/animations) → `flutter build apk --debug` succeeds.

## Status
- Full spec UI built; analyze clean, tests green, debug APK builds.
- Next: wire real API-backed dashboard + copilot replies from the backend.