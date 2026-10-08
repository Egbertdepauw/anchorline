import 'package:flutter/material.dart';

import 'anchorline_colors.dart';

/// Single source of truth for every visual decision in CCRLog.
///
/// Widgets read colours with `context.palette`. Painters, which have no
/// `BuildContext`, receive the palette from the widget that owns them.
/// Only the theme layer itself names `AppColors.wreck` (a test enforces
/// this).

// ── Palette ──────────────────────────────────────────────────────────

/// A complete colour palette, carried in ThemeData as a theme extension.
/// Read it in widgets with context.palette.
class ThemePalette extends ThemeExtension<ThemePalette> {
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
    required this.cell1,
    required this.cell2,
    required this.cell3,
    required this.chartGrid,
    required this.chartTraceDepth,
    required this.chartTracePpo2,
    required this.chartTraceSetpoint,
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
  final Color cell1;
  final Color cell2;
  final Color cell3;
  final Color chartGrid;
  final Color chartTraceDepth;
  final Color chartTracePpo2;
  final Color chartTraceSetpoint;

  @override
  ThemePalette copyWith({
    Color? surfaceBg,
    Color? surfaceCard,
    Color? surfaceRaised,
    Color? surfaceBezel,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? textInverse,
    Color? accentPrimary,
    Color? accentMuted,
    Color? cell1,
    Color? cell2,
    Color? cell3,
    Color? chartGrid,
    Color? chartTraceDepth,
    Color? chartTracePpo2,
    Color? chartTraceSetpoint,
  }) {
    return ThemePalette(
      surfaceBg: surfaceBg ?? this.surfaceBg,
      surfaceCard: surfaceCard ?? this.surfaceCard,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      surfaceBezel: surfaceBezel ?? this.surfaceBezel,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      textInverse: textInverse ?? this.textInverse,
      accentPrimary: accentPrimary ?? this.accentPrimary,
      accentMuted: accentMuted ?? this.accentMuted,
      cell1: cell1 ?? this.cell1,
      cell2: cell2 ?? this.cell2,
      cell3: cell3 ?? this.cell3,
      chartGrid: chartGrid ?? this.chartGrid,
      chartTraceDepth: chartTraceDepth ?? this.chartTraceDepth,
      chartTracePpo2: chartTracePpo2 ?? this.chartTracePpo2,
      chartTraceSetpoint: chartTraceSetpoint ?? this.chartTraceSetpoint,
    );
  }

  /// Used by Flutter to cross-fade between two themes.
  @override
  ThemePalette lerp(covariant ThemeExtension<ThemePalette>? other, double t) {
    if (other is! ThemePalette) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return ThemePalette(
      surfaceBg: mix(surfaceBg, other.surfaceBg),
      surfaceCard: mix(surfaceCard, other.surfaceCard),
      surfaceRaised: mix(surfaceRaised, other.surfaceRaised),
      surfaceBezel: mix(surfaceBezel, other.surfaceBezel),
      textPrimary: mix(textPrimary, other.textPrimary),
      textSecondary: mix(textSecondary, other.textSecondary),
      textMuted: mix(textMuted, other.textMuted),
      textInverse: mix(textInverse, other.textInverse),
      accentPrimary: mix(accentPrimary, other.accentPrimary),
      accentMuted: mix(accentMuted, other.accentMuted),
      cell1: mix(cell1, other.cell1),
      cell2: mix(cell2, other.cell2),
      cell3: mix(cell3, other.cell3),
      chartGrid: mix(chartGrid, other.chartGrid),
      chartTraceDepth: mix(chartTraceDepth, other.chartTraceDepth),
      chartTracePpo2: mix(chartTracePpo2, other.chartTracePpo2),
      chartTraceSetpoint: mix(chartTraceSetpoint, other.chartTraceSetpoint),
    );
  }
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
    // Anchorline brand accent — sourced from the brand palette so any
    // future rebrand updates a single colour file. Cascades to every
    // primary button, focus ring, and selected nav item via the
    // ThemeData wiring in app_theme.dart.
    accentPrimary: AnchorlineColors.reelOrange,
    accentMuted: Color(0xFF806633),
    cell1: Color(0xFF4ADE80),
    cell2: Color(0xFF60A5FA),
    cell3: Color(0xFFF472B6),
    chartGrid: Color(0xFF1A2832),
    chartTraceDepth: Color(0xFFE0E8EC),
    chartTracePpo2: Color(0xFFFFCC66),
    chartTraceSetpoint: Color(0xFFA0AEB6),
  );
}

/// The active [ThemePalette]. Falls back to Wreck when the surrounding
/// theme carries none, so a widget built outside the app theme (a test
/// harness, a nested Theme) still gets a complete palette.
extension PaletteContext on BuildContext {
  ThemePalette get palette =>
      Theme.of(this).extension<ThemePalette>() ?? AppColors.wreck;
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
