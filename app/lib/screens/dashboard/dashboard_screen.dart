import 'package:flutter/material.dart';

import '../../app/constants.dart';
import '../../app/theme.dart';
import '../../widgets/common.dart';
import '../../utils/formatters.dart';
import '../../services/finance_repository.dart';
import '../../models/models.dart';
import '../accounts/accounts_screen.dart';
import '../alerts/alerts_screen.dart';
import '../copilot/copilot_chat_screen.dart';
import '../profile/profile_screen.dart';
import '../recommendations/recommendations_screen.dart';
import '../transactions/transactions_screen.dart';
import '../xai/xai_screen.dart';
import 'widgets/dashboard_sections.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final repo = getRepository();

  DashboardData? _data;
  String? _error;
  String _range = AppConstants.ranges.first;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await repo.fetchDashboard();
      if (!mounted) return;
      setState(() {
        _data = data;
        _error = null;
      });
      // Best effort: swap the mock forecast for the real model output. The
      // dashboard paints immediately with mock data, then upgrades.
      _loadForecast();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  /// Calls `POST /api/ml/spending/predict` and merges the result in.
  ///
  /// Deliberately silent on failure: if the backend is down the mock forecast
  /// already on screen is kept rather than turning the whole tab into an error.
  Future<void> _loadForecast() async {
    SpendingPrediction prediction;
    try {
      prediction = await repo.fetchSpendingPrediction();
    } catch (_) {
      return; // Backend unreachable -> keep the mock forecast.
    }
    if (!mounted || _data == null) return;
    setState(() => _data = _data!.copyWith(mlPrediction: prediction));
  }

  Future<void> _pickRange() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Select period',
                    style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ),
            for (final r in AppConstants.ranges)
              ListTile(
                title: Text(r, style: const TextStyle(fontSize: 14)),
                trailing: r == _range ? const Icon(Icons.check, color: AppColors.accent, size: 20) : null,
                onTap: () => Navigator.pop(ctx, r),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked != null && mounted) {
      setState(() => _range = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.bg,
      child: RefreshIndicator(
        onRefresh: _load,
        color: AppColors.accent,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: _GreetingHeader(onAlerts: _openAlerts, onProfile: _openProfile)),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 2, 18, 4),
                child: _DateSelector(range: _range, onTap: _pickRange),
              ),
            ),
            if (_error != null && _data == null)
              SliverToBoxAdapter(child: ErrorState(message: _error!, onRetry: _load))
            else if (_data == null)
              const SliverToBoxAdapter(child: DashboardSkeleton())
            else
              ..._dataSlivers(_data!),
          ],
        ),
      ),
    );
  }

  List<Widget> _dataSlivers(DashboardData d) {
    final body = DashboardBody(
      data: d,
      onViewInsights: () => _push(const RecommendationsScreen()),
      onViewOffers: () => _push(const RecommendationsScreen(initialCategory: 'Payments')),
      onOpenCopilot: () => _push(const CopilotChatScreen()),
      onExplainScore: () => _push(const XaiScreen()),
      onViewAllTransactions: () => _push(const TransactionsTab()),
      onManageAccounts: () => _push(const AccountsScreen()),
    );
    return [SliverToBoxAdapter(child: body)];
  }

  void _openAlerts() => _push(const AlertsScreen());
  void _openProfile() => _push(const ProfileScreen());

  void _push(Widget page) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => page),
    );
  }
}

class _GreetingHeader extends StatelessWidget {
  final VoidCallback onAlerts;
  final VoidCallback onProfile;

  const _GreetingHeader({required this.onAlerts, required this.onProfile});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 12, 12, 0),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${Formatters.greeting()}, ${AppConstants.userName} 👋',
                    style: const TextStyle(
                        color: AppColors.textPrimary, fontSize: 21, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: onAlerts,
              tooltip: 'Alerts',
              icon: Stack(
                clipBehavior: Clip.none,
                children: [
                  const Icon(Icons.notifications_none, color: AppColors.textPrimary, size: 24),
                  Positioned(
                    top: -2,
                    right: -2,
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: AppColors.danger,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.bg, width: 1.6),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 2),
            InkWell(
              onTap: onProfile,
              borderRadius: BorderRadius.circular(22),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [AppColors.accent, AppColors.ai],
                  ),
                ),
                alignment: Alignment.center,
                child: const Text('S',
                    style: TextStyle(
                        color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DateSelector extends StatelessWidget {
  final String range;
  final VoidCallback onTap;

  const _DateSelector({required this.range, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.calendar_today, size: 14, color: AppColors.accent),
            const SizedBox(width: 8),
            Text(range,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(width: 6),
            const Icon(Icons.arrow_drop_down, size: 18, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}