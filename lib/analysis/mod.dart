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

/// Slack, in metres, [floorDepthTolerant] adds before it floors.
///
/// [modMeters] works in doubles, so an exact whole-metre MOD can come out a
/// hair low: 20 % at 1.4 bar is `59.99999999999999`, not 60. A plain
/// `floor()` would print 59 m for a gas whose MOD is exactly 60 m.
///
/// 1e-6 m is far above that noise (about 1e-14) and far below any genuine
/// fraction. With O2 in 0.1 % steps and ppO2 in 0.01 bar steps a MOD
/// is `100 * p / k - 10` for integers p and k ≤ 1000, so a MOD that is not
/// a whole number of metres is at least `1 / k` (≥ 1e-3 m) from the next
/// metre and is never lifted over it.
const double kDepthFloorToleranceMeters = 1e-6;

/// [meters] floored to whole metres, tolerating floating-point noise just
/// under a whole metre (see [kDepthFloorToleranceMeters]). Use this, never a
/// bare `floor()`, wherever a MOD is shown as whole metres: the analyzer
/// screen and the cylinder label share it so they always agree.
///
/// Floors, never rounds: a limit shown as too deep is the unsafe direction.
/// [meters] must be finite, like [double.floor]; guard with `isFinite`
/// first (see [modMeters]).
int floorDepthTolerant(double meters) =>
    (meters + kDepthFloorToleranceMeters).floor();

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
