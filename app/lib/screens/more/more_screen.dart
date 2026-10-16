import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../widgets/common.dart';
import '../alerts/alerts_screen.dart';
import '../copilot/copilot_chat_screen.dart';
import '../profile/profile_screen.dart';
import '../sms/sms_classifier_screen.dart';
import '../stub/stub_screen.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  void _push(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    final entries = <({IconData icon, Color color, String title, Widget page})>[
      (
        icon: Icons.trending_up,
        color: AppColors.income,
        title: 'Investments',
        page: const StubScreen(title: 'Investments', icon: Icons.trending_up)
      ),
      (
        icon: Icons.account_balance,
        color: AppColors.warning,
        title: 'Loans & EMIs',
        page: const StubScreen(title: 'Loans & EMIs', icon: Icons.account_balance)
      ),
      (
        icon: Icons.credit_card,
        color: AppColors.ai,
        title: 'Credit Cards',
        page: const StubScreen(title: 'Credit Cards', icon: Icons.credit_card)
      ),
      (
        icon: Icons.description_outlined,
        color: AppColors.savings,
        title: 'Reports',
        page: const StubScreen(title: 'Reports', icon: Icons.description_outlined)
      ),
      (
        icon: Icons.notifications_none,
        color: AppColors.warning,
        title: 'Alerts',
        page: const AlertsScreen()
      ),
      (
        icon: Icons.smart_toy_outlined,
        color: AppColors.accent,
        title: 'AI Copilot',
        page: const CopilotChatScreen()
      ),
      (
        icon: Icons.mark_email_unread_outlined,
        color: AppColors.savings,
        title: 'SMS Payments',
        page: const SmsClassifierScreen()
      ),
      (
        icon: Icons.settings_outlined,
        color: AppColors.textMuted,
        title: 'Settings',
        page: const StubScreen(title: 'Settings', icon: Icons.settings_outlined)
      ),
      (
        icon: Icons.person_outline,
        color: AppColors.accent,
        title: 'Profile',
        page: const ProfileScreen()
      ),
    ];

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 20),
        children: [
          const Text('More',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 21, fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          AppCard(
            child: Column(
              children: [
                for (var i = 0; i < entries.length; i++)
                  InkWell(
                    onTap: () => _push(context, entries[i].page),
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 13),
                      child: Row(
                        children: [
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: entries[i].color.withValues(alpha: .16),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            alignment: Alignment.center,
                            child: Icon(entries[i].icon, color: entries[i].color, size: 18),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(entries[i].title,
                                style: const TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w600)),
                          ),
                          const Icon(Icons.chevron_right, color: AppColors.textMuted, size: 20),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}