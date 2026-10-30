import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../models/models.dart';
import '../../services/finance_repository.dart';

/// Opens the "Add transaction" form. Returns `true` when a record was saved.
Future<bool?> showAddTransactionSheet(
  BuildContext context, {
  FinanceRepository? repository,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) =>
        _AddTransactionSheet(repository: repository ?? getRepository()),
  );
}

class _AddTransactionSheet extends StatefulWidget {
  final FinanceRepository repository;

  const _AddTransactionSheet({required this.repository});

  @override
  State<_AddTransactionSheet> createState() => _AddTransactionSheetState();
}

class _AddTransactionSheetState extends State<_AddTransactionSheet> {
  final _formKey = GlobalKey<FormState>();
  final _merchant = TextEditingController();
  final _amount = TextEditingController();

  TxnType _type = TxnType.expense;
  TxnCategory _category = TxnCategory.others;
  bool _saving = false;
  String? _error;

  List<TxnCategory> get _categories => _type == TxnType.income
      ? const [TxnCategory.income]
      : TxnCategory.values.where((c) => c != TxnCategory.income).toList();

  @override
  void dispose() {
    _merchant.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    // Persist as a stable, sortable id so repeated submissions never collide.
    final id = 'txn-${DateTime.now().microsecondsSinceEpoch}';
    final transaction = Transaction(
      id: id,
      merchant: _merchant.text.trim(),
      category: _category,
      type: _type,
      amount: double.parse(_amount.text.trim()),
      date: DateTime.now(),
      note: 'Added manually',
    );

    try {
      await widget.repository.addTransaction(transaction);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not save: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.line,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Add transaction',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                demoModeEnabled
                    ? 'Demo mode is on - this record stays in this session.'
                    : 'This saves to your PostgreSQL account ($currentUserId).',
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 18),
              SegmentedButton<TxnType>(
                segments: const [
                  ButtonSegment(
                    value: TxnType.expense,
                    label: Text('Expense'),
                    icon: Icon(Icons.arrow_upward, size: 16),
                  ),
                  ButtonSegment(
                    value: TxnType.income,
                    label: Text('Income'),
                    icon: Icon(Icons.arrow_downward, size: 16),
                  ),
                ],
                selected: {_type},
                onSelectionChanged: (selection) {
                  final type = selection.first;
                  setState(() {
                    _type = type;
                    _category = type == TxnType.income
                        ? TxnCategory.income
                        : TxnCategory.others;
                  });
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _merchant,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Merchant / source',
                  hintText: 'e.g. Amazon, Salary',
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Enter a merchant or source';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Amount (₹)',
                  hintText: '0.00',
                ),
                validator: (value) {
                  final parsed = double.tryParse(value?.trim() ?? '');
                  if (parsed == null || parsed <= 0) {
                    return 'Enter an amount greater than zero';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<TxnCategory>(
                key: ValueKey(_type),
                initialValue: _category,
                decoration: const InputDecoration(labelText: 'Category'),
                items: [
                  for (final category in _categories)
                    DropdownMenuItem(
                      value: category,
                      child: Row(
                        children: [
                          Icon(category.icon, size: 17, color: category.color),
                          const SizedBox(width: 8),
                          Text(category.label),
                        ],
                      ),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _category = value);
                },
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: const TextStyle(color: AppColors.danger, fontSize: 12),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text(_saving ? 'Saving…' : 'Save transaction'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
