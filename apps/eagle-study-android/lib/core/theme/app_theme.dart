import 'package:flutter/material.dart';

abstract final class AppColors {
  static const background = Color(0xFF07182A);
  static const surface = Color(0xFF24364D);
  static const surfaceLight = Color(0xFF344A63);
  static const cyan = Color(0xFF56D9F5);
  static const cyanDeep = Color(0xFF1BA6C8);
  static const lime = Color(0xFFC9FF72);
  static const pink = Color(0xFFFF548E);
  static const text = Color(0xFFF2F7FC);
  static const muted = Color(0xFFA8B8C8);
}

abstract final class AppTheme {
  static ThemeData get dark {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.cyan,
      brightness: Brightness.dark,
      primary: AppColors.cyan,
      secondary: AppColors.lime,
      surface: AppColors.surface,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      fontFamily: 'Roboto',
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          color: AppColors.text,
          fontSize: 32,
          fontWeight: FontWeight.w700,
          letterSpacing: -1,
        ),
        titleLarge: TextStyle(
          color: AppColors.text,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
        titleMedium: TextStyle(
          color: AppColors.text,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
        bodyMedium: TextStyle(color: AppColors.muted, fontSize: 14),
        labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.surfaceLight,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.lime
              : AppColors.muted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.lime.withValues(alpha: 0.25)
              : AppColors.surfaceLight,
        ),
      ),
    );
  }
}
