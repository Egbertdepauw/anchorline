/// VPM-B-style conservatism level constants. v1 implementation uses a
/// linear interpolation between two GF-equivalent endpoints:
///
/// - Conservatism 0: allowed gradient ≈ M-value × 1.0 (no reduction —
///   near-Bühlmann limits, very permissive)
/// - Conservatism 4: allowed gradient ≈ M-value × 0.5 (50% reduction —
///   very conservative)
///
/// Levels 1, 2, 3 linearly interpolate. Conservatism 2 (the default)
/// gives ~0.75 of the Bühlmann gradient.
///
/// This is a v1 approximation. A faithful VPM-B port involves bubble
/// nucleation radii regenerated per ascent phase; we'll layer that on
/// later if/when divergence from Subsurface's VPM-B becomes a problem
/// in practice.
library;

double vpmbGradientFactor(int conservatism) {
  final clamped = conservatism.clamp(0, 4);
  // Level 0 = 1.0, level 4 = 0.5, linear in between.
  return 1.0 - (clamped / 4.0) * 0.5;
}
