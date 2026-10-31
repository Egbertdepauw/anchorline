/// Maximum operating depth (MOD) and minimum breathable depth for a gas.
///
/// Pure Dart, no Flutter imports. Both use the seawater convention of
/// 10 m per bar with 1 bar at the surface, which is what divers and the
/// rest of the app's planning numbers use:
///
///   MOD(m)       = (ppO2Max / fO2 − 1) × 10
///   minDepth(m)  = (ppO2Min / fO2 − 1) × 10
///
/// `fO2` is always a FRACTION (0–1), never a percentage.
library;

/// Default lowest ppO2 (bar) treated as breathable for [minDepthMeters].
const double kMinBreathablePpo2 = 0.16;

/// Maximum operating depth in metres of seawater for a gas with oxygen
/// fraction [fO2] at the ppO2 limit [ppO2] (bar).
///
/// Returns [double.infinity] when [fO2] ≤ 0 (or is NaN): a gas without
/// oxygen never reaches any ppO2 limit. Callers that can't show an
/// unbounded MOD should guard with `isFinite`.
///
/// The result can be negative when [ppO2] is below [fO2] (e.g. pure O2 at
/// a 0.9 bar limit); that means the gas exceeds the limit at the surface.
double modMeters(double fO2, double ppO2) {
  if (!(fO2 > 0)) return double.infinity;
  return (ppO2 / fO2 - 1.0) * 10.0;
}

/// Shallowest depth in metres of seawater at which a gas with oxygen
/// fraction [fO2] reaches the breathable ppO2 floor [ppO2Min] (bar,
/// default [kMinBreathablePpo2] = 0.16).
///
/// A result ≤ 0 means the gas is breathable at the surface; callers
/// should then show "surface" rather than a depth. Only hypoxic mixes
/// (fO2 < ppO2Min) give a positive value.
///
/// Returns [double.infinity] when [fO2] ≤ 0 (or is NaN): a gas without
/// oxygen is never breathable.
double minDepthMeters(double fO2, {double ppO2Min = kMinBreathablePpo2}) {
  if (!(fO2 > 0)) return double.infinity;
  return (ppO2Min / fO2 - 1.0) * 10.0;
}
