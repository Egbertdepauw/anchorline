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
  // CCR: when > 0.1, the diver is on the loop. Inert pp values fall to
  // (ambient - waterVapour - setpoint) × dilInerts/Σ-inerts instead of
  // gas-fraction-times-inhaled — same lever the replay engine uses.
  // 0 (default) = open circuit, original bailout behaviour.
  double setpointBar = 0.0,
  // Where deco "ends" — the diver surfaces directly from this stop
  // rather than continuing to 3 m. Time at this stop extends to compensate.
  // Default 3.0 = original behaviour.
  double lastStopDepthMeters = 3.0,
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
    final gas = _bestGasAtSwitchDepth(gases: gases, depthMeters: depth);
    final avgAmbient = _surfaceAtmBar + (depth + nextDepth) / 20.0;
    final secs = (1.0 / ascentRateFastMPerMin * 60).round();
    _advanceOneStep(
      pN2: pN2,
      pHe: pHe,
      gas: gas,
      ambientBar: avgAmbient,
      intervalSeconds: secs,
      setpointBar: setpointBar,
    );
    final ceiling = _ceilingMetersFor(
      pN2: pN2,
      pHe: pHe,
      gfFraction: gfLowFrac,
    );
    if (ceiling > nextDepth) break;
    depth = nextDepth;
  }

  // Round up to a 3 m stop. Then clamp: if the user wants their last
  // stop at e.g. 6 m, a borderline dive whose deepest stop would have
  // been 3 m must surface from 6 m instead (the extra time gets
  // absorbed at the deeper hold). Phase 1 still returns 0 for true
  // NDL — no stop emitted at all in that case.
  var firstStopDepth =
      depth <= 0 ? 0.0 : ((depth / 3).ceil() * 3).toDouble();
  if (firstStopDepth == 0) return const []; // NDL — no deco required.
  if (firstStopDepth < lastStopDepthMeters) {
    firstStopDepth = lastStopDepthMeters;
  }

  // ── Phase 2: walk from the trigger depth with clean tissues ───────────
  // Phase 1 mutated pN2/pHe just to find the breach; re-initialise so the
  // recorded steps reflect actual breathing from the trigger forward.
  for (var c = 0; c < 16; c++) {
    pN2[c] = initialN2Bar[c];
    pHe[c] = initialHeBar[c];
  }

  final steps = <DecoStep>[];

  // The most recently breathed gas. Used to detect gas-change events as
  // the diver ascends through successive switch depths — every such
  // change emits a flat 1-minute hold at the switch depth before the
  // ascent continues, matching standard tech-diving practice.
  // Initialised to whatever gas the diver was on at trigger (the same
  // gas the planner would pick at trigger depth), so the first iteration
  // never fires a spurious hold.
  DiveGasMix prevGas = _bestGasAtSwitchDepth(
    gases: gases,
    depthMeters: triggerDepthMeters,
  );
  const switchHoldSec = 60;

  // Phase 2a: trigger → first stop, fast rate, 1m / step.
  double currentDepth = triggerDepthMeters;
  while (currentDepth > firstStopDepth) {
    final nextDepth = max(firstStopDepth, currentDepth - 1.0);
    final gas =
        _bestGasAtSwitchDepth(gases: gases, depthMeters: currentDepth);
    // Gas switch detected — emit a 1-min flat hold at this depth on
    // the new gas BEFORE continuing the ascent. Advance the tissue
    // model the same minute.
    if (gas != prevGas) {
      final ambient = _surfaceAtmBar + currentDepth / 10.0;
      _advanceOneStep(
        pN2: pN2,
        pHe: pHe,
        gas: gas,
        ambientBar: ambient,
        intervalSeconds: switchHoldSec,
        setpointBar: setpointBar,
      );
      steps.add(DecoStep(
        depthStartMeters: currentDepth,
        depthEndMeters: currentDepth,
        duration: const Duration(seconds: switchHoldSec),
        gas: gas,
      ));
    }
    final avgAmbient = _surfaceAtmBar + (currentDepth + nextDepth) / 20.0;
    final secs =
        ((currentDepth - nextDepth) / ascentRateFastMPerMin * 60).round();
    _advanceOneStep(
      pN2: pN2,
      pHe: pHe,
      gas: gas,
      ambientBar: avgAmbient,
      intervalSeconds: secs,
      setpointBar: setpointBar,
    );
    steps.add(DecoStep(
      depthStartMeters: currentDepth,
      depthEndMeters: nextDepth,
      duration: Duration(seconds: secs),
      gas: gas,
    ));
    prevGas = gas;
    currentDepth = nextDepth;
  }

  // Phase 2b: 3m stop ladder. At each stop, hold until the ceiling clears
  // the next stop depth under the linearly-interpolated GF, then ascend
  // one 3m increment at the slow rate.
  const stopStepSec = 60;
  const stopSafetyCap = 600; // 10h per stop — runaway protection.

  while (currentDepth > 0) {
    final candidateNext = currentDepth - 3.0;
    // Skip stops that fall *between* the user's chosen last-stop depth
    // and the surface — go straight up from the last allowed stop. The
    // hold at the previous stop naturally extends because the ceiling
    // has to clear 0 m instead of the next 3 m increment.
    final nextStop =
        candidateNext < lastStopDepthMeters && candidateNext > 0
            ? 0.0
            : max(0.0, candidateNext);
    final gfFractionHere = _gfAt(
      currentDepth: currentDepth,
      firstStopDepth: firstStopDepth,
      lastStopDepth: lastStopDepthMeters,
      gfLow: gfLow,
      gfHigh: gfHigh,
    );
    final stopGas =
        _bestGasAtSwitchDepth(gases: gases, depthMeters: currentDepth);
    // A gas change is happening at this stop boundary when stopGas
    // differs from whatever the diver was last breathing. Even on
    // a stop the deco planner wouldn't otherwise hold at (ceiling
    // already clears next stop), we force a minimum 1-minute hold
    // here for the reg swap.
    final isGasSwitchStop = stopGas != prevGas;

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
        setpointBar: setpointBar,
      );
      minutesHeld++;
    }
    if (isGasSwitchStop && minutesHeld == 0) {
      // Force a 1-minute gas-switch hold even though deco didn't
      // ask for one. Advance the tissue model the same minute.
      final ambient = _surfaceAtmBar + currentDepth / 10.0;
      _advanceOneStep(
        pN2: pN2,
        pHe: pHe,
        gas: stopGas,
        ambientBar: ambient,
        intervalSeconds: stopStepSec,
        setpointBar: setpointBar,
      );
      minutesHeld = 1;
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
      final ascentGas =
          _bestGasAtSwitchDepth(gases: gases, depthMeters: currentDepth);
      final secs =
          ((currentDepth - nextStop) / ascentRateSlowMPerMin * 60).round();
      final avgAmbient = _surfaceAtmBar + (currentDepth + nextStop) / 20.0;
      _advanceOneStep(
        pN2: pN2,
        pHe: pHe,
        gas: ascentGas,
        ambientBar: avgAmbient,
        intervalSeconds: secs,
        setpointBar: setpointBar,
      );
      steps.add(DecoStep(
        depthStartMeters: currentDepth,
        depthEndMeters: nextStop,
        duration: Duration(seconds: secs),
        gas: ascentGas,
      ));
    }
    prevGas = stopGas;
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

/// Standard "switch to this gas at this depth" table — GUE / tech-diving
/// convention, rounded conservatively to 3 m stop boundaries.
///
/// These are NOT raw MOD@1.6 values. They are ascent-side switch points
/// that the diver memorises and applies, often a metre or two shallower
/// than the gas's theoretical MOD so the switch lands on a stop the
/// deco planner would emit anyway.
///
/// The bailout planner uses these to (a) decide which gas to breathe at
/// each ascent depth and (b) emit a flat 1-minute hold every time the
/// gas actually changes — even on an otherwise no-deco ascent.
///
/// Unknown / custom mixes fall back to MOD-based depth (PPO2 limit
/// 1.6 for O₂-rich gases, 1.4 for He-bearing gases), rounded DOWN to
/// the nearest 3 m stop. Acceptable for unusual mixes but not the
/// canonical GUE-table value.
double standardSwitchDepth(DiveGasMix gas) {
  const table = <(int, int), double>{
    (100, 0): 6,
    (50, 0): 21,
    (32, 0): 33,
    (35, 25): 36,
    (21, 35): 57,
    (18, 45): 66,
    (15, 55): 75,
    (12, 65): 90,
  };
  final hit = table[(gas.oxygenPercent, gas.heliumPercent)];
  if (hit != null) return hit;

  // Fallback for non-standard mixes. He-bearing gases use the tighter
  // PPO2=1.4 limit (typical "deep" working limit); non-He deco gases
  // use 1.6.
  final ppo2Cap = gas.heliumPercent > 0 ? 1.4 : 1.6;
  final mod = (ppo2Cap / (gas.oxygenPercent / 100.0) - 1.0) * 10.0;
  final stop = (mod / 3.0).floor() * 3.0;
  return stop.clamp(3.0, 90.0);
}

/// Pick the richest gas in [gases] safe to breathe at [depthMeters]
/// under the standard-switch-depth table. A gas is "safe" when its
/// switch depth ≥ the current depth (i.e. the diver has reached the
/// depth at which this gas becomes the right choice).
///
/// Fallback when nothing qualifies (the diver is deeper than ALL their
/// gases' switch depths — rare bailout-from-bottom scenario): the
/// lowest-O₂ gas in the list, as the most-depth-tolerant option. The
/// caller knows the diver breathes what they have in this degenerate
/// case; the planner doesn't try to second-guess.
DiveGasMix _bestGasAtSwitchDepth({
  required List<DiveGasMix> gases,
  required double depthMeters,
}) {
  DiveGasMix? best;
  for (final m in gases) {
    if (standardSwitchDepth(m) < depthMeters) continue;
    if (best == null || m.oxygenPercent > best.oxygenPercent) best = m;
  }
  if (best != null) return best;
  return gases.reduce((a, b) => a.oxygenPercent < b.oxygenPercent ? a : b);
}

/// Linear GF interpolation between (firstStopDepth, gfLow) and
/// (lastStopDepth, gfHigh). Above lastStopDepth (toward surface) the
/// GF stays at gfHigh — the diver has cleared the deco gradient.
///
/// Anchoring gfHigh at lastStopDepth rather than 0 m matches MultiDeco
/// and Shearwater Petrel: the user's chosen last stop IS where they
/// stop using a tightened GF, so the gradient compresses into the
/// [firstStop, lastStop] depth range. Pure Erik Baker uses (firstStop,
/// 0 m) as anchors, which is more conservative on dives where the
/// diver has elected a deeper-than-3 m last stop.
double _gfAt({
  required double currentDepth,
  required double firstStopDepth,
  required double lastStopDepth,
  required int gfLow,
  required int gfHigh,
}) {
  if (currentDepth <= lastStopDepth) return gfHigh / 100.0;
  final span = firstStopDepth - lastStopDepth;
  if (span <= 0) return gfHigh / 100.0;
  final frac =
      ((firstStopDepth - currentDepth) / span).clamp(0.0, 1.0);
  return (gfLow + (gfHigh - gfLow) * frac) / 100.0;
}

/// Advance all 16 N2/He compartments [intervalSeconds] at [ambientBar] on [gas].
void _advanceOneStep({
  required List<double> pN2,
  required List<double> pHe,
  required DiveGasMix gas,
  required double ambientBar,
  required int intervalSeconds,
  double setpointBar = 0.0,
}) {
  final (paN2, paHe) = inertPartialPressures(
    ambientBar: ambientBar,
    mix: gas,
    setpointBar: setpointBar,
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
