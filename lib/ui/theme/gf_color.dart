import 'package:flutter/material.dart';

/// Colour for a gradient-factor readout, banded by severity. Shared by the
/// dive-detail stat tiles and the profile crosshair so GF readouts speak one
/// colour language from one definition.
///
/// [gfHigh] is the dive's configured GF-high (defaults to 85). Boundaries
/// match the long-standing dive-detail behaviour: `gf == gfHigh` is still
/// green, `gf == 100` is still amber.
Color gfBandColor(double gf, {double gfHigh = 85}) {
  if (gf > 100) return const Color(0xFFDC2626); // red — supersaturated
  if (gf > gfHigh) return const Color(0xFFF59E0B); // amber — over GF-high
  return const Color(0xFF4ADE80); // green — within limits
}
