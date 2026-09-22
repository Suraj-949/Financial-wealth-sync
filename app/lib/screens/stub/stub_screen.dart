import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// Placeholder for screens that will be implemented next (Investments,
/// Loans & EMIs, Credit Cards, Reports, Settings).
class StubScreen extends StatelessWidget {
  final String title;
  final IconData icon;

  const StubScreen({super.key, required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: .14),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: AppColors.accent, size: 34),
            ),
            const SizedBox(height: 16),
            Text('$title is coming soon',
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text('This screen will be built next in the WealthSync roadmap.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }
}