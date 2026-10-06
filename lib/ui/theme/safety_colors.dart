import 'package:flutter/material.dart';

/// Colours that carry safety meaning. They are identical in every theme:
/// a warning must look like a warning whatever palette the diver picked.
/// Never derive these from the active theme.
class SafetyColors {
  SafetyColors._();

  static const Color success = Color(0xFF4ADE80);
  static const Color warning = Color(0xFFF39C12);
  static const Color danger = Color(0xFFE74C3C);
  static const Color info = Color(0xFF60A5FA);

  /// Gradient-factor bands, see `gfBandColor`.
  static const Color gfWithinLimits = Color(0xFF4ADE80);
  static const Color gfOverHigh = Color(0xFFF59E0B);
  static const Color gfOverLimit = Color(0xFFDC2626);

  /// Every safety colour by name, for tests that check them against each
  /// theme's surfaces.
  static const Map<String, Color> all = {
    'success': success,
    'warning': warning,
    'danger': danger,
    'info': info,
    'gfWithinLimits': gfWithinLimits,
    'gfOverHigh': gfOverHigh,
    'gfOverLimit': gfOverLimit,
  };
}
