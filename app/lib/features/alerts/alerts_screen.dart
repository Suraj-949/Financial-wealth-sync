import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../models/models.dart';
import '../../services/finance_repository.dart';

class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  final repo = getRepository();

  List<AlertItem>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await repo.fetchAlerts();
      if (!mounted) return;
      setState(() {
        _items = items;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  void _toggle(AlertItem item) {
    setState(() => item.read = !item.read);
  }

  void _markAllRead() {
    setState(() {
      for (final a in _items ?? <AlertItem>[]) {
        a.read = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final unread = (items ?? const <AlertItem>[]).where((a) => !a.read).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Alerts'),
        actions: [
          TextButton(
            onPressed: _markAllRead,
            child: const Text('Mark all read',
                style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: AppColors.accent,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 6, 18, 20),
          children: [
            if (_error != null)
              ErrorState(message: _error!, onRetry: _load)
            else if (items == null)
              Column(children: const [
                Skeleton(height: 70, radius: 14),
                SizedBox(height: 10),
                Skeleton(height: 70, radius: 14),
              ])
            else if (items.isEmpty)
              const EmptyState(
                  icon: Icons.notifications_off_outlined,
                  title: 'All caught up',
                  message: 'You have no alerts right now.')
            else ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(unread > 0 ? '$unread unread' : 'All read',
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5, fontWeight: FontWeight.w600)),
              ),
              AppCard(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Column(
                  children: [
                    for (final item in items) _alertRow(item),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _alertRow(AlertItem item) {
    final unread = !item.read;
    return InkWell(
      onTap: () => _toggle(item),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.emoji, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.text,
                      style: TextStyle(
                        color: unread ? AppColors.textPrimary : AppColors.textMuted,
                        fontSize: 13.5,
                        fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
                      )),
                  const SizedBox(height: 3),
                  Text(item.time,
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
                ],
              ),
            ),
            if (unread)
              Container(
                margin: const EdgeInsets.only(top: 6),
                width: 9,
                height: 9,
                decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
              ),
          ],
        ),
      ),
    );
  }
}