import 'package:flutter/material.dart';

/// WealthSync design tokens — dark premium fintech palette.
class AppColors {
  static const bg = Color(0xFF0F1220);
  static const surface = Color(0xFF171B2E);
  static const surfaceAlt = Color(0xFF1F2440);
  static const line = Color(0xFF2B3156);
  static const textPrimary = Color(0xFFF1F3FF);
  static const textMuted = Color(0xFF9AA3C7);

  /// WealthSync accent (purple / violet for AI features & active states).
  static const accent = Color(0xFF6C7BFF);
  static const ai = Color(0xFFA78BFA);

  static const income = Color(0xFF2FD06A);
  static const expense = Color(0xFFFF5D73);
  static const warning = Color(0xFFFFB84D);
  static const savings = Color(0xFF36B4FF);
  static const danger = Color(0xFFFF5D73);

  static const successFaint = Color(0x332FD06A);
  static const expenseFaint = Color(0x33FF5D73);
}

class AppTheme {
  const AppTheme._();

  static ThemeData dark() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.bg,
      colorScheme: const ColorScheme.dark(
        surface: AppColors.bg,
        onSurface: AppColors.textPrimary,
        primary: AppColors.accent,
        secondary: AppColors.ai,
        error: AppColors.danger,
        onPrimary: Colors.white,
      ),
      fontFamily: 'Segoe UI',
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 19,
          fontWeight: FontWeight.w700,
        ),
        iconTheme: IconThemeData(color: AppColors.textPrimary),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.line),
        ),
        margin: EdgeInsets.zero,
      ),
      dividerTheme: const DividerThemeData(color: AppColors.line, thickness: 1),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.accent.withValues(alpha: .18),
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStatePropertyAll(
          const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final active = states.contains(WidgetState.selected);
          return IconThemeData(
            color: active ? AppColors.accent : AppColors.textMuted,
            size: 24,
          );
        }),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surfaceAlt,
        contentTextStyle: const TextStyle(color: AppColors.textPrimary, fontSize: 13.5),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
      ),
    );
    return base;
  }

  static double radius() => 16;
}