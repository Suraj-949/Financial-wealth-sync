import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../models/models.dart';
import '../utils/formatters.dart';

/// Single transaction row, shared by the dashboard "Recent" list and the
/// full Transactions screen. Renders the row content only; callers wrap it
/// in the surrounding card / padding they want.
class TransactionTile extends StatelessWidget {
  final Transaction transaction;
  final String? subtitle;
  final VoidCallback? onTap;
  final double iconSize;

  const TransactionTile({
    super.key,
    required this.transaction,
    this.subtitle,
    this.onTap,
    this.iconSize = 18,
  });

  String _defaultSubtitle() =>
      '${transaction.category.label} · ${Formatters.dayLabel(transaction.date)}';

  @override
  Widget build(BuildContext context) {
    final t = transaction;
    final row = Row(
      children: [
        Container(
          width: iconSize + 20,
          height: iconSize + 20,
          decoration: BoxDecoration(
            color: t.category.color.withValues(alpha: .16),
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: Icon(t.category.icon, color: t.category.color, size: iconSize),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t.merchant,
                  style:
                      const TextStyle(color: AppColors.textPrimary, fontSize: 13.5, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(
                subtitle ?? _defaultSubtitle(),
                style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          Formatters.signedMoney(t.amount),
          style: TextStyle(
            color: t.isIncome ? AppColors.income : AppColors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );

    if (onTap == null) return row;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: row,
    );
  }
}