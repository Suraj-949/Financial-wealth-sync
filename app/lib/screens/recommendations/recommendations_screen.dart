import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../widgets/common.dart';
import '../../models/models.dart';
import '../../services/finance_repository.dart';

class RecommendationsScreen extends StatefulWidget {
  final String? initialCategory;

  const RecommendationsScreen({super.key, this.initialCategory});

  @override
  State<RecommendationsScreen> createState() => _RecommendationsScreenState();
}

class _RecommendationsScreenState extends State<RecommendationsScreen> {
  final repo = getRepository();

  List<Recommendation>? _items;
  String? _error;
  String _filter = 'All';

  static const _categories = [
    'All',
    'Budget',
    'Savings',
    'Debt',
    'Credit Cards',
    'Goals',
    'Payments',
  ];

  @override
  void initState() {
    super.initState();
    _filter = widget.initialCategory ?? 'All';
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await repo.fetchRecommendations();
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

  Color _categoryColor(String c) => switch (c) {
        'Budget' => AppColors.accent,
        'Savings' => AppColors.savings,
        'Debt' => AppColors.danger,
        'Credit Cards' => AppColors.ai,
        'Goals' => AppColors.warning,
        'Payments' => AppColors.income,
        _ => AppColors.textMuted,
      };

  IconData _categoryIcon(String c) => switch (c) {
        'Budget' => Icons.pie_chart_outline,
        'Savings' => Icons.savings_outlined,
        'Debt' => Icons.account_balance,
        'Credit Cards' => Icons.credit_card,
        'Goals' => Icons.flag_outlined,
        'Payments' => Icons.swap_horiz,
        _ => Icons.lightbulb_outline,
      };

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final visible = (items ?? const <Recommendation>[])
        .where((r) => _filter == 'All' || r.category == _filter)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: const [
            Icon(Icons.auto_awesome, size: 18, color: AppColors.ai),
            SizedBox(width: 8),
            Text('AI Recommendations'),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: AppColors.accent,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 20),
          children: [
            SizedBox(
              height: 42,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final c in _categories)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(c, style: const TextStyle(fontSize: 12.5)),
                        selected: _filter == c,
                        onSelected: (_) => setState(() => _filter = c),
                        selectedColor: AppColors.accent.withValues(alpha: .25),
                        backgroundColor: AppColors.surface,
                        side: BorderSide(color: _filter == c ? AppColors.accent : AppColors.line),
                        labelStyle: TextStyle(
                            color: _filter == c ? AppColors.accent : AppColors.textMuted),
                        showCheckmark: false,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (_error != null)
              ErrorState(message: _error!, onRetry: _load)
            else if (items == null)
              Column(children: const [
                Skeleton(height: 100, radius: 14),
                SizedBox(height: 10),
                Skeleton(height: 100, radius: 14),
              ])
            else if (visible.isEmpty)
              const EmptyState(
                  icon: Icons.check_circle_outline,
                  title: 'No recommendations',
                  message: 'Nothing to improve in this category right now.')
            else
              for (final r in visible)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: AppCard(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: _categoryColor(r.category).withValues(alpha: .15),
                                borderRadius: BorderRadius.circular(11),
                              ),
                              alignment: Alignment.center,
                              child: Icon(_categoryIcon(r.category),
                                  color: _categoryColor(r.category), size: 18),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(r.title,
                                  style: const TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w700)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(r.description,
                            style: const TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.4)),
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton.tonal(
                            onPressed: () => ScaffoldMessenger.of(context)
                              ..hideCurrentSnackBar()
                              ..showSnackBar(SnackBar(
                                  content: Text('"${r.action}" will be wired to the backend.'))),
                            style: FilledButton.styleFrom(
                              backgroundColor: _categoryColor(r.category).withValues(alpha: .18),
                              foregroundColor: _categoryColor(r.category),
                              padding: const EdgeInsets.symmetric(horizontal: 14),
                              textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                            ),
                            child: Text(r.action),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}