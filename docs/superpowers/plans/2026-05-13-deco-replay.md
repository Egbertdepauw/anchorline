# Tissue Replay Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a pure-Dart ZHL-16C + VPM-B replay engine that consumes a parsed dive and produces per-sample GF99, ceiling, and per-compartment tissue saturation, plus aggregate Surface GF / Max GF stats. Surface as chart traces, stat tiles, and a collapsible heatmap. Algorithm switchable per-dive; VPM-B conservatism settable globally.

**Architecture:** Six analysis files in `lib/analysis/deco/` (constants, shared Schreiner equation, two algorithm engines, result type, orchestrator with LRU cache). Schema migration adds `display_deco_algorithm` on `dive_annotations`. UI surfaces wire to existing patterns from Track 4 — segmented-bar enum extensions, StatTile additions, ListenableBuilder wraps. Fixture-based regression tests validate engine output against hand-computed expectations.

**Tech Stack:** Flutter, flutter_test, dart:typed_data, drift (SQL), shared_preferences

**Spec:** [docs/superpowers/specs/2026-05-13-deco-replay-design.md](../specs/2026-05-13-deco-replay-design.md)

---

## Task 1: Tissue-model constants + Schreiner equation

**Files:**
- Create: `lib/analysis/deco/tissue_model.dart`
- Create: `lib/analysis/deco/schreiner.dart`
- Create: `test/analysis/deco/tissue_model_test.dart`
- Create: `test/analysis/deco/schreiner_test.dart`

- [ ] **Step 1: Write failing tests for `tissue_model.dart`**

Create `test/analysis/deco/tissue_model_test.dart`:

```dart
import 'package:ccrlogger/analysis/deco/tissue_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('zhl16cTissues has exactly 16 compartments', () {
    expect(zhl16cTissues, hasLength(16));
  });

  test('every compartment has positive N2 + He half-times', () {
    for (final c in zhl16cTissues) {
      expect(c.halfTimeN2Min, greaterThan(0));
      expect(c.halfTimeHeMin, greaterThan(0));
    }
  });

  test('every compartment has Bühlmann a/b for both gases', () {
    for (final c in zhl16cTissues) {
      expect(c.aN2, greaterThan(0));
      expect(c.bN2, inInclusiveRange(0.0, 1.0));
      expect(c.aHe, greaterThan(0));
      expect(c.bHe, inInclusiveRange(0.0, 1.0));
    }
  });

  test('compartments ordered fast→slow by N2 half-time', () {
    for (var i = 1; i < zhl16cTissues.length; i++) {
      expect(zhl16cTissues[i].halfTimeN2Min,
          greaterThan(zhl16cTissues[i - 1].halfTimeN2Min));
    }
  });

  test('compartment 1 N2 half-time = 4.0 min, a = 1.2599 (Subsurface canonical)', () {
    expect(zhl16cTissues[0].halfTimeN2Min, closeTo(4.0, 0.01));
    expect(zhl16cTissues[0].aN2, closeTo(1.2599, 0.001));
  });

  test('compartment 16 N2 half-time = 635 min (slowest)', () {
    expect(zhl16cTissues[15].halfTimeN2Min, closeTo(635.0, 0.5));
  });
}
```

- [ ] **Step 2: Implement `tissue_model.dart`**

Lift the Bühlmann ZHL-16C constants verbatim from Subsurface's `core/deco.cpp`. The 16-compartment table is canonical data — copy-paste exactly.

Create `lib/analysis/deco/tissue_model.dart`:

```dart
/// ZHL-16C tissue compartment constants. Verbatim from Subsurface's
/// core/deco.cpp — canonical Bühlmann ZHL-16C parameters.
///
/// Half-times in minutes; a/b are the Workman/Bühlmann coefficients
/// for the M-value linear relationship M = a + depth/b.
library;

class TissueCompartment {
  final double halfTimeN2Min;
  final double halfTimeHeMin;
  final double aN2;
  final double bN2;
  final double aHe;
  final double bHe;
  const TissueCompartment({
    required this.halfTimeN2Min,
    required this.halfTimeHeMin,
    required this.aN2,
    required this.bN2,
    required this.aHe,
    required this.bHe,
  });
}

/// 16 compartments, fast-to-slow. Values from Subsurface core/deco.cpp
/// (which sources Bühlmann ZHL-16C as published).
const List<TissueCompartment> zhl16cTissues = [
  TissueCompartment(halfTimeN2Min: 4.0,   halfTimeHeMin: 1.51,  aN2: 1.2599, bN2: 0.5050, aHe: 1.7424, bHe: 0.4245),
  TissueCompartment(halfTimeN2Min: 8.0,   halfTimeHeMin: 3.02,  aN2: 1.0000, bN2: 0.6514, aHe: 1.3830, bHe: 0.5747),
  TissueCompartment(halfTimeN2Min: 12.5,  halfTimeHeMin: 4.72,  aN2: 0.8618, bN2: 0.7222, aHe: 1.1919, bHe: 0.6527),
  TissueCompartment(halfTimeN2Min: 18.5,  halfTimeHeMin: 6.99,  aN2: 0.7562, bN2: 0.7825, aHe: 1.0458, bHe: 0.7223),
  TissueCompartment(halfTimeN2Min: 27.0,  halfTimeHeMin: 10.21, aN2: 0.6200, bN2: 0.8126, aHe: 0.9220, bHe: 0.7582),
  TissueCompartment(halfTimeN2Min: 38.3,  halfTimeHeMin: 14.48, aN2: 0.5043, bN2: 0.8434, aHe: 0.8205, bHe: 0.7957),
  TissueCompartment(halfTimeN2Min: 54.3,  halfTimeHeMin: 20.53, aN2: 0.4410, bN2: 0.8693, aHe: 0.7305, bHe: 0.8279),
  TissueCompartment(halfTimeN2Min: 77.0,  halfTimeHeMin: 29.11, aN2: 0.4000, bN2: 0.8910, aHe: 0.6502, bHe: 0.8553),
  TissueCompartment(halfTimeN2Min: 109.0, halfTimeHeMin: 41.20, aN2: 0.3750, bN2: 0.9092, aHe: 0.5950, bHe: 0.8757),
  TissueCompartment(halfTimeN2Min: 146.0, halfTimeHeMin: 55.19, aN2: 0.3500, bN2: 0.9222, aHe: 0.5545, bHe: 0.8903),
  TissueCompartment(halfTimeN2Min: 187.0, halfTimeHeMin: 70.69, aN2: 0.3295, bN2: 0.9319, aHe: 0.5333, bHe: 0.8997),
  TissueCompartment(halfTimeN2Min: 239.0, halfTimeHeMin: 90.34, aN2: 0.3065, bN2: 0.9403, aHe: 0.5189, bHe: 0.9073),
  TissueCompartment(halfTimeN2Min: 305.0, halfTimeHeMin: 115.29,aN2: 0.2835, bN2: 0.9477, aHe: 0.5181, bHe: 0.9122),
  TissueCompartment(halfTimeN2Min: 390.0, halfTimeHeMin: 147.42,aN2: 0.2610, bN2: 0.9544, aHe: 0.5176, bHe: 0.9171),
  TissueCompartment(halfTimeN2Min: 498.0, halfTimeHeMin: 188.24,aN2: 0.2480, bN2: 0.9602, aHe: 0.5172, bHe: 0.9217),
  TissueCompartment(halfTimeN2Min: 635.0, halfTimeHeMin: 240.03,aN2: 0.2327, bN2: 0.9653, aHe: 0.5119, bHe: 0.9267),
];
```

- [ ] **Step 3: Write failing tests for `schreiner.dart`**

Create `test/analysis/deco/schreiner_test.dart`:

```dart
import 'package:ccrlogger/analysis/deco/schreiner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('flat-depth equilibration follows exponential load curve', () {
    // Tissue at 0 atm, breathing 0.79 atm N2 (air at surface).
    // After one half-time, should be 50% equilibrated.
    final result = loadCompartment(
      currentLoadBar: 0.0,
      inertGasPartialPressureBar: 0.79,
      halfTimeMin: 10.0,
      intervalSeconds: 600, // 10 min = 1 half-time
    );
    expect(result, closeTo(0.395, 0.005));  // 50% of 0.79
  });

  test('two half-times → 75% equilibration', () {
    final result = loadCompartment(
      currentLoadBar: 0.0,
      inertGasPartialPressureBar: 1.0,
      halfTimeMin: 10.0,
      intervalSeconds: 1200, // 20 min = 2 half-times
    );
    expect(result, closeTo(0.75, 0.01));
  });

  test('zero interval returns current load unchanged', () {
    final result = loadCompartment(
      currentLoadBar: 1.5,
      inertGasPartialPressureBar: 2.0,
      halfTimeMin: 10.0,
      intervalSeconds: 0,
    );
    expect(result, closeTo(1.5, 0.001));
  });

  test('descending pressure (off-gas) reduces load toward new equilibrium', () {
    final result = loadCompartment(
      currentLoadBar: 2.0,
      inertGasPartialPressureBar: 0.79,
      halfTimeMin: 10.0,
      intervalSeconds: 600,
    );
    // Half-way from 2.0 toward 0.79 = 1.395
    expect(result, closeTo(1.395, 0.005));
  });
}
```

- [ ] **Step 4: Implement `schreiner.dart`**

Create `lib/analysis/deco/schreiner.dart`:

```dart
/// Schreiner equation — exponential approach to equilibrium for a
/// single tissue compartment over a single time interval.
///
/// Returns the new compartment load (bar) given:
/// - [currentLoadBar] — the existing dissolved inert-gas partial pressure
/// - [inertGasPartialPressureBar] — what's currently being breathed (PaN2 or PaHe)
/// - [halfTimeMin] — the compartment's half-time for this gas
/// - [intervalSeconds] — elapsed time in this state
///
/// For a constant-depth segment: P(t) = Pi + (P0 − Pi) × exp(−k·t)
/// where k = ln(2) / halfTime.
library;

import 'dart:math';

double loadCompartment({
  required double currentLoadBar,
  required double inertGasPartialPressureBar,
  required double halfTimeMin,
  required int intervalSeconds,
}) {
  if (intervalSeconds <= 0) return currentLoadBar;
  final k = ln2 / (halfTimeMin * 60.0); // per-second decay constant
  final t = intervalSeconds.toDouble();
  return inertGasPartialPressureBar +
      (currentLoadBar - inertGasPartialPressureBar) * exp(-k * t);
}
```

- [ ] **Step 5: Run tests + analyze + commit**

```bash
flutter test test/analysis/deco/tissue_model_test.dart  # 6/6 pass
flutter test test/analysis/deco/schreiner_test.dart     # 4/4 pass
flutter analyze  # clean
git add lib/analysis/deco/tissue_model.dart lib/analysis/deco/schreiner.dart test/analysis/deco/
git commit -m "$(cat <<'EOF'
feat(analysis): ZHL-16C tissue model + Schreiner equation

16 compartment Bühlmann ZHL-16C constants (half-times, a/b coefficients)
lifted verbatim from Subsurface core/deco.cpp — canonical data. Schreiner
equation as a pure function for single-compartment exponential approach
to equilibrium. Foundation for both ZHL-16C and VPM-B engines.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Replay result type + ZHL-16C engine

**Files:**
- Create: `lib/analysis/deco/replay_result.dart`
- Create: `lib/analysis/deco/zhl16c.dart`
- Create: `test/analysis/deco/zhl16c_test.dart`

- [ ] **Step 1: Write failing tests**

Create `test/analysis/deco/zhl16c_test.dart`:

```dart
import 'dart:typed_data';
import 'package:ccrlogger/analysis/deco/zhl16c.dart';
import 'package:ccrlogger/analysis/deco/replay_result.dart';
import 'package:ccrlogger/data/models/dive.dart' show DiveGasMix;
import 'package:flutter_test/flutter_test.dart';

SampleStub _flat(double depthM, int durationSec, int intervalMs) {
  final n = (durationSec * 1000 / intervalMs).round();
  return SampleStub(
    depthMeters: Float32List(n)..fillRange(0, n, depthM),
    gasMixIndex: Uint8List(n),
    sampleIntervalMs: intervalMs,
  );
}

void main() {
  group('Zhl16cReplay — basic invariants', () {
    test('surface-equilibrated diver at 0 m → GF99 ≈ 0', () {
      final samples = _flat(0, 60, 1000);
      final result = Zhl16cReplay().run(
        samples: samples,
        gasMixes: [DiveGasMix(o2: 21, he: 0, diluent: true)],
        gfLow: 30,
        gfHigh: 85,
      );
      expect(result.gf99Series[0], lessThan(1.0));
      expect(result.surfaceGfFinal, lessThan(1.0));
    });

    test('30 min at 30 m on air → tissues take up gas, GF99 rises', () {
      final samples = _flat(30, 30 * 60, 10000);
      final result = Zhl16cReplay().run(
        samples: samples,
        gasMixes: [DiveGasMix(o2: 21, he: 0, diluent: true)],
        gfLow: 30,
        gfHigh: 85,
      );
      // After 30 min at 30 m on air, fast tissues are saturated
      // near ambient. GF99 should be > 50% by end (depends on which
      // compartment dominates).
      expect(result.gf99Series.last, greaterThan(30.0));
    });

    test('result has 16 tissue series each with correct length', () {
      final samples = _flat(20, 60, 1000);
      final result = Zhl16cReplay().run(
        samples: samples,
        gasMixes: [DiveGasMix(o2: 21, he: 0, diluent: true)],
        gfLow: 30,
        gfHigh: 85,
      );
      expect(result.tissueLoadsPct, hasLength(16));
      for (final series in result.tissueLoadsPct) {
        expect(series.length, samples.depthMeters.length);
      }
    });

    test('GF99 series length matches sample count', () {
      final samples = _flat(20, 60, 1000);
      final result = Zhl16cReplay().run(
        samples: samples,
        gasMixes: [DiveGasMix(o2: 21, he: 0, diluent: true)],
        gfLow: 30,
        gfHigh: 85,
      );
      expect(result.gf99Series.length, samples.depthMeters.length);
      expect(result.ceilingMeters.length, samples.depthMeters.length);
    });

    test('algorithm field on result is zhl16c', () {
      final samples = _flat(20, 60, 1000);
      final result = Zhl16cReplay().run(
        samples: samples,
        gasMixes: [DiveGasMix(o2: 21, he: 0, diluent: true)],
        gfLow: 30,
        gfHigh: 85,
      );
      expect(result.algorithm, DecoAlgorithm.zhl16c);
      expect(result.gfLow, 30);
      expect(result.gfHigh, 85);
    });
  });
}
```

Note `SampleStub` here is a minimal test-only stand-in. We're testing the engine; the actual `SampleSet` from the codebase has many more fields. Define a small interface or use the existing `SampleSet` if it's already easy to construct in tests.

- [ ] **Step 2: Implement `replay_result.dart`**

Create `lib/analysis/deco/replay_result.dart`:

```dart
import 'dart:typed_data';

enum DecoAlgorithm { zhl16c, vpmb }

class DecoReplayResult {
  /// Per-sample instantaneous gradient factor (%) — 0 at surface
  /// equilibrium, 100 at the limit, >100 means supersaturated.
  final Float32List gf99Series;

  /// Per-sample deco ceiling (m). 0 means "no stop required".
  final Float32List ceilingMeters;

  /// 16 series, one per ZHL-16C compartment, each = current load
  /// expressed as % of compartment's current M-value. >100 = supersaturated.
  final List<Float32List> tissueLoadsPct;

  /// What GF you'd hit if you surfaced at the last sample.
  final double surfaceGfFinal;

  /// Peak GF99 across the dive.
  final double maxGf99;

  /// Which algorithm produced this result.
  final DecoAlgorithm algorithm;

  /// VPM-B-specific input recorded for cache invalidation. Null for ZHL-16C.
  final int? vpmbConservatism;

  /// ZHL-16C-specific GF inputs recorded for cache invalidation. Both null for VPM-B.
  final int? gfLow;
  final int? gfHigh;

  const DecoReplayResult({
    required this.gf99Series,
    required this.ceilingMeters,
    required this.tissueLoadsPct,
    required this.surfaceGfFinal,
    required this.maxGf99,
    required this.algorithm,
    this.vpmbConservatism,
    this.gfLow,
    this.gfHigh,
  });
}
```

- [ ] **Step 3: Implement `zhl16c.dart`**

Create `lib/analysis/deco/zhl16c.dart`:

```dart
/// ZHL-16C + Erik-Baker-GF replay engine. Walks samples one interval at
/// a time, updating each of 16 N2 + 16 He tissue compartments via the
/// Schreiner equation. Per-sample GF99 = current supersaturation as a
/// percentage of the allowed M-value gradient at that depth.
library;

import 'dart:math';
import 'dart:typed_data';

import '../../data/models/dive.dart' show DiveGasMix;
import 'replay_result.dart';
import 'schreiner.dart';
import 'tissue_model.dart';

/// Minimal interface for what the engine needs from a sample stream.
/// In production this is satisfied by the existing SampleSet; tests
/// can use a stub.
abstract class SampleStream {
  Float32List get depthMeters;
  Uint8List get gasMixIndex;
  int get sampleIntervalMs;
}

class SampleStub implements SampleStream {
  @override
  final Float32List depthMeters;
  @override
  final Uint8List gasMixIndex;
  @override
  final int sampleIntervalMs;
  SampleStub({
    required this.depthMeters,
    required this.gasMixIndex,
    required this.sampleIntervalMs,
  });
}

const double _waterVapourPressureBar = 0.0627; // alveolar at body temp
const double _surfaceAtmBar = 1.013;

class Zhl16cReplay {
  DecoReplayResult run({
    required SampleStream samples,
    required List<DiveGasMix> gasMixes,
    required int gfLow,
    required int gfHigh,
  }) {
    final n = samples.depthMeters.length;
    final gf99 = Float32List(n);
    final ceiling = Float32List(n);
    final tissueLoads = List<Float32List>.generate(
      16,
      (_) => Float32List(n),
      growable: false,
    );

    // Initialize all tissues at surface equilibrium (N2 only — He = 0).
    // PaN2 at surface = (1.013 - 0.0627) × 0.79 = 0.7503 bar.
    final pN2 = List<double>.generate(
      16,
      (_) => (_surfaceAtmBar - _waterVapourPressureBar) * 0.79,
    );
    final pHe = List<double>.filled(16, 0.0);

    final intervalSec = samples.sampleIntervalMs ~/ 1000;
    double maxGf99 = 0.0;

    for (var i = 0; i < n; i++) {
      final depth = samples.depthMeters[i];
      final ambientBar = _surfaceAtmBar + depth / 10.0;
      // Inspired (alveolar) partial pressures of inert gases.
      final mix = gasMixes[samples.gasMixIndex[i].clamp(0, gasMixes.length - 1)];
      final fO2 = mix.o2 / 100.0;
      final fHe = mix.he / 100.0;
      final fN2 = 1.0 - fO2 - fHe;
      final paN2 = (ambientBar - _waterVapourPressureBar) * fN2;
      final paHe = (ambientBar - _waterVapourPressureBar) * fHe;

      // Step each compartment.
      for (var c = 0; c < 16; c++) {
        pN2[c] = loadCompartment(
          currentLoadBar: pN2[c],
          inertGasPartialPressureBar: paN2,
          halfTimeMin: zhl16cTissues[c].halfTimeN2Min,
          intervalSeconds: intervalSec,
        );
        pHe[c] = loadCompartment(
          currentLoadBar: pHe[c],
          inertGasPartialPressureBar: paHe,
          halfTimeMin: zhl16cTissues[c].halfTimeHeMin,
          intervalSeconds: intervalSec,
        );
      }

      // GF99 + ceiling: find the most-saturated compartment.
      double worstGf = 0;
      double worstCeiling = 0;
      for (var c = 0; c < 16; c++) {
        final totalLoad = pN2[c] + pHe[c];
        // Combined a/b weighted by N2/He fractions of the current load.
        final tissueN2Frac =
            pN2[c] / max(totalLoad, 1e-9);
        final tissueHeFrac = 1.0 - tissueN2Frac;
        final a = zhl16cTissues[c].aN2 * tissueN2Frac +
            zhl16cTissues[c].aHe * tissueHeFrac;
        final b = zhl16cTissues[c].bN2 * tissueN2Frac +
            zhl16cTissues[c].bHe * tissueHeFrac;
        // M(P_amb) = a + P_amb / b  (Bühlmann's linearised form)
        // GF99 = (load - P_amb) / (M(P_amb) - P_amb)
        final mValueAtDepth = a + ambientBar / b;
        final allowed = mValueAtDepth - ambientBar;
        final supersaturation = totalLoad - ambientBar;
        final gf = allowed > 0 ? (supersaturation / allowed) * 100.0 : 0.0;
        if (gf > worstGf) worstGf = gf;
        tissueLoads[c][i] = ((totalLoad / mValueAtDepth) * 100.0).toDouble();
        // Compute ceiling for this compartment: depth at which load = M
        // M(P) = a + P/b → P = (load - a) * b
        final pCeilingBar = (totalLoad - a) * b;
        final ceilingForC = (pCeilingBar - _surfaceAtmBar) * 10.0;
        if (ceilingForC > worstCeiling) worstCeiling = ceilingForC;
      }
      gf99[i] = worstGf;
      ceiling[i] = worstCeiling < 0 ? 0 : worstCeiling;
      if (worstGf > maxGf99) maxGf99 = worstGf;
    }

    // Surface GF = GF99 if we ascended to the surface from final sample state.
    // Approximation: take the worst compartment's load at surface ambient (1.013).
    double surfaceGf = 0;
    for (var c = 0; c < 16; c++) {
      final totalLoad = pN2[c] + pHe[c];
      final a = zhl16cTissues[c].aN2 * (pN2[c] / max(totalLoad, 1e-9)) +
          zhl16cTissues[c].aHe * (pHe[c] / max(totalLoad, 1e-9));
      final b = zhl16cTissues[c].bN2 * (pN2[c] / max(totalLoad, 1e-9)) +
          zhl16cTissues[c].bHe * (pHe[c] / max(totalLoad, 1e-9));
      final mSurface = a + _surfaceAtmBar / b;
      final allowed = mSurface - _surfaceAtmBar;
      final supersat = totalLoad - _surfaceAtmBar;
      final gf = allowed > 0 ? (supersat / allowed) * 100.0 : 0.0;
      if (gf > surfaceGf) surfaceGf = gf;
    }

    return DecoReplayResult(
      gf99Series: gf99,
      ceilingMeters: ceiling,
      tissueLoadsPct: tissueLoads,
      surfaceGfFinal: surfaceGf,
      maxGf99: maxGf99,
      algorithm: DecoAlgorithm.zhl16c,
      gfLow: gfLow,
      gfHigh: gfHigh,
    );
  }
}
```

(Note: the linear GF interpolation between gfLow and gfHigh isn't applied here — the spec says we display GF99 directly, not the GF-allowed-curve. The gfLow/gfHigh values are recorded for cache-key purposes and for future ceiling-clamping work.)

- [ ] **Step 4: Run tests + analyze + commit**

```bash
flutter test test/analysis/deco/zhl16c_test.dart  # 5/5 pass
flutter analyze  # clean
git add lib/analysis/deco/zhl16c.dart lib/analysis/deco/replay_result.dart test/analysis/deco/zhl16c_test.dart
git commit -m "$(cat <<'EOF'
feat(analysis): ZHL-16C replay engine + DecoReplayResult type

Per-sample tissue loading via Schreiner; computes GF99 + ceiling +
16-compartment load curves + Surface GF + Max GF aggregates.
SampleStream interface kept minimal so tests can stub it. Combined
a/b weighted by current N2/He fractions per compartment (standard
Subsurface approach).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: VPM-B constants + engine

**Files:**
- Create: `lib/analysis/deco/vpmb_constants.dart`
- Create: `lib/analysis/deco/vpmb.dart`
- Create: `test/analysis/deco/vpmb_test.dart`

- [ ] **Step 1: Write failing tests for vpmb_test.dart**

Mirror the ZHL-16C tests (basic invariants, length checks, algorithm field), substituting `VpmbReplay` for `Zhl16cReplay` and passing `conservatism: 2`. Add tests that:
- Higher conservatism → smaller maxGf99 on the same dive
- Conservatism 0 outputs ≥ conservatism 4 outputs (more allowed supersaturation)

- [ ] **Step 2: Implement `vpmb_constants.dart`**

Lift VPM-B's initial critical radii (`R0_N2`, `R0_He`) and the conservatism-level reduction factors from Subsurface's `core/deco.cpp` (search for `vpmb` or `crit_radius`). 16 entries per gas. Hardcode as `const List<double>`.

- [ ] **Step 3: Implement `vpmb.dart`**

VPM-B is more involved than ZHL-16C. The integration loop is the same Schreiner-based compartment update, but the ceiling derives from a bubble-model rather than M-values. Conservatism modifies the allowed supersaturation via the "set point" reduction.

Implementation strategy: port the relevant section of Subsurface's `core/deco.cpp::vpmb_*` functions function-by-function. The math is documented in the Yount-Hoffman papers and Subsurface's own commit log.

For a v1, the simpler `boyles_law_compensation = false` path is sufficient. Boyles-law compensation is a known refinement we can add later.

A faithful basic implementation per sample:
1. Update N2 + He compartments via Schreiner (same as ZHL-16C).
2. On ascent, regenerate critical bubble radii per compartment.
3. From critical radii + conservatism reduction, compute the allowed supersaturation per compartment.
4. GF99 equivalent = `(current_supersaturation / allowed_supersaturation) × 100`. Ceiling derived similarly.

This is non-trivial. Budget: ~150 lines of Dart matching the Subsurface algorithm.

- [ ] **Step 4: Run tests + analyze + commit**

```bash
flutter test test/analysis/deco/vpmb_test.dart  # expect pass
flutter analyze  # clean
git add lib/analysis/deco/vpmb_constants.dart lib/analysis/deco/vpmb.dart test/analysis/deco/vpmb_test.dart
git commit -m "$(cat <<'EOF'
feat(analysis): VPM-B replay engine

Bubble model with five conservatism levels (0-4) reducing the allowed
supersaturation per compartment. Initial critical radii lifted from
Subsurface core/deco.cpp. Same Schreiner-based compartment loading as
ZHL-16C; differs in how the supersaturation limit is derived (bubble
nucleation theory vs Bühlmann linear M-values).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: ReplayEngine orchestrator + LRU cache

**Files:**
- Create: `lib/analysis/deco/replay_engine.dart`
- Create: `test/analysis/deco/replay_engine_test.dart`

- [ ] **Step 1: Write failing tests for the orchestrator**

Test cases:
1. `replay()` returns a `DecoReplayResult` matching the algorithm parameter
2. Same `(diveId, algorithm, vpmbConservatism, gfLow, gfHigh)` returns the cached result (verify via a counter wrapping the algorithm)
3. Different algorithm → cache miss
4. Different VPM-B conservatism → cache miss
5. LRU eviction when more than 16 entries cached

- [ ] **Step 2: Implement `replay_engine.dart`**

```dart
class DecoReplayEngine {
  static const int _maxCacheEntries = 16;
  final LinkedHashMap<_CacheKey, DecoReplayResult> _cache = LinkedHashMap();

  DecoReplayResult replay({
    required String diveId,
    required SampleStream samples,
    required List<DiveGasMix> gasMixes,
    required DecoAlgorithm algorithm,
    int? vpmbConservatism,
    int? gfLow,
    int? gfHigh,
  }) {
    final key = _CacheKey(diveId, algorithm, vpmbConservatism, gfLow, gfHigh);
    final cached = _cache.remove(key);
    if (cached != null) {
      _cache[key] = cached; // re-insert at end (LRU)
      return cached;
    }
    final result = switch (algorithm) {
      DecoAlgorithm.zhl16c => Zhl16cReplay().run(
          samples: samples, gasMixes: gasMixes,
          gfLow: gfLow ?? 30, gfHigh: gfHigh ?? 85),
      DecoAlgorithm.vpmb => VpmbReplay().run(
          samples: samples, gasMixes: gasMixes,
          conservatism: vpmbConservatism ?? 2),
    };
    if (_cache.length >= _maxCacheEntries) {
      _cache.remove(_cache.keys.first); // evict LRU
    }
    _cache[key] = result;
    return result;
  }

  /// Test helper — bypass the cache for assertions about call count.
  int get cacheSize => _cache.length;
  void clearCache() => _cache.clear();
}

class _CacheKey {
  final String diveId;
  final DecoAlgorithm algorithm;
  final int? vpmbConservatism;
  final int? gfLow;
  final int? gfHigh;
  const _CacheKey(this.diveId, this.algorithm, this.vpmbConservatism, this.gfLow, this.gfHigh);
  @override
  bool operator ==(Object other) => other is _CacheKey
      && other.diveId == diveId
      && other.algorithm == algorithm
      && other.vpmbConservatism == vpmbConservatism
      && other.gfLow == gfLow
      && other.gfHigh == gfHigh;
  @override
  int get hashCode => Object.hash(diveId, algorithm, vpmbConservatism, gfLow, gfHigh);
}
```

- [ ] **Step 3: Run tests + analyze + commit**

```bash
flutter test test/analysis/deco/replay_engine_test.dart  # all pass
git add lib/analysis/deco/replay_engine.dart test/analysis/deco/replay_engine_test.dart
git commit -m "$(cat <<'EOF'
feat(analysis): DecoReplayEngine orchestrator + LRU cache

Dispatches to ZHL-16C or VPM-B based on the algorithm parameter.
LRU cache keyed by (diveId, algorithm, vpmbConservatism, gfLow,
gfHigh) with a 16-entry cap. Test helpers expose cache size +
clear() for assertions.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Schema migration — `display_deco_algorithm` column

**Files:**
- Create: `supabase/migrations/0010_display_deco_algorithm.sql`
- Modify: `lib/data/db/database.dart` (schema version bump + column)
- Modify: `lib/data/models/annotation.dart` (model field)
- Modify: `lib/data/db/dive_annotations_dao.dart` (read/upsert plumbing)
- Modify: `infra/powersync-sync-rules.yaml` (add column to synced list)

- [ ] **Step 1: SQL migration**

Create `supabase/migrations/0010_display_deco_algorithm.sql`:

```sql
ALTER TABLE dive_annotations
ADD COLUMN display_deco_algorithm TEXT;
COMMENT ON COLUMN dive_annotations.display_deco_algorithm IS
  'User per-dive override of which deco algorithm to display. '
  'Values: ''zhl16c'' or ''vpmb''. NULL = use default (zhl16c).';
```

- [ ] **Step 2: Drift schema update**

Open `lib/data/db/database.dart`. Find `DiveAnnotationsTable`. Add the column:

```dart
TextColumn get displayDecoAlgorithm => text().nullable()();
```

Bump the schema version (find current `int get schemaVersion`, increment by 1). Add the migration callback:

```dart
case <new_version>:
  await m.addColumn(diveAnnotationsTable, diveAnnotationsTable.displayDecoAlgorithm);
  break;
```

- [ ] **Step 3: Model field**

Open `lib/data/models/annotation.dart`. Add to `DiveAnnotation`:

```dart
final String? displayDecoAlgorithm;
```

Update the constructor, `copyWith`, and any `fromRow`/`toCompanion` builders to plumb the field.

- [ ] **Step 4: DAO plumbing**

Open `lib/data/db/dive_annotations_dao.dart`. Find the `upsert` method and the `getForDive` (or equivalent) read path. Plumb the new field through both.

- [ ] **Step 5: PowerSync sync rule**

Open `infra/powersync-sync-rules.yaml`. Find the `dive_annotations` rule. Add `display_deco_algorithm` to the column list.

- [ ] **Step 6: Run analyze + tests**

```bash
flutter analyze  # clean
flutter test  # full suite, including drift-migration tests
```

(Note: Supabase + PowerSync deploy of the migration is a separate operational step — flag in the commit message.)

- [ ] **Step 7: Commit**

```bash
git add supabase/migrations/0010_display_deco_algorithm.sql lib/data/db/database.dart lib/data/models/annotation.dart lib/data/db/dive_annotations_dao.dart infra/powersync-sync-rules.yaml
git commit -m "$(cat <<'EOF'
feat(db): dive_annotations.display_deco_algorithm column

Per-dive override of the deco algorithm to display. Nullable TEXT
('zhl16c' or 'vpmb'; NULL = default ZHL-16C). Drift schema bumped;
PowerSync sync rule extended.

Deploy step (manual): apply 0010 to Supabase + push the new
powersync-sync-rules.yaml to the PowerSync dashboard.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: SettingsNotifier extension — `vpmbConservatism`

**Files:**
- Modify: `lib/ui/notifiers/settings_notifier.dart`
- Modify: `test/ui/notifiers/settings_notifier_test.dart`

Standard pattern from Track 4. Add `int _vpmbConservatism = 2` field, getter, setter (clamps 0–4), persist under `vpmb_conservatism`. Add 4 round-trip tests (default 2, clamp negatives → 0, clamp >4 → 4, persist across reload).

Commit message:
```
feat(settings): persist vpmbConservatism (default 2, range 0-4)
```

---

## Task 7: DiveAnnotationsNotifier — algorithm getter/setter

**Files:**
- Modify: `lib/ui/notifiers/dive_annotations_notifier.dart`

Add `String get displayDecoAlgorithm => _annotation.displayDecoAlgorithm ?? 'zhl16c';` and `Future<void> setDisplayDecoAlgorithm(String v)` that updates the local model + marks dirty (the dirty flag triggers the existing save flow).

Add unit tests for the getter/setter.

Commit:
```
feat(ui): DiveAnnotationsNotifier exposes displayDecoAlgorithm
```

---

## Task 8: TraceType extensions — `gf99` + `ceiling` segments

**Files:**
- Modify: `lib/ui/widgets/trace_segmented_bar.dart`
- Modify: `test/ui/widgets/trace_segmented_bar_test.dart`

(Same pattern as Track B Task 4.) Extend the enum + `_segmentData`, bump the "renders N segments" test count (now 10 if Track B already added density+end; otherwise 8). Add toggle tests for both new segments.

Commit:
```
feat(ui): TraceSegmentedBar adds GF99 + Ceiling segments
```

---

## Task 9: ProfileChart renders GF99 + Ceiling traces

**Files:**
- Modify: `lib/ui/widgets/profile_chart.dart`

The chart now needs access to `DecoReplayResult` to render the new traces. Pass the result in via a new optional parameter (`DecoReplayResult? decoReplay`). In the painter:
- GF99: render as a single-colour line (e.g. `Color(0xFF9333EA)` violet) scaled to the existing right axis from 0 to 150%. Replace the right-axis labels when GF99 is visible: 0%, 50%, 100%, 150% labels along the right edge.
- Ceiling: render as a dashed line on the depth axis (above the depth fill). Colour: `Color(0xFFEAB308)` amber.

The caller (`DiveDetailScreen`) computes `decoReplay` via the engine and passes it in only when `gf99` or `ceiling` is in `visibleTraces`.

Commit:
```
feat(ui): ProfileChart renders GF99 + Ceiling traces when toggled
```

---

## Task 10: Surface GF + Max GF StatTiles

**Files:**
- Modify: `lib/ui/screens/dive_detail_screen.dart` (`_buildStatsRow`)

Add two new tiles populated from `decoReplay.surfaceGfFinal` and `decoReplay.maxGf99`. Colour-grade: green ≤ `dive.gfHigh ?? 85`, orange between gfHigh and 100, red > 100. (Use the StatTile `valueColor` parameter added in Track B Task 6.)

Commit:
```
feat(ui): Surface GF + Max GF stat tiles colour-graded
```

---

## Task 11: Inline algorithm dropdown

**Files:**
- Modify: `lib/ui/screens/dive_detail_screen.dart`

Add a small `DropdownButton<String>` above the segmented bar, value bound to `_annotationsNotifier.displayDecoAlgorithm`. Items: `'zhl16c' → 'ZHL-16C'`, `'vpmb' → 'VPM-B'`. `onChanged` calls `_annotationsNotifier.setDisplayDecoAlgorithm(value)` which marks dirty and triggers a chart rebuild via the existing ListenableBuilder.

Commit:
```
feat(ui): inline algorithm dropdown above the segmented bar
```

---

## Task 12: Tissue saturation heatmap widget

**Files:**
- Create: `lib/ui/widgets/tissue_saturation_heatmap.dart`
- Create: `test/ui/widgets/tissue_saturation_heatmap_test.dart`

A `CustomPaint` widget that consumes `DecoReplayResult.tissueLoadsPct` (16 × N). 16 horizontal bands, x-axis = dive time, colour per pixel from the band classifier:
- `<70%` → blue `#3B82F6`
- `70–95%` → yellow `#FACC15`
- `95–100%` → orange `#F97316`
- `>100%` → red `#DC2626`

Widget tests: renders 16 bands, takes correct height, colour-codes correctly for known input values.

Commit:
```
feat(ui): TissueSaturationHeatmap widget
```

---

## Task 13: Wire heatmap as collapsible section on dive detail

**Files:**
- Modify: `lib/ui/screens/dive_detail_screen.dart` (Details tab)
- Modify: `lib/ui/notifiers/settings_notifier.dart` (`tissueHeatmapExpanded` field)

Add a collapsible section below the chart with header `Tissue saturation [ZHL-16C / VPM-B] ▾`. Tap expands; state persists via a new `tissueHeatmapExpanded` Settings field (default false). When expanded, render `TissueSaturationHeatmap(replay: decoReplay)`.

Commit:
```
feat(ui): tissue saturation heatmap collapsible section
```

---

## Definition of done

After Task 13 commits:
1. `flutter analyze` reports zero issues
2. `flutter test` passes the full suite (target: existing + ~50 new tests across all 13 tasks)
3. Manual smoke against the user's own dives:
   - Open a CCR trimix dive, see plausible GF99 + ceiling + heatmap on ZHL-16C
   - Switch the inline dropdown to VPM-B, see numbers shift, dropdown selection persists
   - Bump VPM-B conservatism in Settings, see it reflect on the dive
   - Surface GF + Max GF tiles colour-graded against the dive's gfHigh
4. Thirteen commits land on `main`
5. Supabase migration 0010 applied + PowerSync sync rules deployed (manual operational step noted in Task 5 commit message)
