import 'package:flutter/material.dart';

abstract final class AppColors {
  static const mango = Color(0xFFFFB526);
  static const leaf = Color(0xFF2F7D5B);
  static const purple = Color(0xFF7457D9);
  static const cream = Color(0xFFFFF9ED);
  static const ink = Color(0xFF25221E);
}

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.mango,
    primary: AppColors.leaf,
    secondary: AppColors.purple,
    surface: AppColors.cream,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.cream,
    textTheme: const TextTheme(
      headlineMedium: TextStyle(
        fontWeight: FontWeight.w800,
        color: AppColors.ink,
      ),
      titleLarge: TextStyle(fontWeight: FontWeight.w800, color: AppColors.ink),
      bodyLarge: TextStyle(height: 1.35, color: AppColors.ink),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: BorderSide.none,
      ),
    ),
  );
}
