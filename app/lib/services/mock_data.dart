import 'package:flutter/material.dart';

import '../models/models.dart';

/// Demo data for UI development. Produced by a repository (not by widgets) so
/// rendering code never depends on hardcoded values. Replace `MockFinanceRepository`
/// with the real API implementation once endpoints land (see finance_repository.dart).
class MockData {
  MockData._();

  static final now = DateTime.now();

  static final summary = FinancialSummary(
    income: 60000,
    incomeDeltaPct: 12,
    expenses: 42000,
    expensesDeltaPct: 8,
    savings: 18000,
    savingsDeltaPct: 20,
    wellnessScore: 63,
    wellnessLevel: 'Moderate',
    wellnessDelta: -6,
    wellnessPrev: 69,
  );

  static final categories = [
    SpendingCategory(category: TxnCategory.shopping, amount: 15000, pct: 35.7),
    SpendingCategory(category: TxnCategory.food, amount: 8500, pct: 20.2),
    SpendingCategory(category: TxnCategory.bills, amount: 7000, pct: 16.7),
    SpendingCategory(category: TxnCategory.transport, amount: 4500, pct: 10.7),
    SpendingCategory(category: TxnCategory.entertainment, amount: 3000, pct: 7.1),
    SpendingCategory(category: TxnCategory.others, amount: 4000, pct: 9.6),
  ];

  /// Monthly expense series: Jan..Jun actual + Jul (predicted).
  static const historicExpense = [32000.0, 35500.0, 38000.0, 41000.0, 39500.0, 42300.0];
  static const predictedExpense = 45500.0;
  static const predictionConfidence = 0.82; // mock only; backend provides in production
  static const predictedDeltaPct = 7.5;
  static const monthLabels = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul (Pred.)'];

  static final insights = [
    AiInsight(
      id: 'i1',
      icon: '🛍',
      text: 'Shopping expenses are 18% higher than last month.',
      action: 'Try reducing shopping by ₹3,000 to stay within your budget.',
      tone: InsightTone.highImpact,
    ),
    AiInsight(
      id: 'i2',
      icon: '💳',
      text: 'Your credit card utilization is 72%.',
      action: 'Keeping utilization below your configured target can help manage your finances.',
      tone: InsightTone.highImpact,
    ),
    AiInsight(
      id: 'i3',
      icon: '💰',
      text: 'Your savings increased by 20%.',
      action: "You're on track with your savings goal.",
      tone: InsightTone.positive,
    ),
  ];

  static final paymentSuggestion = PaymentSuggestion(
    merchant: 'Amazon',
    amount: 5000,
    offers: [
      const PaymentOffer(
        id: 'p1',
        name: 'HDFC Credit Card',
        benefit: '10% cashback up to ₹500',
        savings: 500,
        recommended: true,
        typeIcon: '💳',
      ),
      const PaymentOffer(
        id: 'p2',
        name: 'UPI',
        benefit: '5% cashback up to ₹250',
        savings: 250,
        recommended: false,
        typeIcon: '📱',
      ),
      const PaymentOffer(
        id: 'p3',
        name: 'Amazon Pay Wallet',
        benefit: 'Flat ₹100 cashback',
        savings: 100,
        recommended: false,
        typeIcon: '🛒',
      ),
      const PaymentOffer(
        id: 'p4',
        name: 'SBI Credit Card',
        benefit: '5% discount up to ₹300',
        savings: 300,
        recommended: false,
        typeIcon: '💳',
      ),
    ],
  );

  static final budgets = [
    BudgetItem(category: TxnCategory.shopping, spent: 15000, limit: 18000),
    BudgetItem(category: TxnCategory.food, spent: 8500, limit: 10000),
    BudgetItem(category: TxnCategory.bills, spent: 7000, limit: 8000),
    BudgetItem(category: TxnCategory.transport, spent: 4500, limit: 6000),
    BudgetItem(category: TxnCategory.entertainment, spent: 3000, limit: 5000),
  ];

  static final goals = [
    Goal(
      id: 'g1',
      title: 'Emergency Fund',
      icon: '🛡',
      saved: 35000,
      target: 50000,
      note: '₹15,000 away from your goal',
    ),
    Goal(
      id: 'g2',
      title: 'Vacation Fund',
      icon: '✈️',
      saved: 12500,
      target: 30000,
      note: 'Keep saving ₹2,000/month to reach it by December',
    ),
    Goal(
      id: 'g3',
      title: 'New Phone',
      icon: '📱',
      saved: 20000,
      target: 45000,
      note: 'You are 56% of the way there',
    ),
  ];

  static final recommendations = [
    const Recommendation(
      id: 'r1',
      category: 'Savings',
      title: 'Increase Monthly Savings',
      description: 'Try saving at least ₹2,000 more this month.',
      action: 'View suggestion',
    ),
    const Recommendation(
      id: 'r2',
      category: 'Credit Cards',
      title: 'Reduce Credit Utilization',
      description: 'Your current utilization is 72%.',
      action: 'View suggestion',
    ),
    const Recommendation(
      id: 'r3',
      category: 'Goals',
      title: 'Emergency Fund',
      description: 'You are ₹15,000 away from your emergency fund goal.',
      action: 'View goal',
    ),
    const Recommendation(
      id: 'r4',
      category: 'Budget',
      title: 'Trim Shopping Spend',
      description: 'Shopping is 18% above last month; cap it at ₹12,000 this month.',
      action: 'View suggestion',
    ),
    const Recommendation(
      id: 'r5',
      category: 'Payments',
      title: 'Use HDFC Card on Amazon',
      description: 'You can save up to ₹500 on your next Amazon payment via HDFC.',
      action: 'View offers',
    ),
    const Recommendation(
      id: 'r6',
      category: 'Debt',
      title: 'Pay Down Credit Card Balance',
      description: 'Reduce utilization below 30% to improve your wellness score.',
      action: 'View suggestion',
    ),
    const Recommendation(
      id: 'r7',
      category: 'Goals',
      title: 'Vacation Fund',
      description: 'Auto-save ₹2,000/month to reach ₹30,000 by December.',
      action: 'View goal',
    ),
    const Recommendation(
      id: 'r8',
      category: 'Budget',
      title: 'Set Entertainment Cap',
      description: 'Entertainment is at 60% of budget with 10 days left.',
      action: 'View suggestion',
    ),
  ];

  static final accounts = [
    const Account(
      id: 'a1',
      bank: 'HDFC Bank',
      subLabel: '•••• 4321',
      balance: 125430,
      icon: Icons.account_balance,
      color: Color(0xFF36B4FF),
    ),
    const Account(
      id: 'a2',
      bank: 'SBI Credit Card',
      subLabel: '•••• 5678',
      balance: -78340,
      icon: Icons.credit_card,
      color: Color(0xFFFF5D73),
    ),
    const Account(
      id: 'a3',
      bank: 'UPI Wallet',
      subLabel: 'suraj@upi',
      balance: 12450,
      icon: Icons.qr_code,
      color: Color(0xFF2FD06A),
    ),
  ];

  static final alerts = [
    AlertItem(id: 'al1', emoji: '⚠️', text: 'Shopping budget reached 85%', time: '2h ago'),
    AlertItem(id: 'al2', emoji: '🔔', text: 'EMI due in 3 days', time: '1d ago'),
    AlertItem(id: 'al3', emoji: '⚠️', text: 'Unusual spending detected', time: '2d ago'),
    AlertItem(id: 'al4', emoji: '🎯', text: "You're close to your savings goal", time: '3d ago'),
  ];

  static final shapFactors = [
    const ShapFactor(
      label: 'Credit Card Utilization',
      magnitude: .70,
      positive: false,
      detail: 'Utilization rose from 55% to 72%, pulling the score down the most.',
    ),
    const ShapFactor(
      label: 'Monthly Expenses',
      magnitude: .58,
      positive: false,
      detail: 'Expenses are 8% higher; discretionary shopping is up 18%.',
    ),
    const ShapFactor(
      label: 'Savings Rate',
      magnitude: .46,
      positive: true,
      detail: 'Savings rate improved to 30% of income — a positive contributor.',
    ),
    const ShapFactor(
      label: 'Income Stability',
      magnitude: .35,
      positive: true,
      detail: 'Income was consistent with no missing credits in the window.',
    ),
  ];

  static List<Transaction> transactions() {
    DateTime d(int back) => now.subtract(Duration(days: back));
    return [
      Transaction(id: 't1', merchant: 'Amazon India', category: TxnCategory.shopping, type: TxnType.expense, amount: 2499, date: d(1), note: 'Order #33219'),
      Transaction(id: 't2', merchant: 'Zomato', category: TxnCategory.food, type: TxnType.expense, amount: 849, date: d(1)),
      Transaction(id: 't3', merchant: 'Salary Credit', category: TxnCategory.income, type: TxnType.income, amount: 60000, date: d(2)),
      Transaction(id: 't4', merchant: 'Uber', category: TxnCategory.transport, type: TxnType.expense, amount: 320, date: d(2)),
      Transaction(id: 't5', merchant: 'Electricity Bill', category: TxnCategory.bills, type: TxnType.expense, amount: 1840, date: d(3)),
      Transaction(id: 't6', merchant: 'PVR Cinemas', category: TxnCategory.entertainment, type: TxnType.expense, amount: 600, date: d(4)),
      Transaction(id: 't7', merchant: 'Reliance Digital', category: TxnCategory.shopping, type: TxnType.expense, amount: 5499, date: d(5)),
      Transaction(id: 't8', merchant: 'Wifi Recharge', category: TxnCategory.bills, type: TxnType.expense, amount: 799, date: d(6)),
      Transaction(id: 't9', merchant: 'Freelance Payment', category: TxnCategory.income, type: TxnType.income, amount: 8500, date: d(7)),
    ];
  }

  static const copilotSuggested = [
    'Why did my score drop?',
    'How can I save more?',
    'Which payment method is best?',
    'Can I afford a new phone?',
  ];
}