import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../models/models.dart';
import '../../services/finance_repository.dart';

class TransactionsTab extends StatefulWidget {
  const TransactionsTab({super.key});

  @override
  State<TransactionsTab> createState() => _TransactionsTabState();
}

class _TransactionsTabState extends State<TransactionsTab> {
  final repo = getRepository();

  List<Transaction>? _items;
  String? _error;
  String _filter = 'All';

  static const _filters = ['All', 'Income', 'Expense'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await repo.fetchTransactions();
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

  List<Transaction> get _visible {
    final items = _items ?? [];
    return switch (_filter) {
      'Income' => items.where((t) => t.isIncome).toList(),
      'Expense' => items.where((t) => !t.isIncome).toList(),
      _ => items,
    };
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
            child: Text('Transactions',
                style: const TextStyle(
                    color: AppColors.textPrimary, fontSize: 21, fontWeight: FontWeight.w800)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
            child: Row(
              children: [
                for (final f in _filters)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(f, style: const TextStyle(fontSize: 12.5)),
                      selected: _filter == f,
                      onSelected: (_) => setState(() => _filter = f),
                      selectedColor: AppColors.accent.withValues(alpha: .25),
                      backgroundColor: AppColors.surface,
                      side: BorderSide(
                          color: _filter == f ? AppColors.accent : AppColors.line),
                      labelStyle: TextStyle(
                          color: _filter == f ? AppColors.accent : AppColors.textMuted),
                      showCheckmark: false,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              color: AppColors.accent,
              child: _body(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    if (_error != null) {
      return ListView(children: [
        ErrorState(message: _error!, onRetry: _load),
      ]);
    }
    final items = _items;
    if (items == null) {
      return ListView(
        padding: const EdgeInsets.all(18),
        children: const [
          Skeleton(height: 60),
          SizedBox(height: 10),
          Skeleton(height: 60),
          SizedBox(height: 10),
          Skeleton(height: 60),
        ],
      );
    }
    final visible = _visible;
    if (visible.isEmpty) {
      return ListView(children: const [
        EmptyState(
          icon: Icons.receipt_long,
          title: 'No transactions',
          message: 'Nothing here for the selected filter yet.',
        ),
      ]);
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 20),
      itemCount: visible.length,
      itemBuilder: (_, i) => _txnRow(visible[i]),
    );
  }

  Widget _txnRow(Transaction t) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: t.category.color.withValues(alpha: .16),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Icon(t.category.icon, color: t.category.color, size: 19),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.merchant,
                      style: const TextStyle(
                          color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    '${t.category.label} · ${Formatters.dayLabel(t.date)}${t.note != null ? ' · ${t.note}' : ''}',
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
            Text(
              Formatters.signedMoney(t.amount),
              style: TextStyle(
                color: t.isIncome ? AppColors.income : AppColors.textPrimary,
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}