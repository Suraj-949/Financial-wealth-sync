import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../widgets/common.dart';
import '../../models/models.dart';
import '../../services/finance_repository.dart';

class XaiScreen extends StatefulWidget {
  const XaiScreen({super.key});

  @override
  State<XaiScreen> createState() => _XaiScreenState();
}

class _XaiScreenState extends State<XaiScreen> {
  final repo = getRepository();

  FinancialSummary? _summary;
  List<ShapFactor>? _factors;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Dashboard shell paints from the mock repository; SHAP drivers upgrade
  /// best-effort from the live wellness model (`POST /explain/wellness`).
  Future<void> _load() async {
    try {
      final data = await repo.fetchDashboard();
      List<ShapFactor> factors;
      try {
        factors = await getApiRepository().fetchXaiFactors();
      } catch (_) {
        factors = await repo.fetchXaiFactors();
      }
      if (!mounted) return;
      setState(() {
        _summary = data.summary;
        _factors = factors;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary;
    final factors = _factors;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: const [
            Icon(Icons.insights, size: 18, color: AppColors.ai),
            SizedBox(width: 8),
            Text('Why this score?'),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: AppColors.accent,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 6, 18, 24),
          children: [
            if (_error != null)
              ErrorState(message: _error!, onRetry: _load)
            else if (summary == null || factors == null)
              const Column(children: [
                Skeleton(height: 180, radius: 16),
                SizedBox(height: 12),
                Skeleton(height: 60, radius: 12),
                SizedBox(height: 12),
                Skeleton(height: 60, radius: 12),
              ])
            else ...[
              _scoreHeader(summary),
              const SizedBox(height: 14),
              const _ExplainNote(),
              const SizedBox(height: 14),
              SectionHeader(
                title: 'What shaped your score',
                trailing: Pill('SHAP values', color: AppColors.ai, icon: Icons.auto_awesome),
              ),
              for (final f in factors) _factorBar(f),
              const SizedBox(height: 14),
              const _PredictVsExplainCard(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _scoreHeader(FinancialSummary s) {
    final color = s.wellnessScore >= 75
        ? AppColors.income
        : s.wellnessScore >= 50
            ? AppColors.warning
            : AppColors.danger;
    return AppCard(
      color: AppColors.surface,
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          SizedBox(
            width: 76,
            height: 76,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CircularProgressIndicator(
                  value: s.wellnessScore / 100,
                  strokeWidth: 8,
                  strokeCap: StrokeCap.round,
                  backgroundColor: AppColors.surfaceAlt,
                  valueColor: AlwaysStoppedAnimation(color),
                ),
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${s.wellnessScore}',
                          style: TextStyle(
                              color: color, fontSize: 20, fontWeight: FontWeight.w800)),
                      const Text('/ 100',
                          style: TextStyle(color: AppColors.textMuted, fontSize: 10)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.wellnessLevel,
                    style: const TextStyle(
                        color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(s.wellnessDelta >= 0 ? Icons.arrow_upward : Icons.arrow_downward,
                        size: 14, color: s.wellnessDelta >= 0 ? AppColors.income : AppColors.danger),
                    const SizedBox(width: 2),
                    Text('${s.wellnessDelta.abs()} vs last month (was ${s.wellnessPrev})',
                        style: TextStyle(
                            color: s.wellnessDelta >= 0 ? AppColors.income : AppColors.danger,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 6),
                const Text('Model: Gradient Boosting · Target: wellness label from your data',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _factorBar(ShapFactor f) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(f.label,
                      style: const TextStyle(
                          color: AppColors.textPrimary, fontSize: 13.5, fontWeight: FontWeight.w600)),
                ),
                Pill(f.positive ? '+ Impact' : '- Impact',
                    color: f.positive ? AppColors.income : AppColors.danger,
                    filled: !f.positive),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: f.magnitude.clamp(0.02, 1.0),
                minHeight: 7,
                backgroundColor: AppColors.surfaceAlt,
                valueColor: AlwaysStoppedAnimation(
                    f.positive ? AppColors.income : AppColors.danger),
              ),
            ),
            const SizedBox(height: 7),
            Text(f.detail,
                style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _ExplainNote extends StatelessWidget {
  const _ExplainNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.line),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.auto_awesome, size: 16, color: AppColors.ai),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Shown are the top factors affecting your financial wellness score, ranked by impact. '
              'A longer bar = stronger influence.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12.5, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _PredictVsExplainCard extends StatelessWidget {
  const _PredictVsExplainCard();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.rule, size: 18, color: AppColors.accent),
              SizedBox(width: 8),
              Text('Prediction vs Explanation',
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'The ML model predicts your score; SHAP explains why. An explanation is not a reason for '
            'correlation with outcomes — insights should always be sanity-checked before acting.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 12.5, height: 1.5),
          ),
        ],
      ),
    );
  }
}