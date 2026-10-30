import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../services/finance_repository.dart';
import '../../widgets/common.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _demoMode = demoModeEnabled;
  bool _checking = false;
  bool? _backendOnline;
  String? _connectionMessage;

  Future<void> _setDemoMode(bool value) async {
    setState(() => _demoMode = value);
    await setDemoModeEnabled(value);
    if (!value) await _checkBackend();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          value
              ? 'Demo mode enabled. Sample data is shown throughout the prototype.'
              : 'Demo mode disabled. Loading your saved PostgreSQL data.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _editUserId() async {
    final controller = TextEditingController(text: currentUserId);
    final id = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Data namespace'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'User id',
            hintText: 'local-user',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) Navigator.pop(ctx, value);
            },
            child: const Text('Use id'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (id == null || !mounted) return;
    await setUserIdentity(id);
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Now reading records for "$id".'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _checkBackend() async {
    setState(() => _checking = true);
    var online = false;
    var databaseOnline = false;
    try {
      final status = await ApiClient.instance.healthDetails();
      online = status['status'] == 'ok';
      databaseOnline = status['database'] == 'connected';
    } catch (_) {
      online = false;
    }
    if (!mounted) return;
    setState(() {
      _backendOnline = online && databaseOnline;
      _connectionMessage = !online
          ? 'Backend unavailable'
          : databaseOnline
          ? 'API and PostgreSQL connected'
          : 'API online, PostgreSQL unavailable';
      _checking = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
        children: [
          const SectionHeader(title: 'Prototype'),
          AppCard(
            child: Column(
              children: [
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _demoMode,
                  onChanged: _setDemoMode,
                  activeThumbColor: AppColors.accent,
                  title: const Text(
                    'Demo mode',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: const Text(
                    'Load sample finances and show the WealthSync prototype.',
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                  secondary: const Icon(
                    Icons.play_circle_outline,
                    color: AppColors.accent,
                  ),
                ),
                if (_demoMode)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Pill('DEMO DATA', color: AppColors.warning),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const SectionHeader(title: 'Your data'),
          AppCard(
            child: Row(
              children: [
                const Icon(Icons.folder_shared_outlined,
                    color: AppColors.accent),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'PostgreSQL namespace',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        currentUserId,
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: _demoMode ? null : _editUserId,
                  child: const Text('Change'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const SectionHeader(title: 'Backend connection'),
          AppCard(
            child: Row(
              children: [
                Icon(
                  _backendOnline == null
                      ? Icons.cloud_outlined
                      : (_backendOnline!
                            ? Icons.cloud_done_outlined
                            : Icons.cloud_off_outlined),
                  color: _backendOnline == null
                      ? AppColors.textMuted
                      : (_backendOnline!
                            ? AppColors.income
                            : AppColors.warning),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _backendOnline == null
                        ? 'Check API and PostgreSQL'
                        : _connectionMessage!,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _checking ? null : _checkBackend,
                  child: Text(_checking ? 'Checking…' : 'Check'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'With demo mode off, every screen reads the current namespace from PostgreSQL through the backend. Transactions you add are written to the same namespace, and other tabs refresh automatically. ML predictions and SMS classification use the existing model services.',
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 12,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}
