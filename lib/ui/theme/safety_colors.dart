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

  /// Limit bands for gas density and END readouts. Same colours as the
  /// GF bands: within limits, approaching, over.
  static const Color bandSafe = gfWithinLimits;
  static const Color bandCaution = gfOverHigh;
  static const Color bandOver = gfOverLimit;

  /// Background of a full-width alert banner, and of a destructive
  /// swipe action when drawn with [danger].
  static const Color alertCriticalSurface = Color(0xFFB71C1C);
  static const Color alertWarningSurface = Color(0xFFE65100);

  /// Text and icons on an alert surface or on [danger].
  static const Color onAlert = Color(0xFFFFFFFF);

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
