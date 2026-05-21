import 'package:flutter/material.dart';

/// Anchorline brand palette — single source of truth for the four
/// brand colours called out in the design spec. Used both directly
/// (logo widget, launcher-icon config) and indirectly via tokens.dart
/// (the theme's `accentPrimary` references [reelOrange]).
class AnchorlineColors {
  AnchorlineColors._();

  /// Primary dark surface / icon background.
  static const Color hullBlack = Color(0xFF0A1419);

  /// Primary accent — buoy, line, flukes; the call-to-action colour.
  static const Color reelOrange = Color(0xFFC97B3A);

  /// Anchor body / light foreground — high-contrast on dark surfaces.
  static const Color surfaceWhite = Color(0xFFE4E9E6);

  /// Secondary accent — informational / nautical metal.
  static const Color slackSteel = Color(0xFF3A6477);
}
