import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../widgets/common.dart';
import '../../utils/formatters.dart';
import '../../models/models.dart';
import '../../services/finance_repository.dart';
import '../../services/finance_refresh.dart';
import '../dashboard/widgets/charts.dart';

class BudgetTab extends StatefulWidget {
  const BudgetTab({super.key});

  @override
  State<BudgetTab> createState() => _BudgetTabState();
}

class _BudgetTabState extends State<BudgetTab>
    with FinanceDataListener<BudgetTab> {
  final repo = getRepository();

  List<BudgetItem>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void onFinanceDataChanged() => _load();

  Future<void> _load() async {
    try {
      final items = await repo.fetchBudget();
      if (!mounted) return;
      setState(() {
        _items = items;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final totalSpent =
        (items ?? const <BudgetItem>[]).fold<double>(0, (a, b) => a + b.spent);
    final totalLimit =
        (items ?? const <BudgetItem>[]).fold<double>(0, (a, b) => a + b.limit);

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: _load,
        color: AppColors.accent,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 20),
          children: [
            Row(
              children: [
                Text('Budget',
                    style: const TextStyle(
                        color: AppColors.textPrimary, fontSize: 21, fontWeight: FontWeight.w800)),
                const Spacer(),
                IconButton(
                  onPressed: () => ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(const SnackBar(content: Text('Set a new budget is coming soon.'))),
                  icon: const Icon(Icons.add_circle_outline, color: AppColors.accent),
                ),
              ],
            ),
            if (_error != null)
              ErrorState(message: _error!, onRetry: _load)
            else if (items == null)
              Column(children: const [
                Skeleton(height: 90, radius: 16),
                SizedBox(height: 12),
                Skeleton(height: 70, radius: 16),
                SizedBox(height: 12),
                Skeleton(height: 70, radius: 16),
              ])
            else if (items.isEmpty)
              const EmptyState(
                  icon: Icons.insights,
                  title: 'No budgets yet',
                  message: 'Set category budgets to start tracking.')
            else ...[
              AppCard(
                color: AppColors.surface,
                child: Row(
                  children: [
                    Expanded(
                      child: _stat('Total budget', totalLimit, AppColors.accent),
                    ),
                    Container(width: 1, height: 34, color: AppColors.line),
                    Expanded(
                      child: _stat('Spent', totalSpent, AppColors.expense),
                    ),
                    Container(width: 1, height: 34, color: AppColors.line),
                    Expanded(
                      child: _stat(
                        'Remaining',
                        (totalLimit - totalSpent).clamp(0, double.infinity),
                        AppColors.income,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              for (final item in items) _budgetCard(item),
            ],
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, double value, Color color) {
    return Column(
      children: [
        Text(Formatters.inr(value),
            style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
      ],
    );
  }

  Widget _budgetCard(BudgetItem item) {
    final pct = item.limit > 0 ? item.spent / item.limit : 0.0;
    final over = pct >= 1;
    final color = over ? AppColors.danger : pct >= .8 ? AppColors.warning : item.category.color;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(item.category.icon, size: 18, color: item.category.color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(item.category.label,
                      style: const TextStyle(
                          color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
                ),
                Text('${(pct * 100).toStringAsFixed(0)}%',
                    style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w700)),
                const SizedBox(width: 4),
                Text(over ? 'over budget' : 'used',
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
              ],
            ),
            const SizedBox(height: 10),
            ProgressBar(value: pct, color: color, height: 9),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${Formatters.inr(item.spent)} of ${Formatters.inr(item.limit)}',
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                Text('${Formatters.inr((item.limit - item.spent).clamp(0, double.infinity))} left',
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}