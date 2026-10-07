// Turns an Omarchy theme's raw colours into the app's ThemePalette.
//
// Omarchy palettes are designed for terminals and window chrome, so two
// corrections happen here and nowhere else: text colours are lifted until
// they meet a contrast floor, and cell / PPO2 colours fall back to the
// Wreck values when the theme's own are not distinct enough.

import 'package:flutter/material.dart';

import '../color_math.dart';
import '../tokens.dart';
import 'omarchy_colors.dart';

/// Minimum WCAG contrast for primary and secondary text.
const double kMinTextContrast = 4.5;

/// Minimum WCAG contrast for muted text.
const double kMinMutedTextContrast = 3.0;

/// Minimum WCAG contrast for a cell or trace colour on a card.
const double kMinTraceContrast = 3.0;

/// Minimum CIEDE2000 difference between any two cell colours.
const double kMinCellDeltaE = 20;

/// Minimum CIEDE2000 difference between the PPO2 trace and the depth trace,
/// the setpoint trace, and each cell colour.
const double kMinPpo2DeltaE = 15;

/// Returns [color] if it has at least [minRatio] contrast against every
/// one of [backgrounds]; otherwise blends it toward [toward] in 5% steps
/// and returns the first blend that does. Returns [toward] if none does.
Color liftToContrast(
  Color color,
  Color toward,
  List<Color> backgrounds,
  double minRatio,
) {
  bool passes(Color c) =>
      backgrounds.every((bg) => contrastRatio(c, bg) >= minRatio);
  if (passes(color)) return color;
  for (var step = 1; step <= 20; step++) {
    final candidate = Color.lerp(color, toward, step * 0.05)!;
    if (passes(candidate)) return candidate;
  }
  return toward;
}

/// Whether three colours can serve as cell 1/2/3 on [card]: each readable
/// on the card, and each clearly different from the other two.
bool cellColorsPass(Color c1, Color c2, Color c3, Color card) {
  final cells = [c1, c2, c3];
  if (cells.any((c) => contrastRatio(c, card) < kMinTraceContrast)) {
    return false;
  }
  return deltaE2000(c1, c2) >= kMinCellDeltaE &&
      deltaE2000(c1, c3) >= kMinCellDeltaE &&
      deltaE2000(c2, c3) >= kMinCellDeltaE;
}

/// Whether [ppo2] can serve as the PPO2 trace on [card]: readable on the
/// card, and clearly different from the [depth] and [setpoint] traces and
/// from each of the three [cells], which share its axis.
bool ppo2ColorPasses(
  Color ppo2,
  Color depth,
  Color setpoint,
  Color card,
  List<Color> cells,
) =>
    contrastRatio(ppo2, card) >= kMinTraceContrast &&
    deltaE2000(ppo2, depth) >= kMinPpo2DeltaE &&
    deltaE2000(ppo2, setpoint) >= kMinPpo2DeltaE &&
    cells.every((c) => deltaE2000(ppo2, c) >= kMinPpo2DeltaE);

/// Maps one Omarchy theme onto the app's tokens, lifting text colours to the
/// contrast floors and using the Wreck cell / PPO2 colours where the theme's
/// flags say its own are not distinct enough.
ThemePalette paletteFromOmarchy(OmarchyColors o) {
  const wreck = AppColors.wreck;
  final surfaces = [o.background, o.lighterBackground];
  final textPrimary = o.foreground;
  final textSecondary = liftToContrast(
    o.lightForeground,
    o.foreground,
    surfaces,
    kMinTextContrast,
  );
  final textMuted = liftToContrast(
    o.darkForeground,
    o.foreground,
    surfaces,
    kMinMutedTextContrast,
  );
  final cell3 = o.useOwnCellColors ? o.magenta : wreck.cell3;

  return ThemePalette(
    surfaceBg: o.background,
    surfaceCard: o.lighterBackground,
    surfaceRaised: o.selection,
    surfaceBezel: o.muted,
    textPrimary: textPrimary,
    textSecondary: textSecondary,
    textMuted: textMuted,
    textInverse: o.background,
    accentPrimary: o.accent,
    accentMuted: Color.lerp(o.accent, o.background, 0.5)!,
    cell1: o.useOwnCellColors ? o.green : wreck.cell1,
    cell2: o.useOwnCellColors ? o.blue : wreck.cell2,
    cell3: cell3,
    chartGrid: Color.lerp(o.lighterBackground, o.selection, 0.5)!,
    chartTraceDepth: textPrimary,
    chartTracePpo2: o.useOwnPpo2Color ? o.yellow : wreck.chartTracePpo2,
    chartTraceSetpoint: textSecondary,
    chartTraceGf99: cell3,
  );
}
