import 'package:flutter/material.dart';

import '../../app/constants.dart';
import '../../app/theme.dart';
import '../../widgets/common.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
        children: [
          AppCard(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [AppColors.accent, AppColors.ai],
                    ),
                  ),
                  alignment: Alignment.center,
                  child: const Text('S',
                      style: TextStyle(
                          color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(AppConstants.userName,
                          style: const TextStyle(
                              color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      const Text('suraj@wealthsync.in',
                          style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                      const SizedBox(height: 6),
                      const Pill('Premium plan', color: AppColors.accent),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const AppCard(
            child: Column(
              children: [
                _ProfileRow(icon: Icons.phone_android, label: 'Connected phone'),
                _ProfileRow(icon: Icons.badge_outlined, label: 'KYC status'),
                _ProfileRow(icon: Icons.lock_outline, label: 'Privacy & security'),
                _ProfileRow(icon: Icons.help_outline, label: 'Help & support'),
                _ProfileRow(icon: Icons.logout, label: 'Log out'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileRow extends StatelessWidget {
  final IconData icon;
  final String label;

  const _ProfileRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 13),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.textMuted),
          const SizedBox(width: 14),
          Expanded(
            child: Text(label,
                style: const TextStyle(
                    color: AppColors.textPrimary, fontSize: 14.5, fontWeight: FontWeight.w500)),
          ),
          const Icon(Icons.chevron_right, size: 20, color: AppColors.textMuted),
        ],
      ),
    );
  }
}