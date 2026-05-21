import 'package:flutter/material.dart';

import 'tokens.dart';

class AppTheme {
  AppTheme._();

  static ThemeData dark() {
    const palette = AppColors.wreck;

    final colorScheme = ColorScheme(
      brightness: Brightness.dark,
      primary: palette.accentPrimary,
      onPrimary: palette.textInverse,
      secondary: palette.accentMuted,
      onSecondary: palette.textPrimary,
      error: palette.statusDanger,
      onError: palette.textPrimary,
      surface: palette.surfaceBg,
      onSurface: palette.textPrimary,
      surfaceContainer: palette.surfaceCard,
      surfaceContainerHigh: palette.surfaceRaised,
      outline: palette.surfaceBezel,
      outlineVariant: palette.textMuted,
    );

    final textTheme = TextTheme(
      displayLarge: AppTypography.display.copyWith(color: palette.textPrimary),
      displayMedium: AppTypography.display.copyWith(color: palette.textPrimary),
      headlineLarge:
          AppTypography.headline.copyWith(color: palette.textPrimary),
      headlineMedium:
          AppTypography.headline.copyWith(color: palette.textPrimary),
      titleLarge: AppTypography.title.copyWith(color: palette.textPrimary),
      titleMedium: AppTypography.title.copyWith(color: palette.textPrimary),
      bodyLarge: AppTypography.body.copyWith(color: palette.textPrimary),
      bodyMedium: AppTypography.body.copyWith(color: palette.textPrimary),
      bodySmall: AppTypography.caption.copyWith(color: palette.textSecondary),
      labelLarge: AppTypography.label.copyWith(color: palette.textSecondary),
      labelMedium: AppTypography.label.copyWith(color: palette.textSecondary),
      labelSmall: AppTypography.caption.copyWith(color: palette.textMuted),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      textTheme: textTheme,
      scaffoldBackgroundColor: palette.surfaceBg,
      cardColor: palette.surfaceCard,
      dividerColor: palette.surfaceBezel,
      appBarTheme: AppBarTheme(
        backgroundColor: palette.surfaceBg,
        foregroundColor: palette.textPrimary,
        elevation: 0,
        // Force left-aligned titles everywhere. Flutter's per-platform
        // default centres on iOS / macOS, leads on Android — without
        // this the Dives tab (which uses the AppShell's AppBar) reads
        // left-aligned while the Plan / Blend / Settings tabs each
        // have their own AppBars that pick up the platform default.
        centerTitle: false,
        titleTextStyle:
            AppTypography.headline.copyWith(color: palette.textPrimary),
      ),
      cardTheme: CardThemeData(
        color: palette.surfaceCard,
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: Radii.cardBr),
        margin: EdgeInsets.zero,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: palette.surfaceBg,
        selectedItemColor: palette.accentPrimary,
        unselectedItemColor: palette.textMuted,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: palette.accentPrimary,
          foregroundColor: palette.textInverse,
          shape: const RoundedRectangleBorder(borderRadius: Radii.buttonBr),
          textStyle:
              AppTypography.label.copyWith(letterSpacing: 0.6),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: palette.accentPrimary,
          side: BorderSide(color: palette.accentPrimary),
          shape: const RoundedRectangleBorder(borderRadius: Radii.buttonBr),
          textStyle:
              AppTypography.label.copyWith(letterSpacing: 0.6),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: palette.accentPrimary,
          shape: const RoundedRectangleBorder(borderRadius: Radii.buttonBr),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: palette.surfaceCard,
        labelStyle: AppTypography.caption.copyWith(color: palette.textPrimary),
        shape: const RoundedRectangleBorder(borderRadius: Radii.chipBr),
        side: BorderSide(color: palette.surfaceBezel),
        padding: const EdgeInsets.symmetric(horizontal: Spacing.sm),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.surfaceCard,
        border: OutlineInputBorder(
          borderRadius: Radii.cardBr,
          borderSide: BorderSide(color: palette.surfaceBezel),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: Radii.cardBr,
          borderSide: BorderSide(color: palette.surfaceBezel),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: Radii.cardBr,
          borderSide: BorderSide(color: palette.accentPrimary),
        ),
        labelStyle:
            AppTypography.caption.copyWith(color: palette.textSecondary),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: palette.surfaceRaised,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radii.modal),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: palette.surfaceRaised,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: Radii.modalTopBr),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: palette.surfaceRaised,
        contentTextStyle:
            AppTypography.body.copyWith(color: palette.textPrimary),
        shape: const RoundedRectangleBorder(borderRadius: Radii.cardBr),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
