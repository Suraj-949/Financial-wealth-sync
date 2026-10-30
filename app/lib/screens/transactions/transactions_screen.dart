import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/transaction_card.dart';
import '../../utils/formatters.dart';
import '../../models/models.dart';
import '../../services/finance_repository.dart';
import '../../services/finance_refresh.dart';
import 'add_transaction_sheet.dart';

class TransactionsTab extends StatefulWidget {
  const TransactionsTab({super.key});

  @override
  State<TransactionsTab> createState() => _TransactionsTabState();
}

class _TransactionsTabState extends State<TransactionsTab>
    with FinanceDataListener<TransactionsTab> {
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

  @override
  void onFinanceDataChanged() => _load();

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

  Future<void> _add() async {
    final saved = await showAddTransactionSheet(context, repository: repo);
    if (!mounted || saved != true) return;
    await _load();
  }

  Future<bool> _delete(Transaction transaction) async {
    try {
      await repo.deleteTransaction(transaction.id);
      if (!mounted) return false;
      setState(() => _items?.removeWhere((item) => item.id == transaction.id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Deleted ${transaction.merchant}.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return true;
    } catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not delete: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return false;
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
            padding: const EdgeInsets.fromLTRB(18, 14, 10, 6),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Transactions',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _add,
                  tooltip: 'Add transaction',
                  icon: const Icon(
                    Icons.add_circle_outline,
                    color: AppColors.accent,
                  ),
                ),
              ],
            ),
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
    final note = t.note;
    // SMS-imported rows keep their received time so the ledger matches the
    // message that created them.
    final when = note == 'Added from bank SMS'
        ? '${Formatters.dayLabel(t.date)} · ${Formatters.timeLabel(t.date)}'
        : Formatters.dayLabel(t.date);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: AppCard(
              padding: const EdgeInsets.all(12),
              child: TransactionTile(
                transaction: t,
                iconSize: 19,
                subtitle:
                    '${t.category.label} · $when${note != null ? ' · $note' : ''}',
              ),
            ),
          ),
          IconButton(
            onPressed: () => _confirmDelete(t),
            tooltip: 'Delete transaction',
            icon: const Icon(
              Icons.delete_outline,
              size: 19,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(Transaction transaction) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete transaction?'),
        content: Text(
          '${transaction.merchant} · ${Formatters.inr(transaction.amount)}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _delete(transaction);
  }
}