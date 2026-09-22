library;

import 'package:flutter/material.dart';

import '../app/theme.dart';

class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Border? border;
  final VoidCallback? onTap;
  final double radius;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color,
    this.border,
    this.onTap,
    this.radius = 16,
  });

  @override
  Widget build(BuildContext context) {
    final content = Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? AppColors.surface,
        borderRadius: BorderRadius.circular(radius),
        border: border ?? Border.all(color: AppColors.line),
        // subtle glow for AI cards
        boxShadow: color == AppColors.surface
            ? const [BoxShadow(color: Color(0x14000000), blurRadius: 10, offset: Offset(0, 3))]
            : null,
      ),
      child: child,
    );
    if (onTap == null) return content;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(radius),
      child: content,
    );
  }
}

class SectionHeader extends StatelessWidget {
  final String title;
  final String? action;
  final VoidCallback? onAction;
  final Widget? trailing;

  const SectionHeader({super.key, required this.title, this.action, this.onAction, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          ?trailing,
          if (action != null)
            InkWell(
              onTap: onAction,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Text(
                  action!,
                  style: const TextStyle(color: AppColors.accent, fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class Pill extends StatelessWidget {
  final String label;
  final Color color;
  final bool filled;
  final IconData? icon;

  const Pill(this.label, {super.key, this.color = AppColors.textMuted, this.filled = false, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: filled ? color : color.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: color.withValues(alpha: filled ? 0 : .45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 13, color: filled ? Colors.black : color), const SizedBox(width: 4)],
          Text(
            label,
            style: TextStyle(
              color: filled ? Colors.black : color,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Small corner tag (e.g. BETA / NEW) used next to section titles.
/// Named TagBadge to avoid clashing with Material 3's built-in [Badge] widget.
class TagBadge {
  static Widget newTag() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.accent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Text('NEW',
            style: TextStyle(
                color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: .6)),
      );

  static Widget beta() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.ai.withValues(alpha: .2),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.ai.withValues(alpha: .5)),
        ),
        child: const Text('BETA',
            style: TextStyle(
                color: AppColors.ai, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: .6)),
      );
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const EmptyState({super.key, required this.icon, required this.title, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 42, color: AppColors.textMuted),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

class ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const ErrorState({super.key, required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 42, color: AppColors.danger),
            const SizedBox(height: 12),
            const Text('Something went wrong',
                style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

/// Pulsing skeleton placeholder.
class Skeleton extends StatefulWidget {
  final double height;
  final double? width;
  final double radius;

  const Skeleton({super.key, this.height = 14, this.width, this.radius = 8});

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
    lowerBound: 0.3,
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _c,
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}

class DashboardSkeleton extends StatelessWidget {
  const DashboardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final skeleton = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Skeleton(height: 20, width: 180),
        const SizedBox(height: 16),
        const Skeleton(height: 120, width: 280, radius: 16),
        const SizedBox(height: 18),
        const SectionHeaderThenSkeleton(),
        const SizedBox(height: 8),
        const Skeleton(height: 96, width: 280, radius: 16),
        const SizedBox(height: 14),
        _rowOfSkeletons(3),
        const SizedBox(height: 22),
        _block(),
        const SizedBox(height: 22),
        _block(tall: true),
      ],
    );
    return Padding(
      padding: const EdgeInsets.all(18),
      child: SizedBox(width: double.infinity, child: skeleton),
    );
  }

  Widget _rowOfSkeletons(int n) {
    return Row(
      children: List.generate(n, (_) => const Padding(
        padding: EdgeInsets.all(4),
        child: Skeleton(height: 64, width: 64, radius: 12),
      )),
    );
  }

  Widget _block({bool tall = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Skeleton(height: 16, width: 150),
        const SizedBox(height: 8),
        Skeleton(height: tall ? 180 : 96, radius: 16),
      ],
    );
  }
}

class SectionHeaderThenSkeleton extends StatelessWidget {
  const SectionHeaderThenSkeleton({super.key});
  @override
  Widget build(BuildContext context) => const Skeleton(height: 14, width: 120);
}