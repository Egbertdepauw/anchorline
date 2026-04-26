import 'package:flutter/material.dart';

class AppTheme {
  static const _seedColor = Color(0xFF4FC3F7);
  static const _surfaceColor = Color(0xFF0D1B2A);
  static const _cardColor = Color(0xFF152238);

  static ThemeData dark() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _seedColor,
      brightness: Brightness.dark,
      surface: _surfaceColor,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: _surfaceColor,
      cardColor: _cardColor,
      appBarTheme: AppBarTheme(
        backgroundColor: _surfaceColor,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: _surfaceColor,
        selectedItemColor: _seedColor,
        unselectedItemColor: colorScheme.onSurface.withValues(alpha: 0.5),
      ),
    );
  }
}
