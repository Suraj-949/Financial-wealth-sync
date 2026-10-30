import 'package:flutter/widgets.dart';

import 'finance_repository.dart';

/// Reloads a screen whenever a finance write succeeds, so tabs that stay alive
/// inside the shell (transactions, budgets, goals, ...) never show stale rows.
mixin FinanceDataListener<T extends StatefulWidget> on State<T> {
  @override
  void initState() {
    super.initState();
    financeDataRevision.addListener(_onRevision);
  }

  @override
  void dispose() {
    financeDataRevision.removeListener(_onRevision);
    super.dispose();
  }

  void _onRevision() {
    if (mounted) onFinanceDataChanged();
  }

  /// Implemented by screens to refresh their own data.
  void onFinanceDataChanged();
}
