import 'package:flutter/material.dart';

import 'safety_colors.dart';

/// Colour for a gradient-factor readout, banded by severity. Shared by the
/// dive-detail stat tiles and the profile crosshair so GF readouts speak one
/// colour language from one definition.
///
/// [gfHigh] is the dive's configured GF-high (defaults to 85). Boundaries
/// match the long-standing dive-detail behaviour: `gf == gfHigh` is still
/// green, `gf == 100` is still amber.
Color gfBandColor(double gf, {double gfHigh = 85}) {
  if (gf > 100) return SafetyColors.gfOverLimit; // red — supersaturated
  if (gf > gfHigh) return SafetyColors.gfOverHigh; // amber — over GF-high
  return SafetyColors.gfWithinLimits; // green — within limits
}
