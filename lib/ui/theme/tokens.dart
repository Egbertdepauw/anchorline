import 'package:flutter/material.dart';

/// Single source of truth for every visual decision in CCRLog.
///
/// Widgets should read theme values via `Theme.of(context)` once we've
/// built the `ThemeData` from these tokens. Direct references to this
/// file are appropriate inside theme construction and inside the
/// chart layers where there's no `BuildContext`.

// ── Palette ──────────────────────────────────────────────────────────

/// A complete colour palette. Wraps the Wreck dark palette today; future
/// light-mode tropical palettes are added as additional constants.
class ThemePalette {
  const ThemePalette({
    required this.surfaceBg,
    required this.surfaceCard,
    required this.surfaceRaised,
    required this.surfaceBezel,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.textInverse,
    required this.accentPrimary,
    required this.accentMuted,
    required this.statusSuccess,
    required this.statusWarning,
    required this.statusDanger,
    required this.statusInfo,
    required this.cell1,
    required this.cell2,
    required this.cell3,
    required this.chartGrid,
    required this.chartTraceDepth,
    required this.chartTracePpo2,
    required this.chartTraceSetpoint,
    required this.chartTraceGf99,
  });

  final Color surfaceBg;
  final Color surfaceCard;
  final Color surfaceRaised;
  final Color surfaceBezel;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color textInverse;
  final Color accentPrimary;
  final Color accentMuted;
  final Color statusSuccess;
  final Color statusWarning;
  final Color statusDanger;
  final Color statusInfo;
  final Color cell1;
  final Color cell2;
  final Color cell3;
  final Color chartGrid;
  final Color chartTraceDepth;
  final Color chartTracePpo2;
  final Color chartTraceSetpoint;
  final Color chartTraceGf99;
}

class AppColors {
  AppColors._();

  /// Default dark mode. Reference: spec §"Visual direction — Wreck".
  static const ThemePalette wreck = ThemePalette(
    surfaceBg: Color(0xFF0A1518),
    surfaceCard: Color(0xFF142028),
    surfaceRaised: Color(0xFF1F2E38),
    surfaceBezel: Color(0xFF2A3A45),
    textPrimary: Color(0xFFE0E8EC),
    textSecondary: Color(0xFFA0AEB6),
    textMuted: Color(0xFF6B7D88),
    textInverse: Color(0xFF0A1518),
    accentPrimary: Color(0xFFFFCC66),
    accentMuted: Color(0xFF806633),
    statusSuccess: Color(0xFF4ADE80),
    statusWarning: Color(0xFFF39C12),
    statusDanger: Color(0xFFE74C3C),
    statusInfo: Color(0xFF60A5FA),
    cell1: Color(0xFF4ADE80),
    cell2: Color(0xFF60A5FA),
    cell3: Color(0xFFF472B6),
    chartGrid: Color(0xFF1A2832),
    chartTraceDepth: Color(0xFFE0E8EC),
    chartTracePpo2: Color(0xFFFFCC66),
    chartTraceSetpoint: Color(0xFFA0AEB6),
    chartTraceGf99: Color(0xFFF472B6),
  );
}

// ── Typography ───────────────────────────────────────────────────────

/// Pre-built `TextStyle`s referencing Inter (body) + JetBrains Mono
/// (readouts). Sizes/weights/tracking match the spec's type-scale table.
class AppTypography {
  AppTypography._();

  static const _tabular = [FontFeature.tabularFigures()];

  // Body (Inter)
  static const TextStyle display = TextStyle(
    fontFamily: 'Inter',
    fontSize: 28,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.5,
  );
  static const TextStyle headline = TextStyle(
    fontFamily: 'Inter',
    fontSize: 20,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.3,
  );
  static const TextStyle title = TextStyle(
    fontFamily: 'Inter',
    fontSize: 16,
    fontWeight: FontWeight.w600,
  );
  static const TextStyle body = TextStyle(
    fontFamily: 'Inter',
    fontSize: 14,
    fontWeight: FontWeight.w400,
  );
  static const TextStyle label = TextStyle(
    fontFamily: 'Inter',
    fontSize: 12,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.6,
  );
  static const TextStyle caption = TextStyle(
    fontFamily: 'Inter',
    fontSize: 11,
    fontWeight: FontWeight.w400,
  );

  // Readouts (JetBrains Mono, tabular figures)
  static const TextStyle readoutLg = TextStyle(
    fontFamily: 'JetBrainsMono',
    fontSize: 24,
    fontWeight: FontWeight.w600,
    fontFeatures: _tabular,
  );
  static const TextStyle readoutMd = TextStyle(
    fontFamily: 'JetBrainsMono',
    fontSize: 16,
    fontWeight: FontWeight.w500,
    fontFeatures: _tabular,
  );
  static const TextStyle readoutSm = TextStyle(
    fontFamily: 'JetBrainsMono',
    fontSize: 13,
    fontWeight: FontWeight.w400,
    fontFeatures: _tabular,
  );
}

// ── Spacing ──────────────────────────────────────────────────────────

class Spacing {
  Spacing._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;
}

// ── Radii ────────────────────────────────────────────────────────────

class Radii {
  Radii._();
  /// Cards / panels / readouts: 2px hard-edge.
  static const Radius card = Radius.circular(2);
  static const Radius button = Radius.circular(2);
  static const Radius chip = Radius.circular(2);
  /// Modals / sheets: slight softening so they don't read as system errors.
  static const Radius modal = Radius.circular(4);

  static const BorderRadius cardBr = BorderRadius.all(card);
  static const BorderRadius buttonBr = BorderRadius.all(button);
  static const BorderRadius chipBr = BorderRadius.all(chip);
  static const BorderRadius modalTopBr = BorderRadius.vertical(top: modal);
}

// ── Elevation ────────────────────────────────────────────────────────

/// We don't use Material drop shadows on the dark theme — they read as
/// rendering bugs. Elevation is expressed via layered surface colour.
class Elevation {
  Elevation._();
  /// Number of "depth levels" the design system supports.
  static const int levels = 3;
}

// ── Motion ───────────────────────────────────────────────────────────

class Motion {
  Motion._();
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration standard = Duration(milliseconds: 240);
  static const Duration emphasized = Duration(milliseconds: 400);
  static const Curve fastCurve = Curves.easeOut;
  static const Curve standardCurve = Curves.easeInOutCubic;
  static const Curve emphasizedCurve = Curves.easeInOutCubicEmphasized;
}
