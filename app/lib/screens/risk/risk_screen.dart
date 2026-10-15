import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../widgets/common.dart';
import '../../models/models.dart';
import '../../services/finance_repository.dart';
import '../xai/xai_screen.dart';

class RiskAssessmentScreen extends StatefulWidget {
  const RiskAssessmentScreen({super.key});

  @override
  State<RiskAssessmentScreen> createState() => _RiskAssessmentScreenState();
}

class _RiskAssessmentScreenState extends State<RiskAssessmentScreen> {
  final repo = getRepository();

  RiskPrediction? _prediction;
  ShapExplanation? _explanation;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        repo.fetchRiskPrediction(),
        repo.fetchRiskExplanation(),
      ]);
      if (!mounted) return;
      setState(() {
        _prediction = results[0] as RiskPrediction;
        _explanation = results[1] as ShapExplanation;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Color _levelColor(String level) {
    switch (level.toLowerCase()) {
      case 'low':
        return AppColors.income;
      case 'medium':
        return AppColors.warning;
      case 'high':
      default:
        return AppColors.danger;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: const [
            Icon(Icons.shield_outlined, size: 20, color: AppColors.income),
            SizedBox(width: 8),
            Text('Credit Risk Assessment'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Explain with XAI',
            icon: const Icon(Icons.auto_awesome, color: AppColors.ai),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const XaiScreen()),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: AppColors.accent,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
          children: [
            if (_error != null && _prediction == null)
              ErrorState(message: _error!, onRetry: _load)
            else if (_loading && _prediction == null)
              const Column(
                children: [
                  Skeleton(height: 220, radius: 18),
                  SizedBox(height: 14),
                  Skeleton(height: 90, radius: 14),
                  SizedBox(height: 14),
                  Skeleton(height: 180, radius: 14),
                ],
              )
            else ...[
              _buildScoreHero(_prediction!),
              const SizedBox(height: 16),
              _buildRiskBandsCard(_prediction!),
              const SizedBox(height: 16),
              const SectionHeader(
                title: 'Credit Health Indicators',
                trailing: Pill('Observed Features', color: AppColors.savings, icon: Icons.analytics_outlined),
              ),
              _buildMetricsGrid(),
              const SizedBox(height: 16),
              const SectionHeader(
                title: '6-Month Repayment History',
                trailing: Pill('Clean Record', color: AppColors.income, icon: Icons.check_circle_outline),
              ),
              _buildRepaymentTrack(),
              const SizedBox(height: 16),
              if (_explanation != null && _explanation!.top.isNotEmpty) ...[
                SectionHeader(
                  title: 'Top AI Risk Drivers (SHAP)',
                  trailing: Pill('Gradient Boosting', color: AppColors.ai, icon: Icons.auto_awesome),
                  action: 'View all →',
                  onAction: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const XaiScreen()),
                  ),
                ),
                _buildShapHighlights(_explanation!),
                const SizedBox(height: 16),
              ],
              _buildActionCard(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildScoreHero(RiskPrediction pred) {
    final color = _levelColor(pred.riskLevel);
    final scoreNormalized = (pred.riskScore / 100.0).clamp(0.0, 1.0);

    return AppCard(
      padding: const EdgeInsets.all(20),
      color: AppColors.surface,
      border: Border.all(color: color.withValues(alpha: 0.45)),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.security, size: 18, color: color),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'AI Default Risk Score',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Gradient Boosting ML Model',
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Pill(
                '${pred.riskLevel.toUpperCase()} RISK',
                color: color,
                filled: true,
              ),
            ],
          ),
          const SizedBox(height: 22),
          SizedBox(
            width: 140,
            height: 140,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CircularProgressIndicator(
                  value: scoreNormalized,
                  strokeWidth: 12,
                  strokeCap: StrokeCap.round,
                  backgroundColor: AppColors.surfaceAlt,
                  valueColor: AlwaysStoppedAnimation(color),
                ),
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        pred.riskScore.toStringAsFixed(1),
                        style: TextStyle(
                          color: color,
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const Text(
                        'out of 100',
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Column(
                  children: [
                    const Text('Default Probability',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                    const SizedBox(height: 3),
                    Text(
                      '${(pred.defaultProbability * 100).toStringAsFixed(1)}%',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                Container(width: 1, height: 26, color: AppColors.line),
                Column(
                  children: [
                    const Text('Credit Standing',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                    const SizedBox(height: 3),
                    Text(
                      pred.riskLevel == 'Low' ? 'Excellent' : pred.riskLevel,
                      style: TextStyle(
                        color: color,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            pred.note,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 11,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRiskBandsCard(RiskPrediction pred) {
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              Text('Model Risk Bands',
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 13.5, fontWeight: FontWeight.w700)),
              Text('0-100 Scale',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Row(
              children: [
                Expanded(
                  flex: 30,
                  child: Container(
                    height: 10,
                    color: AppColors.income,
                  ),
                ),
                const SizedBox(width: 2),
                Expanded(
                  flex: 30,
                  child: Container(
                    height: 10,
                    color: AppColors.warning,
                  ),
                ),
                const SizedBox(width: 2),
                Expanded(
                  flex: 40,
                  child: Container(
                    height: 10,
                    color: AppColors.danger,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _bandLegend('Low: 0-30', AppColors.income, pred.riskScore <= 30),
              _bandLegend('Medium: 31-60', AppColors.warning, pred.riskScore > 30 && pred.riskScore <= 60),
              _bandLegend('High: 61-100', AppColors.danger, pred.riskScore > 60),
            ],
          ),
        ],
      ),
    );
  }

  Widget _bandLegend(String label, Color color, bool isCurrent) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            color: isCurrent ? AppColors.textPrimary : AppColors.textMuted,
            fontSize: 11,
            fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w500,
          ),
        ),
        if (isCurrent) ...[
          const SizedBox(width: 4),
          const Icon(Icons.arrow_drop_up, size: 14, color: AppColors.accent),
        ],
      ],
    );
  }

  Widget _buildMetricsGrid() {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 1.5,
      children: const [
        _MetricTile(
          icon: Icons.credit_card,
          color: AppColors.savings,
          title: 'Credit Limit',
          value: '₹1,00,000',
          subtitle: 'LIMIT_BAL',
          status: 'Adequate line',
        ),
        _MetricTile(
          icon: Icons.pie_chart_outline,
          color: AppColors.income,
          title: 'Utilization (6m)',
          value: '30.0%',
          subtitle: 'util_mean6',
          status: 'Optimal (<35%)',
        ),
        _MetricTile(
          icon: Icons.check_circle_outline,
          color: AppColors.income,
          title: 'Max Delinquency',
          value: '0 Months',
          subtitle: 'max_delinq_6m',
          status: 'No late payments',
        ),
        _MetricTile(
          icon: Icons.swap_horiz,
          color: AppColors.ai,
          title: 'Repayment Ratio',
          value: '80.0%',
          subtitle: 'repay_ratio_mean6',
          status: 'Strong pay-down',
        ),
      ],
    );
  }

  Widget _buildRepaymentTrack() {
    final months = ['Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep'];
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              Text('Monthly Payment Status (PAY_0 to PAY_6)',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
              Text('All On Time (0)',
                  style: TextStyle(color: AppColors.income, fontSize: 12, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              for (final m in months)
                Column(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: AppColors.income.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.income.withValues(alpha: 0.4)),
                      ),
                      alignment: Alignment.center,
                      child: const Icon(Icons.check, size: 16, color: AppColors.income),
                    ),
                    const SizedBox(height: 6),
                    Text(m, style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(color: AppColors.line, height: 1),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              Text('Latest Bill (BILL_AMT1): ₹5,000',
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 12.5, fontWeight: FontWeight.w600)),
              Text('Latest Paid (PAY_AMT1): ₹2,000',
                  style: TextStyle(color: AppColors.income, fontSize: 12.5, fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildShapHighlights(ShapExplanation expl) {
    final topItems = expl.top.take(3).toList();
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          for (final item in topItems)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: item.shap <= 0 ? AppColors.income : AppColors.danger,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item.rawInputReference.isNotEmpty ? item.rawInputReference : item.transformedFeature,
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text(
                    item.shap <= 0 ? 'Reduces Risk (${item.shap.toStringAsFixed(3)})' : 'Adds Risk (+${item.shap.toStringAsFixed(3)})',
                    style: TextStyle(
                      color: item.shap <= 0 ? AppColors.income : AppColors.danger,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildActionCard() {
    return AppCard(
      padding: const EdgeInsets.all(18),
      color: AppColors.surface,
      border: Border.all(color: AppColors.ai.withValues(alpha: 0.35)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.lightbulb_outline, size: 18, color: AppColors.warning),
              SizedBox(width: 8),
              Text('AI Risk Protection Advice',
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 14.5, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            '• Maintain card utilization below 30% to retain the Low Risk score.\n'
            '• Keep automated payments active to guarantee 0 delinquency.\n'
            '• Your consistent repayment ratio of 80% protects you against credit limit cuts.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 12.5, height: 1.5),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.ai,
                side: const BorderSide(color: AppColors.ai),
                padding: const EdgeInsets.symmetric(vertical: 11),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const XaiScreen()),
              ),
              icon: const Icon(Icons.insights, size: 16),
              label: const Text('Open Detailed SHAP Explanation'),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String value;
  final String subtitle;
  final String status;

  const _MetricTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.value,
    required this.subtitle,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            status,
            style: TextStyle(color: color, fontSize: 10.5, fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
