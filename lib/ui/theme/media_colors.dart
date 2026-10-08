import 'package:flutter/material.dart';

/// Neutral colours around photos and documents. A photo or PDF viewer is
/// black whatever the theme, and controls drawn over a photo sit on a
/// dark scrim. These do not follow the theme.
class MediaColors {
  MediaColors._();

  static const Color viewerBackground = Color(0xFF000000);
  static const Color viewerForeground = Color(0xFFFFFFFF);

  /// Icons and text drawn on a [scrim].
  static const Color onScrim = Color(0xFFFFFFFF);

  /// A black scrim over media at [opacity] (0 to 1).
  static Color scrim(double opacity) =>
      const Color(0xFF000000).withValues(alpha: opacity);
}
