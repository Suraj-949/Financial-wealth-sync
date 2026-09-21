import 'package:flutter/material.dart';

enum TxnType { income, expense }

enum TxnCategory {
  shopping('Shopping', Icons.shopping_bag, Color(0xFFA78BFA)),
  food('Food & Dining', Icons.restaurant, Color(0xFFFFB84D)),
  bills('Bills & Utilities', Icons.receipt_long, Color(0xFF36B4FF)),
  transport('Transport', Icons.directions_car, Color(0xFFFF9F5A)),
  entertainment('Entertainment', Icons.movie, Color(0xFFFF5D73)),
  others('Others', Icons.more_horiz, Color(0xFF9AA3C7)),
  income('Income', Icons.account_balance_wallet, Color(0xFF2FD06A));

  final String label;
  final IconData icon;
  final Color color;

  const TxnCategory(this.label, this.icon, this.color);
}

class Transaction {
  final String id;
  final String merchant;
  final TxnCategory category;
  final TxnType type;
  final double amount;
  final DateTime date;
  final String? note;

  const Transaction({
    required this.id,
    required this.merchant,
    required this.category,
    required this.type,
    required this.amount,
    required this.date,
    this.note,
  });

  bool get isIncome => type == TxnType.income;
}

class Account {
  final String id;
  final String bank;
  final String subLabel; // masked number or UPI id
  final double balance;
  final IconData icon;
  final Color color;

  const Account({
    required this.id,
    required this.bank,
    required this.subLabel,
    required this.balance,
    required this.icon,
    required this.color,
  });
}

class FinancialSummary {
  final double income;
  final double incomeDeltaPct;
  final double expenses;
  final double expensesDeltaPct;
  final double savings;
  final double savingsDeltaPct;
  final int wellnessScore;
  final String wellnessLevel; // e.g. Moderate
  final int wellnessDelta; // negative => dropped
  final int wellnessPrev;

  const FinancialSummary({
    required this.income,
    required this.incomeDeltaPct,
    required this.expenses,
    required this.expensesDeltaPct,
    required this.savings,
    required this.savingsDeltaPct,
    required this.wellnessScore,
    required this.wellnessLevel,
    required this.wellnessDelta,
    required this.wellnessPrev,
  });
}

class SpendingCategory {
  final TxnCategory category;
  final double amount;
  final double pct;

  const SpendingCategory({required this.category, required this.amount, required this.pct});
}

class BudgetItem {
  final TxnCategory category;
  final double spent;
  final double limit;

  const BudgetItem({required this.category, required this.spent, required this.limit});
}

class Goal {
  final String id;
  final String title;
  final String icon;
  final double saved;
  final double target;
  final String note;

  const Goal({
    required this.id,
    required this.title,
    required this.icon,
    required this.saved,
    required this.target,
    required this.note,
  });
}

class AiInsight {
  final String id;
  final String icon;
  final String text;
  final String action;
  final InsightTone tone;

  const AiInsight({
    required this.id,
    required this.icon,
    required this.text,
    required this.action,
    required this.tone,
  });
}

enum InsightTone { highImpact, positive, warning }

class PaymentOffer {
  final String id;
  final String name;
  final String benefit;
  final double savings;
  final bool recommended;
  final String typeIcon;

  const PaymentOffer({
    required this.id,
    required this.name,
    required this.benefit,
    required this.savings,
    required this.recommended,
    required this.typeIcon,
  });
}

class PaymentSuggestion {
  final String merchant;
  final double amount;
  final List<PaymentOffer> offers;

  const PaymentSuggestion({
    required this.merchant,
    required this.amount,
    required this.offers,
  });
}

class Recommendation {
  final String id;
  final String category; // Budget / Savings / Debt / Credit Cards / Goals / Payments
  final String title;
  final String description;
  final String action;

  const Recommendation({
    required this.id,
    required this.category,
    required this.title,
    required this.description,
    required this.action,
  });
}

class AlertItem {
  final String id;
  final String emoji;
  final String text;
  final String time;
  bool read;

  AlertItem({
    required this.id,
    required this.emoji,
    required this.text,
    required this.time,
    this.read = false,
  });
}

class ShapFactor {
  final String label;
  final double magnitude; // 0..1 bar fill
  final bool positive; // true = helps score
  final String detail;

  const ShapFactor({
    required this.label,
    required this.magnitude,
    required this.positive,
    required this.detail,
  });
}

/// Grounded copilot response — Flutter only renders it; the reply is produced
/// by a backend pipeline (query -> data + ML + XAI + recommendations -> LLM).
class CopilotReply {
  final String text;
  final List<String> bullets;

  const CopilotReply({required this.text, this.bullets = const []});
}

class CopilotMessage {
  final String text;
  final bool fromUser;
  final DateTime time;

  const CopilotMessage({required this.text, required this.fromUser, required this.time});
}