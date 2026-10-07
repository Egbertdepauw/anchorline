import 'package:flutter/material.dart';

import 'omarchy_colors.dart';

/// Omarchy "Miasma" — themes/miasma/colors.toml, read 2026-10-06.
/// Green and blue (an olive) are too close, so cells keep the Wreck
/// colours. Its dark and light foregrounds are too dim for body text; the
/// mapping lifts them.
const OmarchyColors miasmaColors = OmarchyColors(
  accent: Color(0xFF78824B),
  selection: Color(0xFF383838),
  muted: Color(0xFF666666),
  background: Color(0xFF222222),
  darkBackground: Color(0xFF191919),
  darkerBackground: Color(0xFF121212),
  lighterBackground: Color(0xFF2C2C2C),
  foreground: Color(0xFFC2C2B0),
  darkForeground: Color(0xFF555555),
  lightForeground: Color(0xFF8A8A7E),
  brightForeground: Color(0xFFC2C2B0),
  red: Color(0xFF685742),
  yellow: Color(0xFFB36D43),
  orange: Color(0xFF8D6242),
  green: Color(0xFF5F875F),
  cyan: Color(0xFFC9A554),
  blue: Color(0xFF78824B),
  magenta: Color(0xFFBB7744),
  brown: Color(0xFF463121),
  brightRed: Color(0xFF685742),
  brightYellow: Color(0xFFB36D43),
  brightGreen: Color(0xFF5F875F),
  brightCyan: Color(0xFFC9A554),
  brightBlue: Color(0xFF78824B),
  brightMagenta: Color(0xFFBB7744),
  useOwnCellColors: false,
  useOwnPpo2Color: true,
);
