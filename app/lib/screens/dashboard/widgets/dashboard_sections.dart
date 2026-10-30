import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../widgets/common.dart';
import '../../../utils/formatters.dart';
import '../../../models/models.dart';
import '../../../services/finance_repository.dart';
import '../../budget/budget_screen.dart';
import '../../goals/goals_screen.dart';
import 'charts.dart';
import 'dashboard_lists.dart';

void cashStub(BuildContext context, String what) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text('$what is coming soon.')));
}

/// All dashboard sections, fed purely by a DashboardData object.
class DashboardBody extends StatelessWidget {
  final DashboardData data;
  final VoidCallback onViewInsights;
  final VoidCallback onViewOffers;
  final VoidCallback onOpenCopilot;
  final VoidCallback onExplainScore;
  final VoidCallback onViewAllTransactions;
  final VoidCallback onManageAccounts;
  final VoidCallback onAddTransaction;

  const DashboardBody({
    super.key,
    required this.data,
    required this.onViewInsights,
    required this.onViewOffers,
    required this.onOpenCopilot,
    required this.onExplainScore,
    required this.onViewAllTransactions,
    required this.onManageAccounts,
    required this.onAddTransaction,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(title: 'Financial Summary'),
          FinancialSummaryCards(
            summary: data.summary,
            onExplainScore: onExplainScore,
          ),
          Padding(
            padding: const EdgeInsets.only(top: 22, bottom: 10),
            child: _RowHeader(title: 'Quick Actions'),
          ),
          QuickActionsGrid(
            onAdd: onAddTransaction,
            onUpload: () => cashStub(context, 'Upload statement'),
            onBudget: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const BudgetTab()),
            ),
            onGoal: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const GoalsTab()),
            ),
          ),
          const SectionHeader(title: 'Spending Breakdown'),
          AppCard(child: SpendingDonut(categories: data.categories, total: data.summary.expenses)),
          const SectionHeader(
            title: 'Expense Prediction',
            trailing: Pill('AI Prediction',
                color: AppColors.ai, filled: true, icon: Icons.auto_awesome),
          ),
          AppCard(
            color: AppColors.surface,
            border: Border.all(color: AppColors.ai.withValues(alpha: .45)),
            child: PredictionCard(
              data: data,
            ),
          ),
          SectionHeader(
            title: 'AI Insights',
            trailing: Pill('Powered by AI', color: AppColors.ai, icon: Icons.auto_awesome),
            action: 'View all →',
            onAction: onViewInsights,
          ),
          AiInsightsList(insights: data.insights, onTap: onViewInsights),
          SectionHeader(title: 'Smart Payment Suggestion', trailing: TagBadge.newTag()),
          PaymentSuggestionCard(
            suggestion: data.paymentSuggestion,
            onViewAll: onViewOffers,
          ),
          SectionHeader(title: 'AI Financial Copilot', trailing: TagBadge.beta()),
          CopilotCard(onTap: onOpenCopilot),
          SectionHeader(title: 'Accounts', action: 'Manage →', onAction: onManageAccounts),
          AccountsBand(accounts: data.accounts, onTap: (a) => ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text('${a.bank} selected')))),
          SectionHeader(
              title: 'Recent Transactions', action: 'View all →', onAction: onViewAllTransactions),
          RecentTransactionsList(
            transactions: data.recentTransactions,
            onViewAll: onViewAllTransactions,
          ),
        ],
      ),
    );
  }
}

class _RowHeader extends StatelessWidget {
  final String title;
  const _RowHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700),
    );
  }
}

/// Horizontally scrollable summary cards (income / expenses / savings / wellness).
class FinancialSummaryCards extends StatelessWidget {
  final FinancialSummary summary;
  final VoidCallback onExplainScore;

  const FinancialSummaryCards({super.key, required this.summary, required this.onExplainScore});

  @override
  Widget build(BuildContext context) {
    final income = _Metric(
      label: 'Total Income',
      value: summary.income,
      deltaPct: summary.incomeDeltaPct,
      positiveIsGood: true,
      color: AppColors.income,
      showInr: false,
    );
    final expenses = _Metric(
      label: 'Total Expenses',
      value: summary.expenses,
      deltaPct: summary.expensesDeltaPct,
      positiveIsGood: false,
      color: AppColors.expense,
      showInr: false,
    );
    final savings = _Metric(
      label: 'Savings',
      value: summary.savings,
      deltaPct: summary.savingsDeltaPct,
      positiveIsGood: true,
      color: AppColors.savings,
      showInr: false,
    );

    return SizedBox(
      height: 168,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _MetricCard(metric: income),
          _MetricCard(metric: expenses),
          _MetricCard(metric: savings),
          _WellnessCard(summary: summary, onTap: onExplainScore),
        ],
      ),
    );
  }
}

class _Metric {
  final String label;
  final double value;
  final double deltaPct;
  final bool positiveIsGood;
  final Color color;
  final bool showInr;

  const _Metric({
    required this.label,
    required this.value,
    required this.deltaPct,
    required this.positiveIsGood,
    required this.color,
    required this.showInr,
  });
}

class _MetricCard extends StatelessWidget {
  final _Metric metric;

  const _MetricCard({required this.metric});

  @override
  Widget build(BuildContext context) {
    final good = metric.positiveIsGood
        ? metric.deltaPct >= 0
        : metric.deltaPct <= 0;
    final deltaColor = good ? AppColors.income : AppColors.danger;

    return Container(
      width: 168,
      margin: const EdgeInsets.only(right: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: metric.color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(metric.label,
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          Text(
            Formatters.inr(metric.value),
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 21, fontWeight: FontWeight.w800),
          ),
          Row(
            children: [
              Icon(metric.deltaPct >= 0 ? Icons.arrow_upward : Icons.arrow_downward,
                  size: 14, color: deltaColor),
              const SizedBox(width: 2),
              Expanded(
                child: Text('${metric.deltaPct.abs()}% vs last month',
                    style: TextStyle(color: deltaColor, fontSize: 11.5, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WellnessCard extends StatelessWidget {
  final FinancialSummary summary;
  final VoidCallback onTap;

  const _WellnessCard({required this.summary, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final score = summary.wellnessScore;
    final color = score >= 75
        ? AppColors.income
        : score >= 50
            ? AppColors.warning
            : AppColors.danger;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 168,
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.surface,
              color.withValues(alpha: .10),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: .45)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: const [
                Icon(Icons.auto_awesome, size: 14, color: AppColors.ai),
                SizedBox(width: 6),
                Expanded(
                  child: Text('Financial Wellness Score',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$score / 100',
                    style: TextStyle(color: color, fontSize: 21, fontWeight: FontWeight.w800)),
                Text(summary.wellnessLevel,
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 13)),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ProgressBar(value: score / 100, color: color, height: 6),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(summary.wellnessDelta >= 0 ? Icons.arrow_upward : Icons.arrow_downward,
                        size: 14, color: summary.wellnessDelta >= 0 ? AppColors.income : AppColors.danger),
                    const SizedBox(width: 2),
                    Flexible(
                      child: Text(
                        '${summary.wellnessDelta.abs()} points vs last month',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ),
                    const Spacer(),
                    const Text('Why? →',
                        style: TextStyle(color: AppColors.accent, fontSize: 11, fontWeight: FontWeight.w700)),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 2x2 grid of quick actions.
class QuickActionsGrid extends StatelessWidget {
  final VoidCallback onAdd;
  final VoidCallback onUpload;
  final VoidCallback onBudget;
  final VoidCallback onGoal;

  const QuickActionsGrid({
    super.key,
    required this.onAdd,
    required this.onUpload,
    required this.onBudget,
    required this.onGoal,
  });

  @override
  Widget build(BuildContext context) {
    final actions = [
      _QuickAction(icon: Icons.add_circle_outline, color: AppColors.income, title: '+ Add Transaction', onTap: onAdd),
      _QuickAction(icon: Icons.upload_file, color: AppColors.savings, title: '↑ Upload Statement', onTap: onUpload),
      _QuickAction(icon: Icons.pie_chart_outline, color: AppColors.accent, title: 'Set Budget', onTap: onBudget),
      _QuickAction(icon: Icons.flag_outlined, color: AppColors.ai, title: 'Create Goal', onTap: onGoal),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 2.6,
      children: actions.map((a) => a).toList(),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.color,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.line),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(title, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

/// Expense prediction card: real ML forecast when the backend is reachable,
/// otherwise the mock trend (area chart, delta and confidence).
class PredictionCard extends StatelessWidget {
  final DashboardData data;

  const PredictionCard({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final ml = data.mlPrediction;
    if (ml == null &&
        data.isLive &&
        data.historicExpense.every((value) => value <= 0)) {
      return const EmptyState(
        icon: Icons.auto_graph,
        title: 'No projection yet',
        message: 'Add transactions to build your expense trend.',
      );
    }
    return ml != null ? _modelForecast(ml) : _mockTrend();
  }

  /// Real output of `POST /api/ml/spending/predict`.
  ///
  /// The model forecasts a **quarterly total in USD**, so it is rendered with
  /// its own symbol and horizon. It is deliberately not plotted on the monthly
  /// INR history — a quarterly USD figure cannot share that axis.
  Widget _modelForecast(SpendingPrediction ml) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: const [
            Expanded(
              child: Text('Model Forecast · Next Quarter',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
            ),
            Icon(Icons.smart_toy_outlined, size: 15, color: AppColors.ai),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Flexible(
              child: Text(Formatters.money(ml.predictedSpending, ml.currency),
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 27,
                      fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Text(ml.currency,
                  style: const TextStyle(
                      color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(ml.note,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 11, height: 1.4)),
        const SizedBox(height: 14),
        const Text('Monthly expense trend (₹) · forecast not plotted',
            style: TextStyle(
                color: AppColors.textMuted, fontSize: 11, fontStyle: FontStyle.italic)),
        const SizedBox(height: 6),
        ExpensePredictionChart(
          historic: data.historicExpense,
          predicted: null,
          labels: data.monthLabels,
        ),
      ],
    );
  }

  /// Projection from the user's own history (live mode) or the mock trend.
  Widget _mockTrend() {
    final up = data.predictedDeltaPct >= 0;
    final live = data.isLive;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                live
                    ? 'Projected Expenses · Next Month'
                    : 'Predicted Expenses · Next Month',
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 13,
                ),
              ),
            ),
            Text(
              live ? 'projection' : Formatters.pct(data.predictionConfidence * 100),
              style: const TextStyle(
                color: AppColors.ai,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              live ? 'from history' : 'confidence',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(Formatters.inr(data.predictedExpense),
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 27, fontWeight: FontWeight.w800)),
            const SizedBox(width: 10),
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Icon(up ? Icons.arrow_upward : Icons.arrow_downward,
                      size: 15, color: up ? AppColors.danger : AppColors.income),
                  const SizedBox(width: 2),
                  Text('${data.predictedDeltaPct.abs().toStringAsFixed(1)}% vs this month',
                      style: TextStyle(
                          color: up ? AppColors.danger : AppColors.income,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          live
              ? 'Projected from your recorded transactions. Add income and expenses to improve it.'
              : 'Dashed purple segment = predicted · confidence shown as mock during UI dev',
          style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
        ),
        const SizedBox(height: 8),
        ExpensePredictionChart(
          historic: data.historicExpense,
          predicted: data.predictedExpense,
          labels: data.monthLabels,
        ),
      ],
    );
  }
}