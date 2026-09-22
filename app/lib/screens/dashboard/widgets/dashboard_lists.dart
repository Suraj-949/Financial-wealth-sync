import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../widgets/common.dart';
import '../../../widgets/transaction_card.dart';
import '../../../utils/formatters.dart';
import '../../../models/models.dart';

class AiInsightsList extends StatelessWidget {
  final List<AiInsight> insights;
  final VoidCallback onTap;

  const AiInsightsList({super.key, required this.insights, required this.onTap});

  Color _toneColor(InsightTone t) => switch (t) {
        InsightTone.highImpact => AppColors.danger,
        InsightTone.positive => AppColors.income,
        InsightTone.warning => AppColors.warning,
      };

  String _toneLabel(InsightTone t) => switch (t) {
        InsightTone.highImpact => 'High Impact',
        InsightTone.positive => 'Positive',
        InsightTone.warning => 'Watch',
      };

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final ins in insights)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: AppCard(
              padding: const EdgeInsets.all(14),
              onTap: onTap,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: _toneColor(ins.tone).withValues(alpha: .14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: Text(ins.icon, style: const TextStyle(fontSize: 18)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(ins.text,
                            style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text(ins.action,
                            style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Pill(_toneLabel(ins.tone),
                      color: _toneColor(ins.tone).withValues(alpha: .8),
                      filled: ins.tone == InsightTone.highImpact),
                ],
              ),
            ),
          ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: onTap,
            child: const Text('View all insights →',
                style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }
}

class PaymentSuggestionCard extends StatelessWidget {
  final PaymentSuggestion suggestion;
  final VoidCallback onViewAll;

  const PaymentSuggestionCard({super.key, required this.suggestion, required this.onViewAll});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      color: AppColors.surface,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.storefront, color: AppColors.accent, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "You're about to spend ${Formatters.inr(suggestion.amount)} at ${suggestion.merchant}",
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final offer in suggestion.offers) _OfferRow(offer: offer),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: onViewAll,
              child: const Text('View all offers →',
                  style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}

class _OfferRow extends StatelessWidget {
  final PaymentOffer offer;

  const _OfferRow({required this.offer});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: offer.recommended ? AppColors.income.withValues(alpha: .08) : AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: offer.recommended
            ? Border.all(color: AppColors.income.withValues(alpha: .7))
            : Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          Text(offer.typeIcon, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(offer.name,
                          style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700),
                          overflow: TextOverflow.ellipsis),
                    ),
                    if (offer.recommended) ...[
                      const SizedBox(width: 6),
                      const Pill('✓ Recommended', color: AppColors.income, filled: true),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(offer.benefit, style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(Formatters.inr(offer.savings),
              style: TextStyle(
                  color: offer.recommended ? AppColors.income : AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class CopilotCard extends StatelessWidget {
  final VoidCallback onTap;

  const CopilotCard({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.ai.withValues(alpha: .22),
              AppColors.accent.withValues(alpha: .14),
            ],
            stops: const [0, 1],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.ai.withValues(alpha: .5)),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: AppColors.ai.withValues(alpha: .25),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.smart_toy_outlined, color: AppColors.ai, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Text('🤖 AI Financial Copilot',
                        style: TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w800)),
                    const SizedBox(width: 6),
                    TagBadge.beta(),
                  ]),
                  const SizedBox(height: 4),
                  const Text('Ask me anything about your finances.',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                ],
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.arrow_forward_ios, size: 16, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}

class AccountsBand extends StatelessWidget {
  final List<Account> accounts;
  final ValueChanged<Account> onTap;

  const AccountsBand({super.key, required this.accounts, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 96,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final account in accounts)
            InkWell(
              onTap: () => onTap(account),
              borderRadius: BorderRadius.circular(14),
              child: Container(
                width: 220,
                margin: const EdgeInsets.only(right: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.line),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: account.color.withValues(alpha: .15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: Icon(account.icon, color: account.color, size: 18),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(account.bank,
                              style: const TextStyle(
                                  color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 2),
                          Text(account.subLabel,
                              style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
                          const SizedBox(height: 2),
                          Text(Formatters.inr(account.balance),
                              style: const TextStyle(
                                  color: AppColors.textPrimary, fontSize: 13.5, fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class RecentTransactionsList extends StatelessWidget {
  final List<Transaction> transactions;
  final VoidCallback onViewAll;

  const RecentTransactionsList({super.key, required this.transactions, required this.onViewAll});

  @override
  Widget build(BuildContext context) {
    if (transactions.isEmpty) {
      return const EmptyState(
        icon: Icons.receipt_long,
        title: 'No transactions',
        message: 'New transactions will appear here.',
      );
    }
    return AppCard(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
      child: Column(
        children: [
          for (final t in transactions)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              child: TransactionTile(transaction: t, onTap: onViewAll),
            ),
        ],
      ),
    );
  }
}