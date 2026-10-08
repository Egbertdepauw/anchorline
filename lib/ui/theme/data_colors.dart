import 'package:flutter/material.dart';

/// Colours that encode data. They are identical in every theme: a
/// closed-circuit dive, a fast ascent or a saturated tissue must look
/// the same whatever palette the diver picked. Never derive these from
/// the active theme.
class DataColors {
  DataColors._();

  // Dive modes (dive list, dive detail, statistics).
  static const Color modeClosedCircuit = Color(0xFF4FC3F7);
  static const Color modeOpenCircuit = Color(0xFFFF9800);
  static const Color modeSemiClosed = Color(0xFFAB47BC);
  static const Color modeGauge = Color(0xFF78909C);
  static const Color modeFreedive = Color(0xFF26A69A);

  // Profile chart traces that are not theme tokens.
  static const Color waterTemp = Color(0xFF4DD0E1);
  static const Color gf99 = Color(0xFF9333EA);
  static const Color ceiling = Color(0xFFEAB308);

  /// Tank pressure traces, by tank index (wraps).
  static const List<Color> tanks = [
    Color(0xFF80DEEA), // cyan-ish
    Color(0xFFFFAB91), // peach
    Color(0xFFCE93D8), // lilac
    Color(0xFFB0BEC5), // blue grey
    Color(0xFFA5D6A7), // pale green
    Color(0xFFFFE082), // pale amber
  ];

  // Vertical-speed gradient for the speed-coloured depth trace. The calm
  // colour is fixed too, so the gradient reads the same on every theme.
  static const Color speedCalm = Color(0xFFE0E8EC);
  static const Color speedSlow = Color(0xFFA8D957);
  static const Color speedModerate = Color(0xFFE5C73F);
  static const Color speedFast = Color(0xFFEC8A3D);
  static const Color speedExtreme = Color(0xFFE65656);

  /// Tissue saturation ramp: (percent of M-value, colour), ascending.
  static const List<(double, Color)> tissueRamp = [
    (0.0, Color(0xFF1E3A8A)), // deep blue
    (40.0, Color(0xFF3B82F6)), // blue
    (70.0, Color(0xFF06B6D4)), // cyan
    (85.0, Color(0xFF22C55E)), // green
    (95.0, Color(0xFFFACC15)), // yellow
    (100.0, Color(0xFFF97316)), // orange
    (115.0, Color(0xFFDC2626)), // red
  ];

  // Pins drawn on map tiles, which do not follow the theme.
  static const Color mapPin = Color(0xFFF44336);
  static const Color mapPinMuted = Color(0xFF8B3A3A);

  /// The data colours drawn as thin lines on a chart card, by name. Used
  /// by tests to check each stays readable on every theme's card.
  static const Map<String, Color> lineColors = {
    'waterTemp': waterTemp,
    'gf99': gf99,
    'ceiling': ceiling,
    'speedCalm': speedCalm,
    'speedSlow': speedSlow,
    'speedModerate': speedModerate,
    'speedFast': speedFast,
    'speedExtreme': speedExtreme,
    'tank0': Color(0xFF80DEEA),
    'tank1': Color(0xFFFFAB91),
    'tank2': Color(0xFFCE93D8),
    'tank3': Color(0xFFB0BEC5),
    'tank4': Color(0xFFA5D6A7),
    'tank5': Color(0xFFFFE082),
  };
}
