/// Bailout ascent simulator (v1 — ZHL-16C / Bühlmann GF).
///
/// Given a trigger point on a dive (depth + current tissue state) and a list
/// of available OC bailout gases, walks an open-circuit ascent in 1-minute
/// timesteps using the Schreiner equation.  At each step it checks whether
/// the GF at the *target* depth would exceed gfHigh; if so, the diver holds
/// at the current depth for one minute (a deco stop) instead of ascending.
/// Gas switches happen when a richer mix can be breathed at ≤ 1.6 bar PPO2.
///
/// v1 goals: plausible output that responds to settings.  No bubble
/// algorithms, no stop-time consolidation, no GF-slope interpolation.
library;

import 'dart:math';

import '../../data/models/dive.dart' show DiveGasMix;
import '../deco/schreiner.dart';
import '../deco/tissue_model.dart';

// ---------------------------------------------------------------------------
// Public data types
// ---------------------------------------------------------------------------

/// A single leg of the ascent plan: either a flat deco stop
/// (depthStart == depthEnd) or a moving ascent segment.
class AscentStop {
  final double depthStartMeters;
  final double depthEndMeters;
  final Duration duration;
  final DiveGasMix gas;
  final double volumeLitresConsumed;

  const AscentStop({
    required this.depthStartMeters,
    required this.depthEndMeters,
    required this.duration,
    required this.gas,
    required this.volumeLitresConsumed,
  });

  /// True when this leg is a flat deco hold.
  bool get isStop => depthStartMeters == depthEndMeters;
}

/// The full ascent plan returned by [simulateAscent].
class AscentPlan {
  /// All legs of the ascent — flat stops + moving segments.
  final List<AscentStop> stops;

  /// Total ascent time across all legs.
  final Duration totalTime;

  /// Gas consumption keyed by mix.  The sum of values equals the sum of
  /// [AscentStop.volumeLitresConsumed] across all [stops].
  final Map<DiveGasMix, double> volumeByGas;

  const AscentPlan({
    required this.stops,
    required this.totalTime,
    required this.volumeByGas,
  });
}

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const double _waterVapourBar = 0.0627;
const double _surfaceAtmBar = 1.013;

/// Safety cap: abort after this many iterations to prevent infinite loops in
/// degenerate cases (e.g. tissue loading so high GF99 never drops below gfHigh).
const int _maxIterations = 300;

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Simulate an open-circuit bailout ascent from [triggerDepthMeters].
///
/// Parameters
/// ----------
/// [triggerDepthMeters]  Depth at which the diver bails out (metres).
/// [initialN2Bar]        16-element list — N2 tissue loads at trigger point (bar).
/// [initialHeBar]        16-element list — He tissue loads at trigger point (bar).
/// [availableGases]      Bailout gases.  First element is the bottom mix; the
///                       rest are deco gases in any order (the function will
///                       always pick the richest mix usable at each depth).
/// [gfLow]               Low gradient factor (1–100).
/// [gfHigh]              High gradient factor (1–100).  Ascent stops when GF99
///                       at the target depth would exceed this.
/// [ascentRateFast]      m/min — used from trigger depth down to the slowdown
///                       point.
/// [ascentRateSlow]      m/min — used from the slowdown point to the surface.
/// [sacBottom]           L/min — used from trigger depth to the first deco stop.
/// [sacDeco]             L/min — used at all deco stops and the final ascent.
AscentPlan simulateAscent({
  required double triggerDepthMeters,
  required List<double> initialN2Bar,
  required List<double> initialHeBar,
  required List<DiveGasMix> availableGases,
  required int gfLow,
  required int gfHigh,
  required int ascentRateFast,
  required int ascentRateSlow,
  required int sacBottom,
  required int sacDeco,
}) {
  assert(initialN2Bar.length == 16, 'initialN2Bar must have 16 elements');
  assert(initialHeBar.length == 16, 'initialHeBar must have 16 elements');
  assert(availableGases.isNotEmpty, 'availableGases must not be empty');

  final pN2 = List<double>.from(initialN2Bar);
  final pHe = List<double>.from(initialHeBar);
  double currentDepth = triggerDepthMeters;

  final stops = <AscentStop>[];
  final volumeByGas = <DiveGasMix, double>{};
  var totalTime = Duration.zero;

  // ------------------------------------------------------------------
  // Determine the slowdown depth.
  //
  // The diver descends fast from trigger depth to the slowdown point,
  // then switches to the slow rate.  Slowdown is the deeper of:
  //   - half-pressure depth: (triggerDepth - 10) / 2
  //   - first-switch depth: deepest MOD (at PPO2 ≤ 1.6) of deco gases
  // ------------------------------------------------------------------
  final halfPressureDepth =
      ((triggerDepthMeters - 10.0) / 2.0).clamp(0.0, triggerDepthMeters);
  final firstSwitchDepth = _findFirstSwitchDepth(availableGases);
  final slowdownDepth = max(halfPressureDepth, firstSwitchDepth);

  bool reachedDecoZone = false;
  int iterations = 0;

  while (currentDepth > 0.0 && iterations < _maxIterations) {
    iterations++;

    // Gas switch: pick richest available mix usable at this depth (PPO2 ≤ 1.6).
    final currentGas = _bestGasForDepth(availableGases, currentDepth);

    final ascentRate =
        currentDepth > slowdownDepth ? ascentRateFast : ascentRateSlow;
    final sac = reachedDecoZone ? sacDeco : sacBottom;
    const stepDurationMin = 1.0;
    const stepSeconds = 60;

    final targetDepth = max(0.0, currentDepth - ascentRate * stepDurationMin);

    // Load tissues for one minute at currentDepth.  We always load at the
    // current position first; the GF check then decides whether we can ascend.
    // This is conservative: tissue loading during the actual ascent leg is
    // modelled at the average depth, which would be slightly less than
    // currentDepth — but using currentDepth keeps the arithmetic simple and
    // errs on the safe side.
    final holdAmbient = _surfaceAtmBar + currentDepth / 10.0;
    _loadTissuesOneStep(pN2, pHe, currentGas, holdAmbient, stepSeconds);

    // After loading, check GF99 at the target depth.  If it exceeds gfHigh
    // the diver stays at currentDepth (the minute already counted as a hold).
    final gf99atTarget = _computeGf99AtDepth(pN2, pHe, targetDepth);

    if (gf99atTarget > gfHigh) {
      // Deco stop: stay at currentDepth.
      reachedDecoZone = true;
      final volumeL = sac * holdAmbient * stepDurationMin;

      volumeByGas[currentGas] = (volumeByGas[currentGas] ?? 0.0) + volumeL;
      stops.add(AscentStop(
        depthStartMeters: currentDepth,
        depthEndMeters: currentDepth,
        duration: const Duration(seconds: stepSeconds),
        gas: currentGas,
        volumeLitresConsumed: volumeL,
      ));
      totalTime += const Duration(seconds: stepSeconds);
      // currentDepth does NOT change.
    } else {
      // Ascend.  Volume uses the average pressure of the leg.
      final avgAmbient = (_surfaceAtmBar + currentDepth / 10.0 +
              _surfaceAtmBar + targetDepth / 10.0) /
          2.0;
      final volumeL = sac * avgAmbient * stepDurationMin;

      volumeByGas[currentGas] = (volumeByGas[currentGas] ?? 0.0) + volumeL;
      stops.add(AscentStop(
        depthStartMeters: currentDepth,
        depthEndMeters: targetDepth,
        duration: const Duration(seconds: stepSeconds),
        gas: currentGas,
        volumeLitresConsumed: volumeL,
      ));
      totalTime += const Duration(seconds: stepSeconds);
      currentDepth = targetDepth;
    }
  }

  return AscentPlan(
    stops: stops,
    totalTime: totalTime,
    volumeByGas: volumeByGas,
  );
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

/// Returns the richest (highest fO2) gas from [available] whose PPO2 at
/// [depthMeters] is ≤ 1.6 bar.  Falls back to the first gas (bottom mix)
/// if nothing else qualifies.
DiveGasMix _bestGasForDepth(List<DiveGasMix> available, double depthMeters) {
  final ambient = _surfaceAtmBar + depthMeters / 10.0;
  DiveGasMix best = available.first;
  for (final mix in available) {
    final ppo2 = (mix.oxygenPercent / 100.0) * ambient;
    if (ppo2 > 1.6) continue;
    if (mix.oxygenPercent > best.oxygenPercent) {
      best = mix;
    }
  }
  return best;
}

/// Returns the deepest MOD (PPO2 ≤ 1.6) of all deco gases (gases[1..]).
/// If there are no deco gases, returns 0.
double _findFirstSwitchDepth(List<DiveGasMix> gases) {
  double deepest = 0.0;
  for (var i = 1; i < gases.length; i++) {
    final fO2 = gases[i].oxygenPercent / 100.0;
    if (fO2 <= 0.0) continue;
    final modBar = 1.6 / fO2;
    final modM = (modBar - _surfaceAtmBar) * 10.0;
    if (modM > deepest) deepest = modM;
  }
  return deepest;
}

/// Advances all 16 N2 + He tissue compartments by [intervalSeconds] seconds
/// while breathing [gas] at [ambientBar].
void _loadTissuesOneStep(
  List<double> pN2,
  List<double> pHe,
  DiveGasMix gas,
  double ambientBar,
  int intervalSeconds,
) {
  final fO2 = gas.oxygenPercent / 100.0;
  final fHe = gas.heliumPercent / 100.0;
  final fN2 = 1.0 - fO2 - fHe;
  final paN2 = (ambientBar - _waterVapourBar) * fN2;
  final paHe = (ambientBar - _waterVapourBar) * fHe;

  for (var c = 0; c < 16; c++) {
    pN2[c] = loadCompartment(
      currentLoadBar: pN2[c],
      inertGasPartialPressureBar: paN2,
      halfTimeMin: zhl16cTissues[c].halfTimeN2Min,
      intervalSeconds: intervalSeconds,
    );
    pHe[c] = loadCompartment(
      currentLoadBar: pHe[c],
      inertGasPartialPressureBar: paHe,
      halfTimeMin: zhl16cTissues[c].halfTimeHeMin,
      intervalSeconds: intervalSeconds,
    );
  }
}

/// Computes the worst-compartment GF99 evaluated at [depthMeters].
///
/// Follows the same M-value formula as zhl16c.dart:
///   a = aN2*tn2 + aHe*(1-tn2)
///   b = bN2*tn2 + bHe*(1-tn2)
///   M_at_depth = a + ambient/b
///   GF = (load - ambient) / (M - ambient) × 100
double _computeGf99AtDepth(
  List<double> pN2,
  List<double> pHe,
  double depthMeters,
) {
  final ambient = _surfaceAtmBar + depthMeters / 10.0;
  double worst = 0.0;

  for (var c = 0; c < 16; c++) {
    final totalLoad = pN2[c] + pHe[c];
    final tn2 = pN2[c] / max(totalLoad, 1e-9);
    final thHe = 1.0 - tn2;

    final a = zhl16cTissues[c].aN2 * tn2 + zhl16cTissues[c].aHe * thHe;
    final b = zhl16cTissues[c].bN2 * tn2 + zhl16cTissues[c].bHe * thHe;

    final mAtDepth = a + ambient / b;
    final allowed = mAtDepth - ambient;
    final supersat = totalLoad - ambient;

    final gf = allowed > 0.0 ? (supersat / allowed) * 100.0 : 0.0;
    if (gf > worst) worst = gf;
  }

  return worst;
}
