import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wealthsync/models/models.dart';
import 'package:wealthsync/services/finance_repository.dart';

Transaction _txn({
  required String id,
  required double amount,
  required DateTime date,
  required TxnType type,
  TxnCategory category = TxnCategory.others,
}) {
  return Transaction(
    id: id,
    merchant: id,
    category: type == TxnType.income ? TxnCategory.income : category,
    type: type,
    amount: amount,
    date: date,
  );
}

void main() {
  final now = DateTime(2026, 10, 30);

  test('aggregates the signed-in user rows into a live dashboard', () {
    final data = buildDashboardFromRecords(
      now: now,
      transactions: [
        _txn(
          id: 'salary',
          amount: 60000,
          date: DateTime(2026, 10, 1),
          type: TxnType.income,
        ),
        _txn(
          id: 'shopping',
          amount: 10000,
          date: DateTime(2026, 10, 5),
          type: TxnType.expense,
          category: TxnCategory.shopping,
        ),
        _txn(
          id: 'food',
          amount: 5000,
          date: DateTime(2026, 10, 10),
          type: TxnType.expense,
          category: TxnCategory.food,
        ),
        _txn(
          id: 'september-salary',
          amount: 50000,
          date: DateTime(2026, 9, 1),
          type: TxnType.income,
        ),
        _txn(
          id: 'september-bills',
          amount: 12000,
          date: DateTime(2026, 9, 20),
          type: TxnType.expense,
          category: TxnCategory.bills,
        ),
      ],
      accounts: const [
        Account(
          id: 'a1',
          bank: 'HDFC',
          subLabel: '•••• 4321',
          balance: 125000,
          icon: Icons.account_balance,
          color: Color(0xFF36B4FF),
        ),
      ],
      budgets: const [
        BudgetItem(
          category: TxnCategory.shopping,
          spent: 15000,
          limit: 18000,
        ),
      ],
      goals: const [
        Goal(
          id: 'g1',
          title: 'Emergency Fund',
          icon: '🛡',
          saved: 25000,
          target: 50000,
          note: '',
        ),
      ],
    );

    expect(data.isLive, isTrue);
    expect(data.summary.income, 60000);
    expect(data.summary.expenses, 15000);
    expect(data.summary.savings, 45000);
    expect(data.summary.wellnessLevel, isNot('No data yet'));
    expect(data.categories.first.category, TxnCategory.shopping);
    expect(data.categories.first.amount, 10000);
    expect(data.categories.first.pct, closeTo(66.7, 0.05));
    expect(data.historicExpense.length, 6);
    expect(data.historicExpense.last, 15000); // October
    expect(data.historicExpense[4], 12000); // September
    expect(data.monthLabels.length, 7);
    expect(data.monthLabels.last, 'Nov (Proj.)');
    expect(data.predictedExpense, greaterThan(0));
    expect(data.recentTransactions.length, 5);
    expect(data.insights, isNotEmpty);
    expect(data.accounts.single.bank, 'HDFC');
    expect(data.paymentSuggestion.amount, 5000);
  });

  test('an empty account renders zeroes without falling back to sample data',
      () {
    final data = buildDashboardFromRecords(
      now: now,
      transactions: const [],
      accounts: const [],
      budgets: const [],
      goals: const [],
    );

    expect(data.isLive, isTrue);
    expect(data.summary.income, 0);
    expect(data.summary.expenses, 0);
    expect(data.summary.savings, 0);
    expect(data.summary.wellnessLevel, 'No data yet');
    expect(data.categories, isEmpty);
    expect(data.predictedExpense, 0);
    expect(data.recentTransactions, isEmpty);
    expect(data.insights.single.text, contains('No financial activity'));
  });
}
