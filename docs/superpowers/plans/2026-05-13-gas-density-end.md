# Gas Density + END Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add gas-density and END as two new toggleable chart traces, colour-banded by their safety thresholds, plus two new max-value StatTiles in the row below the chart. Both calculations are per-sample on the active gas mix.

**Architecture:** Two new pure-function analysis modules (`gas_density.dart`, `end.dart`) compute per-sample value series from a `SampleSet` + the dive's gas-mix table. ProfileChart consumes the series and renders each segment in its band's colour. StatTiles read max-of-series + apply the same band logic to colour the text. END has a Settings toggle for the formula choice (N₂ + O₂ count vs N₂ only).

**Tech Stack:** Flutter, flutter_test, dart:typed_data

**Spec:** [docs/superpowers/specs/2026-05-13-gas-density-end-design.md](../specs/2026-05-13-gas-density-end-design.md)

---

## Task 1: Build the gas-density analysis module + tests

**Files:**
- Create: `lib/analysis/gas_density.dart`
- Create: `test/analysis/gas_density_test.dart`

- [ ] **Step 1: Write failing tests**

Create `test/analysis/gas_density_test.dart`:

```dart
import 'dart:typed_data';

import 'package:ccrlogger/analysis/gas_density.dart';
import 'package:ccrlogger/data/models/dive.dart' show DiveGasMix;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('mixDensityAt1Atm', () {
    test('air ≈ 1.225 g/L', () {
      expect(mixDensityAt1Atm(0.21, 0.0), closeTo(1.225, 0.01));
    });
    test('100% O₂ = 1.314 g/L', () {
      expect(mixDensityAt1Atm(1.0, 0.0), closeTo(1.314, 0.001));
    });
    test('18/45 trimix ≈ 0.74 g/L', () {
      expect(mixDensityAt1Atm(0.18, 0.45), closeTo(0.74, 0.01));
    });
    test('100% He = 0.166 g/L', () {
      expect(mixDensityAt1Atm(0.0, 1.0), closeTo(0.166, 0.001));
    });
  });

  group('density band classification', () {
    test('returns green below 5.2 g/L', () {
      expect(densityBand(5.0), DensityBand.green);
      expect(densityBand(5.199), DensityBand.green);
    });
    test('returns orange between 5.2 and 5.7', () {
      expect(densityBand(5.2), DensityBand.orange);
      expect(densityBand(5.5), DensityBand.orange);
      expect(densityBand(5.699), DensityBand.orange);
    });
    test('returns red at or above 5.7', () {
      expect(densityBand(5.7), DensityBand.red);
      expect(densityBand(6.5), DensityBand.red);
    });
  });

  group('computeDensitySeries', () {
    test('air at 30 m ≈ 4.9 g/L', () {
      // SampleSet stub: 1 sample at 30 m, mix index 0.
      // 4 bar ambient × 1.225 g/L = 4.9 g/L.
      final depth = Float32List.fromList([30.0]);
      final mixIndex = Uint8List.fromList([0]);
      final gasMixes = [DiveGasMix(o2: 21, he: 0, diluent: true)];
      final series = computeDensitySeries(
        depthMeters: depth,
        gasMixIndex: mixIndex,
        gasMixes: gasMixes,
        atmosphericPressureMbar: 1013,
      );
      expect(series.length, 1);
      expect(series[0], closeTo(4.9, 0.05));
    });

    test('18/45 trimix at 60 m ≈ 5.2 g/L', () {
      // 7 bar × 0.74 g/L = 5.18 g/L
      final depth = Float32List.fromList([60.0]);
      final mixIndex = Uint8List.fromList([0]);
      final gasMixes = [DiveGasMix(o2: 18, he: 45, diluent: true)];
      final series = computeDensitySeries(
        depthMeters: depth,
        gasMixIndex: mixIndex,
        gasMixes: gasMixes,
        atmosphericPressureMbar: 1013,
      );
      expect(series[0], closeTo(5.2, 0.05));
    });

    test('EAN 50 at 6 m ≈ 2.0 g/L', () {
      final depth = Float32List.fromList([6.0]);
      final mixIndex = Uint8List.fromList([0]);
      final gasMixes = [DiveGasMix(o2: 50, he: 0, diluent: false)];
      final series = computeDensitySeries(
        depthMeters: depth,
        gasMixIndex: mixIndex,
        gasMixes: gasMixes,
        atmosphericPressureMbar: 1013,
      );
      expect(series[0], closeTo(2.0, 0.05));
    });
  });
}
```

- [ ] **Step 2: Run to confirm failure**

Run: `flutter test test/analysis/gas_density_test.dart`
Expected: FAIL — compile error, module doesn't exist.

- [ ] **Step 3: Implement the module**

Create `lib/analysis/gas_density.dart`:

```dart
/// Per-sample gas-density computation for the active gas mix at each
/// depth. Used as a chart trace (colour-banded by safety thresholds)
/// and a max-value StatTile on the dive detail screen.
library;

import 'dart:typed_data';

import '../data/models/dive.dart' show DiveGasMix;

/// Standard atmospheric pressure constant (mbar) used as a fallback.
const int kStandardAtmosphericPressureMbar = 1013;

/// Density of each pure gas at 1 ATA (g/L), per the Anthony/Mitchell
/// CCR-density safety paper.
const double kO2DensityAt1Atm = 1.314;
const double kN2DensityAt1Atm = 1.165;
const double kHeDensityAt1Atm = 0.166;

/// Density colour-band thresholds (g/L). Per Track B brainstorm —
/// standard tech (matches Shearwater's own warning at 5.7).
const double kDensityOrangeThreshold = 5.2;
const double kDensityRedThreshold = 5.7;

enum DensityBand { green, orange, red }

DensityBand densityBand(double densityGramsPerLitre) {
  if (densityGramsPerLitre >= kDensityRedThreshold) return DensityBand.red;
  if (densityGramsPerLitre >= kDensityOrangeThreshold) return DensityBand.orange;
  return DensityBand.green;
}

/// Weighted gas density at 1 ATA. [o2Fraction] and [heFraction] are
/// 0.0–1.0 (not percentages). N₂ is inferred as the remainder.
double mixDensityAt1Atm(double o2Fraction, double heFraction) {
  final n2Fraction = 1.0 - o2Fraction - heFraction;
  return o2Fraction * kO2DensityAt1Atm +
      heFraction * kHeDensityAt1Atm +
      n2Fraction * kN2DensityAt1Atm;
}

/// Per-sample gas density (g/L) at ambient pressure. Walks
/// [depthMeters] and [gasMixIndex] in parallel; multiplies the mix's
/// 1 ATA density by ambient pressure (atm + depth/10).
Float32List computeDensitySeries({
  required Float32List depthMeters,
  required Uint8List gasMixIndex,
  required List<DiveGasMix> gasMixes,
  required int atmosphericPressureMbar,
}) {
  assert(depthMeters.length == gasMixIndex.length);
  final out = Float32List(depthMeters.length);
  // Pre-compute density at 1 ATA per mix — avoid recomputing in the loop.
  final densityByMix = Float32List(gasMixes.length);
  for (var i = 0; i < gasMixes.length; i++) {
    densityByMix[i] = mixDensityAt1Atm(
      gasMixes[i].o2 / 100.0,
      gasMixes[i].he / 100.0,
    );
  }
  final atmBar = atmosphericPressureMbar / 1000.0;
  for (var i = 0; i < depthMeters.length; i++) {
    final mixIdx = gasMixIndex[i];
    if (mixIdx >= densityByMix.length) {
      out[i] = double.nan;
      continue;
    }
    final ambientBar = atmBar + depthMeters[i] / 10.0;
    out[i] = densityByMix[mixIdx] * ambientBar;
  }
  return out;
}
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/analysis/gas_density_test.dart`
Expected: 11/11 pass.

- [ ] **Step 5: Run full suite + analyze + commit**

Run: `flutter analyze` → expect `No issues found!`
Run: `flutter test` → expect full suite passes.

```bash
git add lib/analysis/gas_density.dart test/analysis/gas_density_test.dart
git commit -m "$(cat <<'EOF'
feat(analysis): per-sample gas-density computation

mixDensityAt1Atm weighted-sum for O2/N2/He. computeDensitySeries
walks depth + active mix per sample, returns a Float32List of g/L
values. Three colour-band thresholds (green/orange/red at 5.2/5.7
g/L) matching standard tech-instructor teaching. Pre-computes mix
density once per mix to avoid redundant work in the per-sample loop.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Build the END analysis module + tests

**Files:**
- Create: `lib/analysis/end.dart`
- Create: `test/analysis/end_test.dart`

- [ ] **Step 1: Write failing tests**

Create `test/analysis/end_test.dart`:

```dart
import 'dart:typed_data';

import 'package:ccrlogger/analysis/end.dart';
import 'package:ccrlogger/data/models/dive.dart' show DiveGasMix;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('END band classification', () {
    test('green below 30 m', () {
      expect(endBand(29.9), EndBand.green);
      expect(endBand(0), EndBand.green);
    });
    test('orange 30–40 m', () {
      expect(endBand(30), EndBand.orange);
      expect(endBand(35), EndBand.orange);
      expect(endBand(39.9), EndBand.orange);
    });
    test('red at or above 40 m', () {
      expect(endBand(40), EndBand.red);
      expect(endBand(55), EndBand.red);
    });
  });

  group('computeEndSeries — formula A (N2 + O2 count)', () {
    test('air at 30 m → END = 30 m', () {
      final series = computeEndSeries(
        depthMeters: Float32List.fromList([30]),
        gasMixIndex: Uint8List.fromList([0]),
        gasMixes: [DiveGasMix(o2: 21, he: 0, diluent: true)],
        countsOxygen: true,
      );
      expect(series[0], closeTo(30.0, 0.1));
    });

    test('18/45 trimix at 60 m → END ≈ 28.5 m', () {
      // (60 + 10) × (1 - 0.45) - 10 = 70 × 0.55 - 10 = 28.5
      final series = computeEndSeries(
        depthMeters: Float32List.fromList([60]),
        gasMixIndex: Uint8List.fromList([0]),
        gasMixes: [DiveGasMix(o2: 18, he: 45, diluent: true)],
        countsOxygen: true,
      );
      expect(series[0], closeTo(28.5, 0.1));
    });
  });

  group('computeEndSeries — formula B (N2 only, GUE)', () {
    test('18/45 trimix at 60 m → END ≈ 22.8 m', () {
      // (60 + 10) × (0.37 / 0.79) - 10 = 70 × 0.468 - 10 = 22.78
      final series = computeEndSeries(
        depthMeters: Float32List.fromList([60]),
        gasMixIndex: Uint8List.fromList([0]),
        gasMixes: [DiveGasMix(o2: 18, he: 45, diluent: true)],
        countsOxygen: false,
      );
      expect(series[0], closeTo(22.8, 0.1));
    });

    test('air at 30 m → END = 30 m (N2 ≈ 0.79, so formula collapses to depth)', () {
      final series = computeEndSeries(
        depthMeters: Float32List.fromList([30]),
        gasMixIndex: Uint8List.fromList([0]),
        gasMixes: [DiveGasMix(o2: 21, he: 0, diluent: true)],
        countsOxygen: false,
      );
      expect(series[0], closeTo(30.0, 0.1));
    });
  });

  group('computeEndSeries — clamping', () {
    test('END never goes negative — heliox at shallow depth clamps to 0', () {
      // 5/95 trimix at 5 m: (15) × 0.05 - 10 = -9.25, clamp to 0
      final series = computeEndSeries(
        depthMeters: Float32List.fromList([5]),
        gasMixIndex: Uint8List.fromList([0]),
        gasMixes: [DiveGasMix(o2: 5, he: 95, diluent: true)],
        countsOxygen: true,
      );
      expect(series[0], greaterThanOrEqualTo(0.0));
    });
  });
}
```

- [ ] **Step 2: Run to confirm failure**

Run: `flutter test test/analysis/end_test.dart`
Expected: FAIL — module not defined.

- [ ] **Step 3: Implement the module**

Create `lib/analysis/end.dart`:

```dart
/// Per-sample equivalent narcotic depth (END) for the active gas mix
/// at each sample. Two formulas:
///
/// **Formula A** (`countsOxygen == true`, default): N₂ + O₂ both narcotic.
///   END(m) = max(0, (depth + 10) × (1 − He fraction) − 10)
///
/// **Formula B** (`countsOxygen == false`, GUE/DIR): only N₂ narcotic.
///   END(m) = max(0, (depth + 10) × (N₂ / 0.79) − 10)
library;

import 'dart:typed_data';

import '../data/models/dive.dart' show DiveGasMix;

/// END colour-band thresholds (m).
const double kEndOrangeThreshold = 30.0;
const double kEndRedThreshold = 40.0;

enum EndBand { green, orange, red }

EndBand endBand(double endMeters) {
  if (endMeters >= kEndRedThreshold) return EndBand.red;
  if (endMeters >= kEndOrangeThreshold) return EndBand.orange;
  return EndBand.green;
}

Float32List computeEndSeries({
  required Float32List depthMeters,
  required Uint8List gasMixIndex,
  required List<DiveGasMix> gasMixes,
  required bool countsOxygen,
}) {
  assert(depthMeters.length == gasMixIndex.length);
  final out = Float32List(depthMeters.length);
  // Pre-compute the narcotic factor per mix.
  final factorByMix = Float32List(gasMixes.length);
  for (var i = 0; i < gasMixes.length; i++) {
    final he = gasMixes[i].he / 100.0;
    if (countsOxygen) {
      factorByMix[i] = 1.0 - he;
    } else {
      final n2 = 1.0 - (gasMixes[i].o2 / 100.0) - he;
      factorByMix[i] = n2 / 0.79;
    }
  }
  for (var i = 0; i < depthMeters.length; i++) {
    final mixIdx = gasMixIndex[i];
    if (mixIdx >= factorByMix.length) {
      out[i] = double.nan;
      continue;
    }
    final end = (depthMeters[i] + 10.0) * factorByMix[mixIdx] - 10.0;
    out[i] = end < 0 ? 0.0 : end;
  }
  return out;
}
```

- [ ] **Step 4: Run tests + analyze + commit**

```bash
flutter test test/analysis/end_test.dart  # expect all pass
flutter analyze  # expect clean
flutter test  # expect full suite green
git add lib/analysis/end.dart test/analysis/end_test.dart
git commit -m "$(cat <<'EOF'
feat(analysis): per-sample END computation, two formulas

computeEndSeries with countsOxygen flag — true (default, US-Navy/TDI)
uses (depth+10)(1-He)-10; false (GUE/DIR) uses (depth+10)(N2/0.79)-10.
Pre-computes the narcotic factor once per mix. Clamps to 0 to avoid
negative values for heliox at shallow depths. Three-band threshold
classifier at 30/40 m.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Extend `SettingsNotifier` with `endCountsOxygen`

**Files:**
- Modify: `lib/ui/notifiers/settings_notifier.dart`
- Modify: `test/ui/notifiers/settings_notifier_test.dart`

- [ ] **Step 1: Write failing tests**

Open `test/ui/notifiers/settings_notifier_test.dart`. Add a new group at the end of `main()`:

```dart
  group('endCountsOxygen', () {
    test('defaults to true when prefs empty', () async {
      final n = SettingsNotifier();
      await n.load();
      expect(n.endCountsOxygen, isTrue);
    });

    test('setEndCountsOxygen flips and notifies', () async {
      final n = SettingsNotifier();
      await n.load();
      var notifyCount = 0;
      n.addListener(() => notifyCount++);
      await n.setEndCountsOxygen(false);
      expect(n.endCountsOxygen, isFalse);
      expect(notifyCount, 1);
    });

    test('setEndCountsOxygen no-ops on identical', () async {
      final n = SettingsNotifier();
      await n.load();
      var notifyCount = 0;
      n.addListener(() => notifyCount++);
      await n.setEndCountsOxygen(true);
      expect(notifyCount, 0);
    });

    test('endCountsOxygen persists across reload', () async {
      final n1 = SettingsNotifier();
      await n1.load();
      await n1.setEndCountsOxygen(false);
      final n2 = SettingsNotifier();
      await n2.load();
      expect(n2.endCountsOxygen, isFalse);
    });
  });
```

- [ ] **Step 2: Run to confirm failure**

Run: `flutter test test/ui/notifiers/settings_notifier_test.dart --plain-name endCountsOxygen`
Expected: FAIL — getter undefined.

- [ ] **Step 3: Extend `SettingsNotifier`**

Open `lib/ui/notifiers/settings_notifier.dart`.

Add a static key:
```dart
static const _kEndCountsOxygen = 'end_counts_oxygen';
```

Add a field:
```dart
bool _endCountsOxygen = true;
```

Add a getter:
```dart
bool get endCountsOxygen => _endCountsOxygen;
```

In `load()`, before `notifyListeners()`:
```dart
_endCountsOxygen = prefs.getBool(_kEndCountsOxygen) ?? true;
```

Add a setter method:
```dart
Future<void> setEndCountsOxygen(bool v) async {
  if (_endCountsOxygen == v) return;
  _endCountsOxygen = v;
  notifyListeners();
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_kEndCountsOxygen, v);
}
```

- [ ] **Step 4: Run tests + analyze + commit**

```bash
flutter test test/ui/notifiers/settings_notifier_test.dart  # expect all pass
flutter analyze  # clean
git add lib/ui/notifiers/settings_notifier.dart test/ui/notifiers/settings_notifier_test.dart
git commit -m "$(cat <<'EOF'
feat(settings): persist endCountsOxygen (default true)

Bool on SettingsNotifier, SharedPreferences key end_counts_oxygen.
Drives the END formula choice: true (default) treats N2+O2 narcotic
(US-Navy/TDI), false treats only N2 narcotic (GUE/DIR).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Add `TraceType.density` + `TraceType.end` to the segmented bar

**Files:**
- Modify: `lib/ui/widgets/trace_segmented_bar.dart`
- Modify: `test/ui/widgets/trace_segmented_bar_test.dart`

- [ ] **Step 1: Write failing tests**

Open `test/ui/widgets/trace_segmented_bar_test.dart`. Find the existing
`'TraceSegmentedBar renders six segments with their labels'` test and update
it to expect eight:

Replace:
```dart
testWidgets('TraceSegmentedBar renders six segments with their labels', ...
```

with:
```dart
testWidgets('TraceSegmentedBar renders eight segments with their labels', (tester) async {
  await tester.pumpWidget(wrap(TraceSegmentedBar(
    visibleTraces: const {TraceType.ppo2, TraceType.deco},
    onToggle: (_) {},
  )));
  expect(find.text('PPO2'), findsOneWidget);
  expect(find.text('Setpoint'), findsOneWidget);
  expect(find.text('Cells'), findsOneWidget);
  expect(find.text('Deco'), findsOneWidget);
  expect(find.text('Tanks'), findsOneWidget);
  expect(find.text('Gas'), findsOneWidget);
  expect(find.text('Density'), findsOneWidget);
  expect(find.text('END'), findsOneWidget);
});
```

Add a new toggle test:
```dart
testWidgets('tapping Density / END segments calls onToggle', (tester) async {
  TraceType? toggled;
  await tester.pumpWidget(wrap(TraceSegmentedBar(
    visibleTraces: const {},
    onToggle: (t) => toggled = t,
  )));
  await tester.tap(find.text('Density'));
  expect(toggled, TraceType.density);
  await tester.tap(find.text('END'));
  expect(toggled, TraceType.end);
});
```

- [ ] **Step 2: Run to confirm failure**

Run: `flutter test test/ui/widgets/trace_segmented_bar_test.dart`
Expected: FAIL — `TraceType.density` / `TraceType.end` undefined.

- [ ] **Step 3: Extend the enum + `_segmentData`**

Open `lib/ui/widgets/trace_segmented_bar.dart`.

Extend the enum (currently `TraceType { ppo2, setpoint, deco, cells, tanks, gasChanges }`):

```dart
enum TraceType { ppo2, setpoint, deco, cells, tanks, gasChanges, density, end }
```

Extend the `_segmentData` map with two new entries (use neutral monochrome dot colours since these traces don't have a single colour — they're colour-banded):

```dart
const _segmentData = <TraceType, ({String label, Color color})>{
  TraceType.ppo2: (label: 'PPO2', color: Color(0xFFFFCC66)),
  TraceType.setpoint: (label: 'Setpoint', color: Color(0xFFA0AEB6)),
  TraceType.cells: (label: 'Cells', color: Color(0xFF4ADE80)),
  TraceType.deco: (label: 'Deco', color: Color(0xFFF39C12)),
  TraceType.tanks: (label: 'Tanks', color: Color(0xFF60A5FA)),
  TraceType.gasChanges: (label: 'Gas', color: Color(0xFF60A5FA)),
  TraceType.density: (label: 'Density', color: Color(0xFFE3E6EB)),
  TraceType.end: (label: 'END', color: Color(0xFFE3E6EB)),
};
```

- [ ] **Step 4: Verify all callers of `TraceType` exhaust the new cases**

Run: `flutter analyze`
Expected: may report `non_exhaustive_switch` warnings on existing switch statements over TraceType — most likely in `profile_chart.dart` and `crosshair_tooltip.dart`. Add a default `case _:` (or explicit `case TraceType.density:` / `case TraceType.end:` placeholder rendering null) to each so the analyzer is clean.

- [ ] **Step 5: Run tests + commit**

```bash
flutter test test/ui/widgets/trace_segmented_bar_test.dart  # expect pass
flutter test  # full suite
git add lib/ui/widgets/trace_segmented_bar.dart test/ui/widgets/trace_segmented_bar_test.dart lib/ui/widgets/profile_chart.dart lib/ui/widgets/crosshair_tooltip.dart
git commit -m "$(cat <<'EOF'
feat(ui): TraceSegmentedBar gains Density + END segments

Two new TraceType enum entries, added to the right of the existing
six. Neutral monochrome dot (the per-band colour comes from the
trace itself, not the segment). Existing switch-statements on
TraceType audited for exhaustiveness; placeholder no-op cases added
where needed. Actual chart rendering of the new traces lands in
the next task.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Render density + END traces in `ProfileChart` (colour-banded)

**Files:**
- Modify: `lib/ui/widgets/profile_chart.dart`
- Modify: `test/ui/widgets/profile_chart_test.dart` (extension)

- [ ] **Step 1: Understand the existing chart's trace-painting structure**

Read `lib/ui/widgets/profile_chart.dart`. Find the `CustomPainter`'s `paint` method. Existing traces (PPO2, deco, etc.) are drawn as `Path` objects walking the samples; each trace has a single colour. We're adding two traces where the colour varies per-segment.

- [ ] **Step 2: Add per-band colour constants**

Inside `profile_chart.dart`, define the band colours as private const fields near the top:

```dart
const Color _bandGreen = Color(0xFF4ADE80);
const Color _bandOrange = Color(0xFFF59E0B);
const Color _bandRed = Color(0xFFDC2626);

Color _colorForDensityBand(DensityBand b) => switch (b) {
  DensityBand.green => _bandGreen,
  DensityBand.orange => _bandOrange,
  DensityBand.red => _bandRed,
};

Color _colorForEndBand(EndBand b) => switch (b) {
  EndBand.green => _bandGreen,
  EndBand.orange => _bandOrange,
  EndBand.red => _bandRed,
};
```

Import `gas_density.dart` and `end.dart` at the top of the file.

- [ ] **Step 3: Compute the density + END series at build time**

Locate the `ProfileChart` widget's `build` method (or wherever it constructs its painter). Add a computed series for each:

```dart
final densitySeries = visibleTraces.contains(TraceType.density)
    ? computeDensitySeries(
        depthMeters: samples.depthMeters,
        gasMixIndex: samples.gasMixIndex,
        gasMixes: gasMixes,
        atmosphericPressureMbar: 1013, // or read from dive if exposed
      )
    : null;

final endSeries = visibleTraces.contains(TraceType.end)
    ? computeEndSeries(
        depthMeters: samples.depthMeters,
        gasMixIndex: samples.gasMixIndex,
        gasMixes: gasMixes,
        countsOxygen: endCountsOxygen,
      )
    : null;
```

Pass both into the painter's constructor.

- [ ] **Step 4: Paint the traces**

Inside the painter's `paint`, after the existing trace draws, add:

```dart
// Density trace — colour banded per-segment.
if (densitySeries != null) {
  // Density y-axis: implicit. Draw scaled to 0–7 g/L on the right
  // edge; share with PPO2's right axis but at a different scale
  // (PPO2 0–2 bar, density 0–7 g/L).
  for (var i = 1; i < densitySeries!.length; i++) {
    final d0 = densitySeries![i - 1];
    final d1 = densitySeries![i];
    if (d0.isNaN || d1.isNaN) continue;
    final band = densityBand((d0 + d1) / 2);
    paint.color = _colorForDensityBand(band);
    paint.strokeWidth = 1.6;
    paint.style = PaintingStyle.stroke;
    final x0 = chartLeftPad + (i - 1) / (sampleCount - 1) * chartWidth;
    final x1 = chartLeftPad + i / (sampleCount - 1) * chartWidth;
    // Map density to y: 0 = top of chart, 7 g/L = bottom
    final y0 = (d0 / 7.0) * chartHeight;
    final y1 = (d1 / 7.0) * chartHeight;
    canvas.drawLine(Offset(x0, y0), Offset(x1, y1), paint);
  }
}

// END trace — colour banded per-segment, shares depth axis.
if (endSeries != null) {
  for (var i = 1; i < endSeries!.length; i++) {
    final e0 = endSeries![i - 1];
    final e1 = endSeries![i];
    if (e0.isNaN || e1.isNaN) continue;
    final band = endBand((e0 + e1) / 2);
    paint.color = _colorForEndBand(band);
    paint.strokeWidth = 1.6;
    paint.style = PaintingStyle.stroke;
    final x0 = chartLeftPad + (i - 1) / (sampleCount - 1) * chartWidth;
    final x1 = chartLeftPad + i / (sampleCount - 1) * chartWidth;
    // END uses the depth axis — same mapping as the depth trace.
    final y0 = (e0 / maxDepthMeters) * depthChartHeight;
    final y1 = (e1 / maxDepthMeters) * depthChartHeight;
    canvas.drawLine(Offset(x0, y0), Offset(x1, y1), paint);
  }
}
```

(Exact axis variable names depend on the existing painter — adapt the pattern.)

- [ ] **Step 5: Update profile chart tests**

Open `test/ui/widgets/profile_chart_test.dart`. Add a test:

```dart
testWidgets('ProfileChart with TraceType.density visible builds without error',
    (tester) async {
  // existing test scaffolding pattern + Set<TraceType>{TraceType.density}
  // assertion: just that the chart renders, no exception
});
```

- [ ] **Step 6: Run analyze + tests + commit**

```bash
flutter analyze  # clean
flutter test  # full suite passes
git add lib/ui/widgets/profile_chart.dart test/ui/widgets/profile_chart_test.dart
git commit -m "$(cat <<'EOF'
feat(ui): render Density + END traces colour-banded on the chart

Each per-sample segment drawn in its band colour (green/orange/red).
Density mapped to implicit 0-7 g/L scale; END shares the depth axis
(always at-or-shallower-than current depth). Series computed at build
time when the trace is in visibleTraces; recomputed via the existing
ListenableBuilder on SettingsNotifier when endCountsOxygen flips.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Add `Max ρ` + `Max END` StatTiles to the stats row

**Files:**
- Modify: `lib/ui/screens/dive_detail_screen.dart` (`_buildStatsRow`)

- [ ] **Step 1: Add the two tiles**

Open `lib/ui/screens/dive_detail_screen.dart`. Find `_buildStatsRow`. After the existing tile list construction, compute the max density and max END from the same series the chart uses (or recompute — cheap):

```dart
// At the top of _buildStatsRow, after the existing series are computed:
final densitySeries = computeDensitySeries(
  depthMeters: samples.depthMeters,
  gasMixIndex: samples.gasMixIndex,
  gasMixes: gasMixes,
  atmosphericPressureMbar: 1013,
);
final endSeries = computeEndSeries(
  depthMeters: samples.depthMeters,
  gasMixIndex: samples.gasMixIndex,
  gasMixes: gasMixes,
  countsOxygen: widget.settingsNotifier.endCountsOxygen,
);
var maxDensity = 0.0;
for (final d in densitySeries) {
  if (!d.isNaN && d > maxDensity) maxDensity = d;
}
var maxEnd = 0.0;
for (final e in endSeries) {
  if (!e.isNaN && e > maxEnd) maxEnd = e;
}

Color colourForDensityValue(double v) => switch (densityBand(v)) {
  DensityBand.green => const Color(0xFF4ADE80),
  DensityBand.orange => const Color(0xFFF59E0B),
  DensityBand.red => const Color(0xFFDC2626),
};
Color colourForEndValue(double v) => switch (endBand(v)) {
  EndBand.green => const Color(0xFF4ADE80),
  EndBand.orange => const Color(0xFFF59E0B),
  EndBand.red => const Color(0xFFDC2626),
};
```

Add to the `cells` list after the existing tiles, in this order: density tile first, then END tile:

```dart
StatTile(
  label: 'Max ρ',
  unit: 'g/L',
  value: maxDensity.toStringAsFixed(1),
  valueColor: colourForDensityValue(maxDensity),
),
StatTile(
  label: 'Max END',
  unit: 'm',
  value: maxEnd.round().toString(),
  valueColor: colourForEndValue(maxEnd),
),
```

(If `StatTile` doesn't currently have a `valueColor` parameter, add one — default null, when set overrides the existing colour). That's a small additive change to the StatTile widget.

- [ ] **Step 2: Run analyze + tests + manual smoke**

Run: `flutter analyze` → clean.
Run: `flutter test` → full suite passes.

Manual smoke on macOS:
- Open a CCR trimix dive — see `Max ρ` and `Max END` tiles in the stats row, colour-graded appropriately
- Toggle Density on in the segmented bar — see the trace appear, colour-banded
- Toggle END on — see the trace appear
- Flip "Count O₂ as narcotic in END" in Settings → END trace + tile values shift accordingly

- [ ] **Step 3: Commit**

```bash
git add lib/ui/screens/dive_detail_screen.dart lib/ui/components/stat_tile.dart
git commit -m "$(cat <<'EOF'
feat(ui): Max ρ + Max END StatTiles colour-graded in the stats row

Two new tiles after the existing seven. Density (g/L, 1 decimal) and
END (m, rounded). Value text colour-graded by the same thresholds the
chart trace uses. StatTile gains an optional valueColor override.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: Settings UI for the END formula toggle

**Files:**
- Modify: `lib/ui/screens/settings_screen.dart`

- [ ] **Step 1: Add the SwitchTile**

Find an appropriate place in the Settings list (under "Graph" subsection if it exists; otherwise create one). Add:

```dart
ListenableBuilder(
  listenable: widget.notifier,
  builder: (context, _) {
    return SwitchListTile(
      title: const Text('Count O₂ as narcotic in END'),
      subtitle: const Text(
          'On: N₂ + O₂ both count (TDI/IANTD/US-Navy). Off: only N₂ counts (GUE/DIR).'),
      value: widget.notifier.endCountsOxygen,
      onChanged: (v) => widget.notifier.setEndCountsOxygen(v),
    );
  },
),
```

- [ ] **Step 2: Smoke test + commit**

Run app, navigate to Settings, flip the switch, return to a dive — END trace + Max END tile update immediately (ListenableBuilder + chart's existing settingsNotifier listener fire the rebuild).

```bash
git add lib/ui/screens/settings_screen.dart
git commit -m "$(cat <<'EOF'
feat(settings): END formula toggle in Settings

SwitchListTile with both formula labels in the subtitle for self-
documentation. Reads/writes SettingsNotifier.endCountsOxygen. Flipping
it rebuilds the chart + StatTiles immediately via the existing
ListenableBuilder.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Definition of done

After Task 7 commits:
1. `flutter analyze` reports zero issues
2. `flutter test` passes the full suite (target: existing + ~16 new tests)
3. Manual smoke tests pass:
   - Toggle Density on → see colour-banded trace on a trimix dive
   - Toggle END on → see END trace above the depth trace
   - Max ρ + Max END stat tiles present and colour-graded
   - Flip the Settings toggle → END values shift; tile colour band may shift
4. Seven commits land on `main`
