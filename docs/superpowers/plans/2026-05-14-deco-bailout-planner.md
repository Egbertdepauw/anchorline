# Deco-based Bailout Planner Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the fixed-time-step bailout simulator with a proper Bühlmann ZH-L16C + Erik-Baker-GF deco planner that produces 3m stop increments starting from a GF-Low-derived first stop. The bailout planner's public type `AscentPlan` stays unchanged so the UI doesn't churn.

**Architecture:** Add a new pure-Dart `deco_planner.dart` that walks tissue state up from a trigger depth, finds the first stop (round up to next 3m), then hops 3m increments holding at each until the linearly-interpolated GF allows the next step. Rewrite `ascent_simulator.simulateAscent` as a thin shim that calls into it and decorates each leg with gas volume via the existing SAC × ambient × duration math. PPO2 limits and ascent rates flow in as parameters so any user-tweaked Settings all work without code changes.

**Tech Stack:** Dart, Drift (unchanged), Flutter (no UI changes). Existing test patterns from `test/analysis/deco/` and `test/analysis/bailout/`.

---

### Task 1: New `DecoStep` shape + signature for `planDeco`

**Files:**
- Create: `lib/analysis/deco/deco_step.dart` (small data class)
- Create: `lib/analysis/deco/deco_planner.dart` (function stub + signature only)
- Create: `test/analysis/deco/deco_planner_test.dart` (the seven tests from the spec; ALL initially failing because planner is a stub)

- [ ] **Step 1: Write the data class**

```dart
// lib/analysis/deco/deco_step.dart
import '../../data/models/dive.dart' show DiveGasMix;

/// One leg of a deco plan: either a flat stop (depthStart == depthEnd) or
/// a moving ascent segment. Duration is always positive. Gas is the mix the
/// diver breathes during this leg.
class DecoStep {
  final double depthStartMeters;
  final double depthEndMeters;
  final Duration duration;
  final DiveGasMix gas;

  const DecoStep({
    required this.depthStartMeters,
    required this.depthEndMeters,
    required this.duration,
    required this.gas,
  });

  bool get isStop => depthStartMeters == depthEndMeters;
}
```

- [ ] **Step 2: Write the planner signature + a stub that returns []**

```dart
// lib/analysis/deco/deco_planner.dart
/// Bühlmann ZH-L16C + Erik-Baker-GF deco planner. Pure function over
/// initial tissue state + ambient model. Output: every leg of the ascent
/// from the trigger depth to the surface, including all 3m holds. No
/// gas-volume math here — that's added by the bailout layer.
library;

import 'dart:math';

import '../../data/models/dive.dart' show DiveGasMix;
import 'deco_step.dart';
import 'gas_pressures.dart';
import 'schreiner.dart';
import 'tissue_model.dart';

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
  return const [];
}
```

- [ ] **Step 3: Write the failing tests**

```dart
// test/analysis/deco/deco_planner_test.dart
import 'package:ccrlogger/analysis/deco/deco_planner.dart';
import 'package:ccrlogger/data/models/dive.dart' show DiveGasMix;
import 'package:flutter_test/flutter_test.dart';

const _air = DiveGasMix(oxygenPercent: 21, heliumPercent: 0, isDiluent: false);
const _ean50 = DiveGasMix(oxygenPercent: 50, heliumPercent: 0, isDiluent: false);
const _o2 = DiveGasMix(oxygenPercent: 100, heliumPercent: 0, isDiluent: false);

List<double> _surfaceN2() =>
    List<double>.filled(16, (1.013 - 0.0627) * 0.79);
List<double> _zeroHe() => List<double>.filled(16, 0.0);

/// Heavily loaded: 4 bar N2 across all compartments — represents a long
/// deep dive that needs substantial deco from 30m+.
List<double> _heavilyLoadedN2() => List<double>.filled(16, 4.0);

void main() {
  group('planDeco', () {
    test('NDL dive returns no stops', () {
      final steps = planDeco(
        initialN2Bar: _surfaceN2(),
        initialHeBar: _zeroHe(),
        triggerDepthMeters: 20,
        gases: const [_air],
        gfLow: 50,
        gfHigh: 95,
        ascentRateFastMPerMin: 18,
        ascentRateSlowMPerMin: 9,
        ppo2LimitBottom: 1.6,
        ppo2LimitDeco: 1.4,
      );
      // Single straight-up ascent leg(s), no stops.
      expect(steps.where((s) => s.isStop), isEmpty);
    });

    test('first stop depth lies on a 3m multiple', () {
      final steps = planDeco(
        initialN2Bar: _heavilyLoadedN2(),
        initialHeBar: _zeroHe(),
        triggerDepthMeters: 40,
        gases: const [_air, _ean50, _o2],
        gfLow: 50,
        gfHigh: 95,
        ascentRateFastMPerMin: 18,
        ascentRateSlowMPerMin: 9,
        ppo2LimitBottom: 1.6,
        ppo2LimitDeco: 1.6,
      );
      final stops = steps.where((s) => s.isStop).toList();
      expect(stops, isNotEmpty);
      for (final s in stops) {
        expect(s.depthStartMeters % 3, 0,
            reason: 'every stop must be at a 3m multiple');
      }
    });

    test('GF Low 30 produces a deeper first stop than GF Low 70', () {
      List<DecoStep> run(int gfLow) => planDeco(
            initialN2Bar: _heavilyLoadedN2(),
            initialHeBar: _zeroHe(),
            triggerDepthMeters: 40,
            gases: const [_air, _ean50, _o2],
            gfLow: gfLow,
            gfHigh: 85,
            ascentRateFastMPerMin: 18,
            ascentRateSlowMPerMin: 9,
            ppo2LimitBottom: 1.6,
            ppo2LimitDeco: 1.6,
          );
      double firstStop(List<DecoStep> steps) => steps
          .firstWhere((s) => s.isStop, orElse: () => steps.first)
          .depthStartMeters;
      expect(firstStop(run(30)), greaterThan(firstStop(run(70))));
    });

    test('every stop depth is divisible by 3', () {
      final steps = planDeco(
        initialN2Bar: _heavilyLoadedN2(),
        initialHeBar: _zeroHe(),
        triggerDepthMeters: 45,
        gases: const [_air, _ean50, _o2],
        gfLow: 50,
        gfHigh: 95,
        ascentRateFastMPerMin: 18,
        ascentRateSlowMPerMin: 9,
        ppo2LimitBottom: 1.6,
        ppo2LimitDeco: 1.6,
      );
      for (final s in steps.where((s) => s.isStop)) {
        expect(s.depthStartMeters % 3, 0);
      }
    });

    test('heavier tissue loading produces longer total stop time', () {
      Duration totalStopTime(List<double> n2) {
        final steps = planDeco(
          initialN2Bar: n2,
          initialHeBar: _zeroHe(),
          triggerDepthMeters: 40,
          gases: const [_air, _ean50, _o2],
          gfLow: 50,
          gfHigh: 95,
          ascentRateFastMPerMin: 18,
          ascentRateSlowMPerMin: 9,
          ppo2LimitBottom: 1.6,
          ppo2LimitDeco: 1.6,
        );
        return steps.where((s) => s.isStop).fold(
              Duration.zero,
              (sum, s) => sum + s.duration,
            );
      }

      final heavy = List<double>.filled(16, 4.5);
      final lighter = List<double>.filled(16, 3.0);
      expect(totalStopTime(heavy), greaterThan(totalStopTime(lighter)));
    });

    test('EAN 50 is breathed at its first MOD-allowed stop, not deeper', () {
      final steps = planDeco(
        initialN2Bar: _heavilyLoadedN2(),
        initialHeBar: _zeroHe(),
        triggerDepthMeters: 40,
        gases: const [_air, _ean50, _o2],
        gfLow: 50,
        gfHigh: 95,
        ascentRateFastMPerMin: 18,
        ascentRateSlowMPerMin: 9,
        ppo2LimitBottom: 1.6,
        ppo2LimitDeco: 1.6,
      );
      for (final s in steps) {
        final ambient = 1.013 + s.depthStartMeters / 10.0;
        final ppo2 = (s.gas.oxygenPercent / 100.0) * ambient;
        expect(ppo2, lessThanOrEqualTo(1.6),
            reason: 'breathing ${s.gas.oxygenPercent}% at ${s.depthStartMeters}m '
                'gives PPO2 $ppo2 — must stay ≤ 1.6');
      }
    });

    test('plan terminates at the surface (final depthEnd == 0)', () {
      final steps = planDeco(
        initialN2Bar: _heavilyLoadedN2(),
        initialHeBar: _zeroHe(),
        triggerDepthMeters: 40,
        gases: const [_air, _ean50, _o2],
        gfLow: 50,
        gfHigh: 95,
        ascentRateFastMPerMin: 18,
        ascentRateSlowMPerMin: 9,
        ppo2LimitBottom: 1.6,
        ppo2LimitDeco: 1.6,
      );
      expect(steps, isNotEmpty);
      expect(steps.last.depthEndMeters, 0);
    });
  });
}
```

- [ ] **Step 4: Verify all seven tests fail**

```bash
flutter test test/analysis/deco/deco_planner_test.dart
```

Expected: 7 failures (planner stub returns empty list).

- [ ] **Step 5: Commit**

```bash
git add lib/analysis/deco/deco_step.dart lib/analysis/deco/deco_planner.dart \
        test/analysis/deco/deco_planner_test.dart
git commit -m "feat(deco): scaffold deco_planner signature + failing tests"
```

---

### Task 2: First-stop search (phase 1 of the algorithm)

**Files:**
- Modify: `lib/analysis/deco/deco_planner.dart`

- [ ] **Step 1: Add the GF-aware ceiling helper**

Insert at the top of `deco_planner.dart` (under imports):

```dart
const double _surfaceAtmBar = 1.013;

/// Worst-compartment ceiling in metres at the given tissue state and GF.
/// Returns 0 when no compartment requires a stop deeper than the surface.
///
/// Uses the Erik-Baker GF reduction of the Bühlmann M-line:
///     P_amb_tol = (P_tissue − a × gf) × b / (1 − gf + gf × b)
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
    final denom = 1.0 - gfFraction + gfFraction * b;
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
```

- [ ] **Step 2: Replace the stub body with phase-1 first-stop search**

```dart
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

  final pN2 = List<double>.from(initialN2Bar);
  final pHe = List<double>.from(initialHeBar);
  final gfLowFrac = gfLow / 100.0;

  // ── Phase 1: walk up at fast rate in 1m steps to find first stop ─────
  // At each 1m, advance tissues, then check GF-Low ceiling. The first
  // depth where the ceiling breaches the diver's position is the deepest
  // legal stop; we round it UP to a 3m multiple.
  double depth = triggerDepthMeters;
  final stepMin = 1.0 / ascentRateFastMPerMin; // minutes per 1m step
  final stepSec = (stepMin * 60).round();
  while (depth > 0) {
    final nextDepth = (depth - 1).clamp(0.0, depth);
    final gas = _bestGasAt(
      gases: gases,
      depthMeters: (depth + nextDepth) / 2.0,
      ppo2Limit: ppo2LimitBottom,
    );
    final avgAmbient = _surfaceAtmBar + (depth + nextDepth) / 2.0 / 10.0;
    final (paN2, paHe) = inertPartialPressures(
      ambientBar: avgAmbient,
      mix: gas,
      setpointBar: 0.0,
    );
    for (var c = 0; c < 16; c++) {
      pN2[c] = loadCompartment(
        currentLoadBar: pN2[c],
        inertGasPartialPressureBar: paN2,
        halfTimeMin: zhl16cTissues[c].halfTimeN2Min,
        intervalSeconds: stepSec,
      );
      pHe[c] = loadCompartment(
        currentLoadBar: pHe[c],
        inertGasPartialPressureBar: paHe,
        halfTimeMin: zhl16cTissues[c].halfTimeHeMin,
        intervalSeconds: stepSec,
      );
    }
    final ceiling = _ceilingMetersFor(
      pN2: pN2,
      pHe: pHe,
      gfFraction: gfLowFrac,
    );
    if (ceiling > nextDepth) {
      // Ceiling breaches the depth we'd be at next minute → stop here.
      break;
    }
    depth = nextDepth;
  }

  // Round first stop up to the next 3m increment. If we walked all the way
  // to the surface without ever finding a ceiling breach, depth == 0 → no deco.
  final firstStopDepth = depth <= 0 ? 0.0 : ((depth / 3).ceil() * 3).toDouble();
  if (firstStopDepth == 0) {
    return const []; // NDL, no deco required
  }

  // Phase 2 lands in Task 3.
  return const [];
}
```

- [ ] **Step 3: Run tests — expect first-stop tests partially pass**

```bash
flutter test test/analysis/deco/deco_planner_test.dart
```

Expected: "NDL dive returns no stops" passes; the rest still fail because phase 2 (stop ladder) isn't there yet.

- [ ] **Step 4: Commit**

```bash
git add -u lib/analysis/deco/deco_planner.dart
git commit -m "feat(deco): phase 1 — walk tissues up to find GF-Low first stop"
```

---

### Task 3: Stop-ladder loop (phase 2)

**Files:**
- Modify: `lib/analysis/deco/deco_planner.dart`

- [ ] **Step 1: Replace the trailing `return const [];` with phase 2**

The state at the top of phase 2: `pN2`, `pHe` already advanced to whatever depth phase 1 stopped at; `firstStopDepth` is the rounded 3m. We need to:
- Re-roll back the tissues to the trigger point (phase 1 was just a search), OR
- Track them separately. Simpler to **re-do phase 1 cleanly** as a "walk from trigger to firstStop, recording legs" once we know the target.

Replace the bottom of `planDeco` with:

```dart
  // Phase 1 mutated pN2/pHe to find the breach. Re-initialise from the
  // original input so phase 2 walks a clean tissue state from the trigger.
  for (var c = 0; c < 16; c++) {
    pN2[c] = initialN2Bar[c];
    pHe[c] = initialHeBar[c];
  }

  final steps = <DecoStep>[];

  // ── Phase 2a: ascent from trigger depth to first stop (1m / 1-min) ────
  // Tissues evolve at the configured FAST ascent rate. Gas chosen at each
  // metre per ppo2LimitBottom — the bottom mix while at depth.
  double currentDepth = triggerDepthMeters;
  while (currentDepth > firstStopDepth) {
    final nextDepth = max(firstStopDepth, currentDepth - 1.0);
    final gas = _bestGasAt(
      gases: gases,
      depthMeters: (currentDepth + nextDepth) / 2.0,
      ppo2Limit: ppo2LimitBottom,
    );
    final avgAmbient = _surfaceAtmBar + (currentDepth + nextDepth) / 2.0 / 10.0;
    final (paN2, paHe) = inertPartialPressures(
      ambientBar: avgAmbient,
      mix: gas,
      setpointBar: 0.0,
    );
    final secs = ((currentDepth - nextDepth) / ascentRateFastMPerMin * 60).round();
    for (var c = 0; c < 16; c++) {
      pN2[c] = loadCompartment(
        currentLoadBar: pN2[c],
        inertGasPartialPressureBar: paN2,
        halfTimeMin: zhl16cTissues[c].halfTimeN2Min,
        intervalSeconds: secs,
      );
      pHe[c] = loadCompartment(
        currentLoadBar: pHe[c],
        inertGasPartialPressureBar: paHe,
        halfTimeMin: zhl16cTissues[c].halfTimeHeMin,
        intervalSeconds: secs,
      );
    }
    steps.add(DecoStep(
      depthStartMeters: currentDepth,
      depthEndMeters: nextDepth,
      duration: Duration(seconds: secs),
      gas: gas,
    ));
    currentDepth = nextDepth;
  }

  // ── Phase 2b: 3m stop ladder ──────────────────────────────────────────
  while (currentDepth > 0) {
    final nextStop = max(0.0, currentDepth - 3.0);
    final gfFractionHere = _gfAt(
      currentDepth: currentDepth,
      firstStopDepth: firstStopDepth,
      gfLow: gfLow,
      gfHigh: gfHigh,
    );
    final gas = _bestGasAt(
      gases: gases,
      depthMeters: currentDepth,
      ppo2Limit: ppo2LimitDeco,
    );

    // Hold at currentDepth until ceiling clears nextStop (≤ nextStop metres).
    var minutesHeld = 0;
    const stopStepSec = 60;
    while (true) {
      final ceiling = _ceilingMetersFor(
        pN2: pN2,
        pHe: pHe,
        gfFraction: gfFractionHere,
      );
      if (ceiling <= nextStop + 1e-6) break;
      // Off-gas one minute at currentDepth on the chosen gas.
      final ambient = _surfaceAtmBar + currentDepth / 10.0;
      final (paN2, paHe) = inertPartialPressures(
        ambientBar: ambient,
        mix: gas,
        setpointBar: 0.0,
      );
      for (var c = 0; c < 16; c++) {
        pN2[c] = loadCompartment(
          currentLoadBar: pN2[c],
          inertGasPartialPressureBar: paN2,
          halfTimeMin: zhl16cTissues[c].halfTimeN2Min,
          intervalSeconds: stopStepSec,
        );
        pHe[c] = loadCompartment(
          currentLoadBar: pHe[c],
          inertGasPartialPressureBar: paHe,
          halfTimeMin: zhl16cTissues[c].halfTimeHeMin,
          intervalSeconds: stopStepSec,
        );
      }
      minutesHeld++;
      if (minutesHeld > 600) break; // 10h safety cap
    }
    if (minutesHeld > 0) {
      steps.add(DecoStep(
        depthStartMeters: currentDepth,
        depthEndMeters: currentDepth,
        duration: Duration(minutes: minutesHeld),
        gas: gas,
      ));
    }

    // Ascend 3m to next stop at SLOW rate.
    if (nextStop < currentDepth) {
      final ascentGas = _bestGasAt(
        gases: gases,
        depthMeters: (currentDepth + nextStop) / 2.0,
        ppo2Limit: ppo2LimitDeco,
      );
      final secs = ((currentDepth - nextStop) / ascentRateSlowMPerMin * 60).round();
      final avgAmbient =
          _surfaceAtmBar + (currentDepth + nextStop) / 2.0 / 10.0;
      final (paN2, paHe) = inertPartialPressures(
        ambientBar: avgAmbient,
        mix: ascentGas,
        setpointBar: 0.0,
      );
      for (var c = 0; c < 16; c++) {
        pN2[c] = loadCompartment(
          currentLoadBar: pN2[c],
          inertGasPartialPressureBar: paN2,
          halfTimeMin: zhl16cTissues[c].halfTimeN2Min,
          intervalSeconds: secs,
        );
        pHe[c] = loadCompartment(
          currentLoadBar: pHe[c],
          inertGasPartialPressureBar: paHe,
          halfTimeMin: zhl16cTissues[c].halfTimeHeMin,
          intervalSeconds: secs,
        );
      }
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

/// Linear GF interpolation between (firstStopDepth, gfLow) and (0m, gfHigh).
double _gfAt({
  required double currentDepth,
  required double firstStopDepth,
  required int gfLow,
  required int gfHigh,
}) {
  if (firstStopDepth <= 0) return gfHigh / 100.0;
  final frac = ((firstStopDepth - currentDepth) / firstStopDepth).clamp(0.0, 1.0);
  return (gfLow + (gfHigh - gfLow) * frac) / 100.0;
}
```

- [ ] **Step 2: Run tests — all seven should now pass**

```bash
flutter test test/analysis/deco/deco_planner_test.dart
```

Expected: green.

- [ ] **Step 3: Commit**

```bash
git add -u lib/analysis/deco/deco_planner.dart
git commit -m "feat(deco): phase 2 — 3m stop ladder with linear GF interpolation"
```

---

### Task 4: Rewrite `ascent_simulator.simulateAscent` as a shim

**Files:**
- Modify: `lib/analysis/bailout/ascent_simulator.dart`
- Test: `test/analysis/bailout/ascent_simulator_test.dart` (existing tests should still pass — the public API is unchanged)

- [ ] **Step 1: Replace the body of `simulateAscent`**

The new body calls `planDeco` and decorates the returned `DecoStep`s with `volumeLitresConsumed`. Replace the existing `simulateAscent` function body (keep the signature):

```dart
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
  assert(initialN2Bar.length == 16);
  assert(initialHeBar.length == 16);
  assert(availableGases.isNotEmpty);

  final steps = planDeco(
    initialN2Bar: initialN2Bar,
    initialHeBar: initialHeBar,
    triggerDepthMeters: triggerDepthMeters,
    gases: availableGases,
    gfLow: gfLow,
    gfHigh: gfHigh,
    ascentRateFastMPerMin: ascentRateFast,
    ascentRateSlowMPerMin: ascentRateSlow,
    // Bottom mix selection uses 1.6 max; deco-gas switches use 1.6 too
    // (1.4 is the bailout-capable-diluent limit and lives at the bailout planner layer).
    ppo2LimitBottom: 1.6,
    ppo2LimitDeco: 1.6,
  );

  // Phantom "straight up" leg for the NDL case — planDeco returns [] which
  // would otherwise leave the diver at triggerDepth with no stops to consume.
  if (steps.isEmpty) {
    final secs = (triggerDepthMeters / ascentRateSlow * 60).round();
    final gas = availableGases.first;
    final avgAmbient = _surfaceAtmBar + triggerDepthMeters / 2.0 / 10.0;
    final volumeL = sacDeco * avgAmbient * (secs / 60);
    return AscentPlan(
      stops: [
        AscentStop(
          depthStartMeters: triggerDepthMeters,
          depthEndMeters: 0,
          duration: Duration(seconds: secs),
          gas: gas,
          volumeLitresConsumed: volumeL,
        ),
      ],
      totalTime: Duration(seconds: secs),
      volumeByGas: {gas: volumeL},
    );
  }

  // Decorate each DecoStep with volume. Bottom SAC applies on the leg from
  // trigger to first stop; deco SAC applies once at the first stop and beyond.
  // We detect "in deco zone" the first time we hit a flat stop.
  var inDecoZone = false;
  final stops = <AscentStop>[];
  final volumeByGas = <DiveGasMix, double>{};
  var totalTime = Duration.zero;
  for (final step in steps) {
    if (step.isStop) inDecoZone = true;
    final sac = inDecoZone ? sacDeco : sacBottom;
    final avgAmbient =
        _surfaceAtmBar + (step.depthStartMeters + step.depthEndMeters) / 20.0;
    final minutes = step.duration.inMilliseconds / 60000.0;
    final volumeL = sac * avgAmbient * minutes;
    stops.add(AscentStop(
      depthStartMeters: step.depthStartMeters,
      depthEndMeters: step.depthEndMeters,
      duration: step.duration,
      gas: step.gas,
      volumeLitresConsumed: volumeL,
    ));
    volumeByGas[step.gas] = (volumeByGas[step.gas] ?? 0.0) + volumeL;
    totalTime += step.duration;
  }
  return AscentPlan(stops: stops, totalTime: totalTime, volumeByGas: volumeByGas);
}
```

- [ ] **Step 2: Delete the now-unused private helpers from `ascent_simulator.dart`**

Drop these (they live in `deco_planner.dart` now, or are no longer needed):
- `_findFirstSwitchDepth`
- `_loadTissuesOneStep`
- `_computeGf99AtDepth`
- `_bestGasForDepth` *(if `deco_planner._bestGasAt` is callable via export; otherwise keep but rename for clarity — easier to just delete and let `planDeco` own the logic)*
- The `_maxIterations` constant.

Add a single new import:

```dart
import '../deco/deco_planner.dart' show planDeco;
```

- [ ] **Step 3: Update the existing ascent-simulator tests**

Look at the existing test file and update assertions where they reference fixed-time-walk behavior (e.g. asserting on exact depth values like `22m → 4m`). The new tests should assert structural invariants:
- For an NDL dive: `stops.length == 1` and `stops.first.depthEndMeters == 0`.
- For a dive that needs deco: `stops.length > 1`, `stops.last.depthEndMeters == 0`, `stops.any((s) => s.depthStartMeters == s.depthEndMeters)` is true.
- `volumeByGas` keys match the gases that appear in `stops`.
- Total volume is the sum of per-stop volumes.

```bash
flutter test test/analysis/bailout/ascent_simulator_test.dart
```

Fix the assertions until green. Don't loosen anything that tests real behavior — just remove brittle hard-coded depth/time values that the old time-walk produced.

- [ ] **Step 4: Run the full bailout test suite**

```bash
flutter test test/analysis/bailout/
flutter test test/analysis/deco/
```

Expected: green. The `bailout_planner_test.dart` regressions (the 51m-trimix-bottom-mix one) keep passing because the bottom-mix-prepending logic is upstream of the simulator.

- [ ] **Step 5: Commit**

```bash
git add -u lib/analysis/bailout/ascent_simulator.dart \
          test/analysis/bailout/ascent_simulator_test.dart
git commit -m "refactor(bailout): ascent_simulator wraps the new deco_planner"
```

---

### Task 5: Remove the temporary debug banner

**Files:**
- Modify: `lib/ui/widgets/bailout_section.dart` (drop `debugBanner` field)
- Modify: `lib/ui/screens/dive_detail_screen.dart` (stop passing `debugBanner`)

- [ ] **Step 1: Drop the field**

In `bailout_section.dart`, remove the `debugBanner` field, its constructor parameter, and the conditional `if (debugBanner != null && debugBanner!.isNotEmpty)` block inside `_Banner`. Restore the banner to a single `Text` child.

- [ ] **Step 2: Drop the call site**

In `dive_detail_screen.dart`'s `_bailoutSectionBody`, remove the `dilLabel`/`gasLabels` computation and the `debugBanner:` argument when constructing `BailoutSection`.

- [ ] **Step 3: Verify**

```bash
flutter analyze
flutter test
```

Expected: clean + green.

- [ ] **Step 4: Commit**

```bash
git add -u lib/ui/widgets/bailout_section.dart lib/ui/screens/dive_detail_screen.dart
git commit -m "chore(bailout): drop temporary diagnostic banner"
```

---

### Task 6: Smoke check + scope verification

**Files:** none.

- [ ] **Step 1: `flutter analyze`**

Expected: clean.

- [ ] **Step 2: `flutter test`**

Expected: all green.

- [ ] **Step 3: Manual verification (operator runs on device after rebuild)**

For a known dive (e.g. Dive #709, 40m on air, GF 50/95):
- Bailout panel header shows "Standard gases" or "User-defined bailout tanks" as before.
- Stops table shows 12m or 15m as the **first stop** (GF-Low determined), then 9, 6, 3, 0.
- Gas column shows the bottom mix (Air or 21/35) at the deeper stops, EAN 50 from ~22m up (if present), O2 from ~6m up.
- Times are integer minutes.

If output deviates significantly from Subsurface's planner on the same dive — document the delta but don't chase exact parity in v1 (Subsurface uses a different ascent-rate convention by default).

- [ ] **Step 4: No commit — verification only.**

---

## Self-review

- [x] **Spec coverage:** every spec section maps to a task (planDeco signature → T1, phase 1 → T2, phase 2 → T3, ascent_simulator shim → T4, debug cleanup → T5, verify → T6).
- [x] **No placeholders:** every step contains the code or commands to execute, not "TODO".
- [x] **Type consistency:** `DecoStep` defined in T1, used in T2/T3/T4. `_bestGasAt` defined in T2's helper block, called in T2 and T3. `_gfAt` defined in T3, used in T3.
- [x] **No bare references:** `gas_pressures.dart`, `schreiner.dart`, `tissue_model.dart` already exist on `main` — no need to create them.
