import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../widgets/common.dart';
import '../../utils/formatters.dart';
import '../../models/models.dart';
import '../../services/finance_repository.dart';
import '../../services/finance_refresh.dart';
import '../dashboard/widgets/charts.dart';

class GoalsTab extends StatefulWidget {
  const GoalsTab({super.key});

  @override
  State<GoalsTab> createState() => _GoalsTabState();
}

class _GoalsTabState extends State<GoalsTab>
    with FinanceDataListener<GoalsTab> {
  final repo = getRepository();

  List<Goal>? _items;
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
      final items = await repo.fetchGoals();
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
                Text('Goals',
                    style: const TextStyle(
                        color: AppColors.textPrimary, fontSize: 21, fontWeight: FontWeight.w800)),
                const Spacer(),
                IconButton(
                  onPressed: () => ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(const SnackBar(content: Text('Create a new goal is coming soon.'))),
                  icon: const Icon(Icons.add_circle_outline, color: AppColors.accent),
                ),
              ],
            ),
            if (_error != null)
              ErrorState(message: _error!, onRetry: _load)
            else if (items == null)
              Column(children: const [
                Skeleton(height: 120, radius: 16),
                SizedBox(height: 12),
                Skeleton(height: 120, radius: 16),
              ])
            else if (items.isEmpty)
              const EmptyState(
                  icon: Icons.flag_outlined,
                  title: 'No goals yet',
                  message: 'Set a savings target to start tracking progress.')
            else
              for (final goal in items) _goalCard(goal),
          ],
        ),
      ),
    );
  }

  Widget _goalCard(Goal goal) {
    final pct = goal.target > 0 ? goal.saved / goal.target : 0.0;
    final color = pct >= 1 ? AppColors.income : AppColors.accent;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(goal.icon, style: const TextStyle(fontSize: 22)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(goal.title,
                          style: const TextStyle(
                              color: AppColors.textPrimary, fontSize: 14.5, fontWeight: FontWeight.w700)),
                      Text(goal.note,
                          style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                    ],
                  ),
                ),
                Text('${(pct * 100).toStringAsFixed(0)}%',
                    style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w800)),
              ],
            ),
            const SizedBox(height: 12),
            ProgressBar(value: pct, color: color, height: 9),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(Formatters.inr(goal.saved),
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                Text('Target: ${Formatters.inr(goal.target)}',
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}