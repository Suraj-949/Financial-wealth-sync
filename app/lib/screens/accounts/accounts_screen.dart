import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../widgets/common.dart';
import '../../utils/formatters.dart';
import '../../models/models.dart';
import '../../services/finance_repository.dart';

class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key});

  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> {
  final repo = getRepository();

  List<Account>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await repo.fetchAccounts();
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

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final total = (items ?? const <Account>[])
        .where((a) => a.balance > 0)
        .fold<double>(0, (a, b) => a + b.balance);

    return Scaffold(
      appBar: AppBar(title: const Text('Accounts & Cards')),
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
                Skeleton(height: 120, radius: 16),
                SizedBox(height: 12),
                Skeleton(height: 70, radius: 16),
              ])
            else ...[
              AppCard(
                color: AppColors.surface,
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          Text(Formatters.inr(total),
                              style: const TextStyle(
                                  color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 2),
                          const Text('Net balance',
                              style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                        ],
                      ),
                    ),
                    Container(width: 1, height: 30, color: AppColors.line),
                    const Expanded(
                      child: Column(
                        children: [
                          Text('End-to-end',
                              style: TextStyle(
                                  color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.w800)),
                          SizedBox(height: 2),
                          Text('encrypted & PIN protected',
                              style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              for (final account in items) _accountCard(account),
            ],
          ],
        ),
      ),
    );
  }

  Widget _accountCard(Account account) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: account.color.withValues(alpha: .15),
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: Icon(account.icon, color: account.color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(account.bank,
                      style: const TextStyle(
                          color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(account.subLabel,
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(Formatters.inr(account.balance),
                    style: const TextStyle(
                        color: AppColors.textPrimary, fontSize: 15.5, fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.lock_outline, size: 11, color: AppColors.textMuted),
                    SizedBox(width: 3),
                    Text('Masked for privacy',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 10.5)),
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