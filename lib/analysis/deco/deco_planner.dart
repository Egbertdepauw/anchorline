/// Bühlmann ZH-L16C + Erik-Baker-GF deco planner. Pure function over an
/// initial tissue state + ambient model. Output: every leg of the ascent
/// from the trigger depth to the surface, including all 3m holds. No
/// gas-volume math here — that lives in the bailout layer.
library;

import 'dart:math';

import '../../data/models/dive.dart' show DiveGasMix;
import 'deco_step.dart';
import 'gas_pressures.dart';
import 'schreiner.dart';
import 'tissue_model.dart';

const double _surfaceAtmBar = 1.013;

/// Returns the list of [DecoStep]s the diver must execute to surface safely.
/// An empty list means no deco was required (straight ascent acceptable).
///
/// [initialN2Bar], [initialHeBar]: 16-element lists, tissue pressures at the
///   trigger point (bar).
/// [triggerDepthMeters]: depth (m) the diver was at when bailout was triggered.
/// [gases]: bottom-mix-first, deco gases follow in ascending O2 %.
/// [gfLow], [gfHigh]: gradient factors (1..100).
/// [ascentRateFastMPerMin]: m/min from trigger depth to first stop.
/// [ascentRateSlowMPerMin]: m/min between stops.
/// [ppo2LimitBottom]: max PPO2 allowed for the bottom-mix selection (typ 1.6).
/// [ppo2LimitDeco]: max PPO2 allowed when switching to a deco gas (1.6 / 1.4).
List<DecoStep> planDeco({
  required List<double> initialN2Bar,
  required List<double> initialHeBar,
  required double triggerDepthMeters,
  required List<DiveGasMix> gases,
  required int gfLow,
  required int gfHigh,
  required int ascentRateFastMPerMin,
  required int ascentRateSlowMPerMin,
  required double ppo2LimitBottom,
  required double ppo2LimitDeco,
}) {
  assert(initialN2Bar.length == 16);
  assert(initialHeBar.length == 16);
  assert(gases.isNotEmpty);

  // ── Phase 1: find first stop depth ────────────────────────────────────
  // Walk a scratch copy of the tissues up at the FAST ascent rate in 1m
  // steps. At each metre, after advancing the tissues, check whether the
  // GF-Low ceiling breaches the depth we'd be at next minute. The deepest
  // metre where that happens is the deepest legal stop; round up to a 3m
  // multiple.
  final pN2 = List<double>.from(initialN2Bar);
  final pHe = List<double>.from(initialHeBar);
  final gfLowFrac = gfLow / 100.0;

  double depth = triggerDepthMeters;
  while (depth > 0) {
    final nextDepth = max(0.0, depth - 1.0);
    final gas = _bestGasAt(
      gases: gases,
      depthMeters: depth,
      ppo2Limit: ppo2LimitBottom,
    );
    final avgAmbient = _surfaceAtmBar + (depth + nextDepth) / 20.0;
    final secs = (1.0 / ascentRateFastMPerMin * 60).round();
    _advanceOneStep(
      pN2: pN2,
      pHe: pHe,
      gas: gas,
      ambientBar: avgAmbient,
      intervalSeconds: secs,
    );
    final ceiling = _ceilingMetersFor(
      pN2: pN2,
      pHe: pHe,
      gfFraction: gfLowFrac,
    );
    if (ceiling > nextDepth) break;
    depth = nextDepth;
  }

  final firstStopDepth =
      depth <= 0 ? 0.0 : ((depth / 3).ceil() * 3).toDouble();
  if (firstStopDepth == 0) return const []; // NDL — no deco required.

  // ── Phase 2: walk from the trigger depth with clean tissues ───────────
  // Phase 1 mutated pN2/pHe just to find the breach; re-initialise so the
  // recorded steps reflect actual breathing from the trigger forward.
  for (var c = 0; c < 16; c++) {
    pN2[c] = initialN2Bar[c];
    pHe[c] = initialHeBar[c];
  }

  final steps = <DecoStep>[];

  // Phase 2a: trigger → first stop, fast rate, 1m / step.
  double currentDepth = triggerDepthMeters;
  while (currentDepth > firstStopDepth) {
    final nextDepth = max(firstStopDepth, currentDepth - 1.0);
    // Pick gas safe at the deepest point of the leg (currentDepth).
    final gas = _bestGasAt(
      gases: gases,
      depthMeters: currentDepth,
      ppo2Limit: ppo2LimitBottom,
    );
    final avgAmbient = _surfaceAtmBar + (currentDepth + nextDepth) / 20.0;
    final secs =
        ((currentDepth - nextDepth) / ascentRateFastMPerMin * 60).round();
    _advanceOneStep(
      pN2: pN2,
      pHe: pHe,
      gas: gas,
      ambientBar: avgAmbient,
      intervalSeconds: secs,
    );
    steps.add(DecoStep(
      depthStartMeters: currentDepth,
      depthEndMeters: nextDepth,
      duration: Duration(seconds: secs),
      gas: gas,
    ));
    currentDepth = nextDepth;
  }

  // Phase 2b: 3m stop ladder. At each stop, hold until the ceiling clears
  // the next stop depth under the linearly-interpolated GF, then ascend
  // one 3m increment at the slow rate.
  const stopStepSec = 60;
  const stopSafetyCap = 600; // 10h per stop — runaway protection.
  while (currentDepth > 0) {
    final nextStop = max(0.0, currentDepth - 3.0);
    final gfFractionHere = _gfAt(
      currentDepth: currentDepth,
      firstStopDepth: firstStopDepth,
      gfLow: gfLow,
      gfHigh: gfHigh,
    );
    final stopGas = _bestGasAt(
      gases: gases,
      depthMeters: currentDepth,
      ppo2Limit: ppo2LimitDeco,
    );

    var minutesHeld = 0;
    while (minutesHeld < stopSafetyCap) {
      final ceiling = _ceilingMetersFor(
        pN2: pN2,
        pHe: pHe,
        gfFraction: gfFractionHere,
      );
      if (ceiling <= nextStop + 1e-6) break;
      final ambient = _surfaceAtmBar + currentDepth / 10.0;
      _advanceOneStep(
        pN2: pN2,
        pHe: pHe,
        gas: stopGas,
        ambientBar: ambient,
        intervalSeconds: stopStepSec,
      );
      minutesHeld++;
    }
    if (minutesHeld > 0) {
      steps.add(DecoStep(
        depthStartMeters: currentDepth,
        depthEndMeters: currentDepth,
        duration: Duration(minutes: minutesHeld),
        gas: stopGas,
      ));
    }

    if (nextStop < currentDepth) {
      // Gate gas selection by the deepest point of the leg, not midpoint —
      // ensures the breathed gas is safe at every depth on the way up.
      final ascentGas = _bestGasAt(
        gases: gases,
        depthMeters: currentDepth,
        ppo2Limit: ppo2LimitDeco,
      );
      final secs =
          ((currentDepth - nextStop) / ascentRateSlowMPerMin * 60).round();
      final avgAmbient = _surfaceAtmBar + (currentDepth + nextStop) / 20.0;
      _advanceOneStep(
        pN2: pN2,
        pHe: pHe,
        gas: ascentGas,
        ambientBar: avgAmbient,
        intervalSeconds: secs,
      );
      steps.add(DecoStep(
        depthStartMeters: currentDepth,
        depthEndMeters: nextStop,
        duration: Duration(seconds: secs),
        gas: ascentGas,
      ));
    }
    currentDepth = nextStop;
  }

  return steps;
}

/// Worst-compartment ceiling in metres at the given tissue state and GF.
/// Erik-Baker GF reduction of the Bühlmann M-line.
double _ceilingMetersFor({
  required List<double> pN2,
  required List<double> pHe,
  required double gfFraction,
}) {
  double worst = 0.0;
  for (var c = 0; c < 16; c++) {
    final totalLoad = pN2[c] + pHe[c];
    final tn2 = pN2[c] / max(totalLoad, 1e-9);
    final tHe = 1.0 - tn2;
    final a = zhl16cTissues[c].aN2 * tn2 + zhl16cTissues[c].aHe * tHe;
    final b = zhl16cTissues[c].bN2 * tn2 + zhl16cTissues[c].bHe * tHe;
    // Erik Baker: P_amb_tol = (P_t − a·GF) × b / (b + GF·(1 − b))
    // Equivalent to b(1−GF) + GF. The "1 − GF + GF·b" form some sources
    // print is the *swap* — it gives GF=30 and GF=70 reversed ceilings.
    final denom = b + gfFraction * (1.0 - b);
    final pAmbTol = (totalLoad - a * gfFraction) * b / denom;
    final ceilingMeters = (pAmbTol - _surfaceAtmBar) * 10.0;
    if (ceilingMeters > worst) worst = ceilingMeters;
  }
  return worst;
}

/// Pick the richest gas in [gases] with PPO2 ≤ [ppo2Limit] at [depthMeters].
/// Falls back to gases.first if nothing qualifies — caller is expected to
/// have prepended a depth-safe bottom mix already.
DiveGasMix _bestGasAt({
  required List<DiveGasMix> gases,
  required double depthMeters,
  required double ppo2Limit,
}) {
  final ambient = _surfaceAtmBar + depthMeters / 10.0;
  DiveGasMix best = gases.first;
  for (final m in gases) {
    final ppo2 = (m.oxygenPercent / 100.0) * ambient;
    if (ppo2 > ppo2Limit) continue;
    if (m.oxygenPercent > best.oxygenPercent) best = m;
  }
  return best;
}

/// Linear GF interpolation between (firstStopDepth, gfLow) and (0m, gfHigh).
double _gfAt({
  required double currentDepth,
  required double firstStopDepth,
  required int gfLow,
  required int gfHigh,
}) {
  if (firstStopDepth <= 0) return gfHigh / 100.0;
  final frac =
      ((firstStopDepth - currentDepth) / firstStopDepth).clamp(0.0, 1.0);
  return (gfLow + (gfHigh - gfLow) * frac) / 100.0;
}

/// Advance all 16 N2/He compartments [intervalSeconds] at [ambientBar] on [gas].
void _advanceOneStep({
  required List<double> pN2,
  required List<double> pHe,
  required DiveGasMix gas,
  required double ambientBar,
  required int intervalSeconds,
}) {
  final (paN2, paHe) = inertPartialPressures(
    ambientBar: ambientBar,
    mix: gas,
    setpointBar: 0.0,
  );
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
