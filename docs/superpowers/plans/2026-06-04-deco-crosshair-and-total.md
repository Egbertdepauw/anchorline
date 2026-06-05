# Deco Crosshair + Total Deco Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show decompression state (stop depth/time, NDL, TTS, GF99, ceiling) at the profile crosshair, and surface two whole-dive deco numbers (time-in-deco, peak TTS) in the dive summary.

**Architecture:** Two whole-dive numbers come from pure helpers over DC-recorded sample arrays. The crosshair tooltip gains a deco row-group (DC-recorded values always; GF99/ceiling from the deco-replay engine, which the Details tab already computes and caches). A small shared `gfBandColor` unifies the GF colour language across the tooltip and the existing stat tiles.

**Tech Stack:** Flutter / Dart, `flutter_test` (unit + widget tests). No new dependencies.

---

## Branch & prerequisites

- Work on a feature branch, not `main`: `git switch -c feat/deco-crosshair-total` (or an isolated worktree created via `superpowers:using-git-worktrees`).
- The spec lives at `docs/superpowers/specs/2026-06-04-deco-crosshair-and-total-design.md` and is committed alongside the first task.
- Per-task gates: `flutter analyze` clean and `flutter test` green before each commit.

## File structure

**Create:**
- `lib/ui/theme/gf_color.dart` — shared `gfBandColor(gf, {gfHigh})`. One responsibility: the GF severity → colour mapping.
- `test/ui/theme/gf_color_test.dart` — unit tests for `gfBandColor`.
- `test/ui/widgets/crosshair_tooltip_test.dart` — widget tests for the deco row-group.

**Modify:**
- `lib/data/sample_codec/dive_stats.dart` — add `totalTimeInDecoSeconds`, `peakTtsSeconds`.
- `test/data/sample_codec/dive_stats_test.dart` — add a `deco stats` test group.
- `lib/ui/widgets/crosshair_tooltip.dart` — `decoReplay` param, `_fmtMinutes`, `_Row.divider()`, deco rows, tabular-figures value style, GF99 via `gfBandColor`.
- `lib/ui/screens/dive_detail_screen.dart` — compute replay unconditionally; pass `decoReplay` to the tooltip; add two stat tiles; route the local `colourForGf` through `gfBandColor`.
- `lib/ui/screens/fullscreen_chart_screen.dart` — pass `decoReplay` to its `CrosshairTooltip`.

---

## Task 1: Deco computation helpers

**Files:**
- Modify: `lib/data/sample_codec/dive_stats.dart` (append two top-level functions; `dart:typed_data` is already imported)
- Test: `test/data/sample_codec/dive_stats_test.dart` (append a group inside the existing `main()`)

- [ ] **Step 1: Write the failing tests**

Append this group inside `main()` in `test/data/sample_codec/dive_stats_test.dart`, immediately before the final closing `}` (after the `verticalSpeedExtremes` group). The file already imports `dart:typed_data`, the lib, and `flutter_test` — do not re-import.

```dart
  group('deco stats', () {
    test('totalTimeInDecoSeconds is 0 for a no-stop (NDL) dive', () {
      final stops = Float32List.fromList([0, 0, 0, 0]);
      expect(
        totalTimeInDecoSeconds(
            decoStopDepthMeters: stops, sampleCount: 4, sampleIntervalMs: 10000),
        0,
      );
    });

    test('totalTimeInDecoSeconds counts in-deco samples x interval', () {
      // 3 of 5 samples carry a stop depth; 10s interval -> 30s.
      final stops = Float32List.fromList([0, 6, 6, 3, 0]);
      expect(
        totalTimeInDecoSeconds(
            decoStopDepthMeters: stops, sampleCount: 5, sampleIntervalMs: 10000),
        30,
      );
    });

    test('totalTimeInDecoSeconds scales with sample interval', () {
      final stops = Float32List.fromList([6, 6, 6]);
      expect(
        totalTimeInDecoSeconds(
            decoStopDepthMeters: stops, sampleCount: 3, sampleIntervalMs: 5000),
        15,
      );
      expect(
        totalTimeInDecoSeconds(
            decoStopDepthMeters: stops, sampleCount: 3, sampleIntervalMs: 10000),
        30,
      );
    });

    test('totalTimeInDecoSeconds skips NaN stop depths (merged-dive gaps)', () {
      final stops = Float32List.fromList([6, double.nan, 6, double.nan]);
      // 2 real in-deco samples x 10s = 20s; NaNs ignored.
      expect(
        totalTimeInDecoSeconds(
            decoStopDepthMeters: stops, sampleCount: 4, sampleIntervalMs: 10000),
        20,
      );
    });

    test('peakTtsSeconds returns the maximum TTS', () {
      final tts = Int32List.fromList([0, 600, 1380, 1200, 0]);
      expect(peakTtsSeconds(ttsSeconds: tts, sampleCount: 5), 1380);
    });

    test('peakTtsSeconds is 0 when no TTS recorded', () {
      final tts = Int32List.fromList([0, 0, 0]);
      expect(peakTtsSeconds(ttsSeconds: tts, sampleCount: 3), 0);
    });
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/data/sample_codec/dive_stats_test.dart`
Expected: FAIL — compile error, `The function 'totalTimeInDecoSeconds' isn't defined` (and `peakTtsSeconds`).

- [ ] **Step 3: Implement the helpers**

Append to the end of `lib/data/sample_codec/dive_stats.dart`:

```dart
/// Total time spent in mandatory decompression, in seconds.
///
/// Counts samples carrying a non-zero deco stop depth and multiplies by the
/// sample interval. Returns 0 for a no-stop (NDL) dive. NaN stop depths
/// (merged-dive surface gaps) are skipped.
int totalTimeInDecoSeconds({
  required Float32List decoStopDepthMeters,
  required int sampleCount,
  required int sampleIntervalMs,
}) {
  if (sampleCount == 0) return 0;
  final n = sampleCount < decoStopDepthMeters.length
      ? sampleCount
      : decoStopDepthMeters.length;
  var inDeco = 0;
  for (var i = 0; i < n; i++) {
    final d = decoStopDepthMeters[i];
    if (d.isNaN || d <= 0) continue;
    inDeco++;
  }
  return inDeco * sampleIntervalMs ~/ 1000;
}

/// Peak time-to-surface reached during the dive, in seconds.
///
/// Returns the largest TTS value across the dive, or 0 if none was recorded.
int peakTtsSeconds({
  required Int32List ttsSeconds,
  required int sampleCount,
}) {
  if (sampleCount == 0) return 0;
  final n = sampleCount < ttsSeconds.length ? sampleCount : ttsSeconds.length;
  var peak = 0;
  for (var i = 0; i < n; i++) {
    if (ttsSeconds[i] > peak) peak = ttsSeconds[i];
  }
  return peak;
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/data/sample_codec/dive_stats_test.dart`
Expected: PASS (all tests, including the new `deco stats` group).

- [ ] **Step 5: Commit (include the spec doc so it rides along on the branch)**

```bash
git add lib/data/sample_codec/dive_stats.dart \
        test/data/sample_codec/dive_stats_test.dart \
        docs/superpowers/specs/2026-06-04-deco-crosshair-and-total-design.md \
        docs/superpowers/plans/2026-06-04-deco-crosshair-and-total.md
git commit -m "feat(deco): add totalTimeInDecoSeconds + peakTtsSeconds helpers" \
           -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Shared `gfBandColor` helper + refactor

**Files:**
- Create: `lib/ui/theme/gf_color.dart`
- Test: `test/ui/theme/gf_color_test.dart`
- Modify: `lib/ui/screens/dive_detail_screen.dart:1417-1422` (route local `colourForGf` through the shared helper) + its import block

- [ ] **Step 1: Write the failing test**

Create `test/ui/theme/gf_color_test.dart`:

```dart
import 'package:ccrlogger/ui/theme/gf_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('green within GF-high (boundary inclusive)', () {
    expect(gfBandColor(50, gfHigh: 85), const Color(0xFF4ADE80));
    expect(gfBandColor(85, gfHigh: 85), const Color(0xFF4ADE80));
  });

  test('amber above GF-high up to 100 (100 not yet red)', () {
    expect(gfBandColor(90, gfHigh: 85), const Color(0xFFF59E0B));
    expect(gfBandColor(100, gfHigh: 85), const Color(0xFFF59E0B));
  });

  test('red above 100', () {
    expect(gfBandColor(101, gfHigh: 85), const Color(0xFFDC2626));
  });

  test('default gfHigh is 85', () {
    expect(gfBandColor(90), const Color(0xFFF59E0B));
    expect(gfBandColor(80), const Color(0xFF4ADE80));
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/ui/theme/gf_color_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:ccrlogger/ui/theme/gf_color.dart'`.

- [ ] **Step 3: Create the helper**

Create `lib/ui/theme/gf_color.dart`:

```dart
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
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/ui/theme/gf_color_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Route the existing closure through the shared helper**

In `lib/ui/screens/dive_detail_screen.dart`, add the import alongside the other `../theme/` imports near the top of the file:

```dart
import '../theme/gf_color.dart';
```

Then replace the local closure (currently at lines 1417–1422):

```dart
    Color colourForGf(double gf) {
      final gfHighVal = (widget.dive.gfHigh ?? 85).toDouble();
      if (gf > 100) return const Color(0xFFDC2626); // red
      if (gf > gfHighVal) return const Color(0xFFF59E0B); // orange
      return const Color(0xFF4ADE80); // green
    }
```

with:

```dart
    Color colourForGf(double gf) =>
        gfBandColor(gf, gfHigh: (widget.dive.gfHigh ?? 85).toDouble());
```

The two call sites (`colourForGf(surfaceGf)`, `colourForGf(maxGf)`) are unchanged.

- [ ] **Step 6: Verify analyze + full tests (behaviour is identical, so existing tests stay green)**

Run: `flutter analyze`
Expected: `No issues found!`
Run: `flutter test`
Expected: PASS (all suites).

- [ ] **Step 7: Commit**

```bash
git add lib/ui/theme/gf_color.dart test/ui/theme/gf_color_test.dart \
        lib/ui/screens/dive_detail_screen.dart
git commit -m "refactor(deco): extract shared gfBandColor helper" \
           -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Crosshair tooltip deco row-group

**Files:**
- Modify: `lib/ui/widgets/crosshair_tooltip.dart`
- Test: `test/ui/widgets/crosshair_tooltip_test.dart` (create)

- [ ] **Step 1: Write the failing widget test**

Create `test/ui/widgets/crosshair_tooltip_test.dart`:

```dart
import 'dart:typed_data';

import 'package:ccrlogger/analysis/deco/replay_result.dart';
import 'package:ccrlogger/data/models/sample_set.dart';
import 'package:ccrlogger/ui/widgets/crosshair_tooltip.dart';
import 'package:ccrlogger/ui/widgets/trace_segmented_bar.dart' show TraceType;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

SampleSet _samples() {
  Float32List f(List<double> v) => Float32List.fromList(v);
  return SampleSet(
    diveId: 'test',
    sampleCount: 2,
    sampleIntervalMs: 10000,
    depthMeters: f([21.0, 9.0]),
    temperatureCelsius: f([11.4, 12.0]),
    ppo2Bar: f([1.30, 1.10]),
    cellMv0: f([50, 50]),
    cellMv1: f([50, 50]),
    cellMv2: f([50, 50]),
    setpointBar: f([1.30, 1.10]),
    cns: f([0.1, 0.1]),
    // index 0 = in deco; index 1 = NDL.
    decoStopDepthMeters: f([6.0, 0.0]),
    decoTimeSeconds: Int32List.fromList([720, 1080]), // 12 min stop / 18 min NDL
    ttsSeconds: Int32List.fromList([1380, 120]), // 23 min / 2 min
    gasMixIndex: Uint8List.fromList([0, 0]),
    statusFlags: Uint8List.fromList([0, 0]),
  );
}

DecoReplayResult _replay() => DecoReplayResult(
      gf99Series: Float32List.fromList([84, 40]),
      ceilingMeters: Float32List.fromList([5.4, 0.0]),
      tissueLoadsPct: const <Float32List>[],
      surfaceGfFinal: 40,
      maxGf99: 84,
      algorithm: DecoAlgorithm.zhl16c,
      gfHigh: 85,
    );

Future<void> _pump(WidgetTester tester, int index) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: CrosshairTooltip(
        samples: _samples(),
        sampleIndex: index,
        visibleTraces: const <TraceType>{},
        chartX: 10,
        chartWidth: 300,
        decoReplay: _replay(),
      ),
    ),
  ));
}

void main() {
  testWidgets('in deco: shows Stop, Stop time, TTS, Ceiling, GF99',
      (tester) async {
    await _pump(tester, 0);
    expect(find.text('Stop'), findsOneWidget);
    expect(find.text('6.0m'), findsOneWidget);
    expect(find.text('Stop time'), findsOneWidget);
    expect(find.text('12 min'), findsOneWidget);
    expect(find.text('TTS'), findsOneWidget);
    expect(find.text('23 min'), findsOneWidget);
    expect(find.text('Ceiling'), findsOneWidget);
    expect(find.text('5.4m'), findsOneWidget);
    expect(find.text('GF99'), findsOneWidget);
    expect(find.text('84%'), findsOneWidget);
    expect(find.text('NDL'), findsNothing);
  });

  testWidgets('out of deco: shows NDL, hides Stop and Ceiling',
      (tester) async {
    await _pump(tester, 1);
    expect(find.text('NDL'), findsOneWidget);
    expect(find.text('18 min'), findsOneWidget);
    expect(find.text('Stop'), findsNothing);
    expect(find.text('Ceiling'), findsNothing); // ceiling 0 -> hidden
    expect(find.text('GF99'), findsOneWidget);
    expect(find.text('40%'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/ui/widgets/crosshair_tooltip_test.dart`
Expected: FAIL — `No named parameter with the name 'decoReplay'` (param doesn't exist yet).

- [ ] **Step 3: Add the import and constructor param**

In `lib/ui/widgets/crosshair_tooltip.dart`, add to the imports (after the existing `import '../../data/models/sample_set.dart';`):

```dart
import '../../analysis/deco/replay_result.dart';
import '../theme/gf_color.dart';
```

Add the field (after `final List<DiveGasMix>? gasMixes;`):

```dart
  final DecoReplayResult? decoReplay;
```

Add the constructor param (after `this.gasMixes,`):

```dart
    this.decoReplay,
```

- [ ] **Step 4: Add the `_fmtMinutes` helper**

Add this method to the `CrosshairTooltip` class (e.g. right after `_verticalRateAt`):

```dart
  /// Deco/TTS/NDL durations are whole-minute values from the DC, stored as
  /// seconds. Render them in minutes.
  static String _fmtMinutes(int seconds) => '${(seconds / 60).round()} min';
```

- [ ] **Step 5: Insert the deco row-group after the Temp row**

In `build()`, immediately after the existing line:

```dart
    rows.add(_Row('Temp', '${samples.temperatureCelsius[i].toStringAsFixed(1)}°C'));
```

insert:

```dart
    // ── Decompression group ───────────────────────────────────────────
    final inDeco = i < samples.decoStopDepthMeters.length &&
        samples.decoStopDepthMeters[i] > 0;
    final ndlSeconds =
        i < samples.decoTimeSeconds.length ? samples.decoTimeSeconds[i] : 0;
    final ttsAt = i < samples.ttsSeconds.length ? samples.ttsSeconds[i] : 0;
    final replay = decoReplay;
    final hasDecoRows = inDeco || ndlSeconds > 0 || ttsAt > 0 || replay != null;
    if (hasDecoRows) {
      rows.add(_Row.divider());
      if (inDeco) {
        rows.add(_Row(
            'Stop', '${samples.decoStopDepthMeters[i].toStringAsFixed(1)}m'));
        rows.add(_Row('Stop time', _fmtMinutes(samples.decoTimeSeconds[i])));
      } else if (ndlSeconds > 0) {
        rows.add(_Row('NDL', _fmtMinutes(ndlSeconds)));
      }
      if (ttsAt > 0) {
        rows.add(_Row('TTS', _fmtMinutes(ttsAt)));
      }
      if (replay != null) {
        if (i < replay.ceilingMeters.length && replay.ceilingMeters[i] > 0) {
          rows.add(_Row(
              'Ceiling', '${replay.ceilingMeters[i].toStringAsFixed(1)}m'));
        }
        if (i < replay.gf99Series.length) {
          final gf = replay.gf99Series[i];
          rows.add(_Row('GF99', '${gf.round()}%',
              valueColor: gfBandColor(gf, gfHigh: (replay.gfHigh ?? 85).toDouble())));
        }
      }
    }
```

- [ ] **Step 6: Upgrade `_Row` to support a divider and a value colour**

Replace the `_Row` class at the bottom of the file:

```dart
class _Row {
  final String label, value;
  final Color? valueColor;
  final bool isDivider;
  _Row(this.label, this.value, {this.valueColor}) : isDivider = false;
  _Row.divider()
      : label = '',
        value = '',
        valueColor = null,
        isDivider = true;
}
```

- [ ] **Step 7: Render dividers, value colour, and tabular figures**

Replace the children loop inside the tooltip's `Column` (the `for (final row in rows) Padding(...)` block) with:

```dart
            for (final row in rows)
              if (row.isDivider)
                Container(
                  height: 1,
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  color: const Color(0xFF778899).withValues(alpha: 0.25),
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    ConstrainedBox(
                        constraints:
                            const BoxConstraints(minWidth: 40, maxWidth: 110),
                        child: Text(row.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Color(0xFF778899), fontSize: 10))),
                    const SizedBox(width: 6),
                    Text(row.value,
                        style: TextStyle(
                            color: row.valueColor ?? Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            fontFeatures: const [FontFeature.tabularFigures()])),
                  ]),
                )
```

(`FontFeature` is re-exported by `package:flutter/material.dart`, already imported — no extra import.)

- [ ] **Step 8: Run the widget test to verify it passes**

Run: `flutter test test/ui/widgets/crosshair_tooltip_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 9: Verify analyze + full tests**

Run: `flutter analyze`
Expected: `No issues found!`
Run: `flutter test`
Expected: PASS (all suites — existing callers still compile because `decoReplay` is optional).

- [ ] **Step 10: Commit**

```bash
git add lib/ui/widgets/crosshair_tooltip.dart \
        test/ui/widgets/crosshair_tooltip_test.dart
git commit -m "feat(deco): deco row-group in crosshair tooltip (stop/TTS/GF99/ceiling)" \
           -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Wire `decoReplay` into both tooltip call sites

**Files:**
- Modify: `lib/ui/screens/dive_detail_screen.dart:636-731` (compute replay unconditionally; pass to tooltip)
- Modify: `lib/ui/screens/fullscreen_chart_screen.dart:213-227` (pass `widget.decoReplay`)

- [ ] **Step 1: Compute the chart's `decoReplay` unconditionally**

In `lib/ui/screens/dive_detail_screen.dart`, inside the chart `LayoutBuilder` (lines ~637–661), replace this block:

```dart
                                final samples = _notifier.samples!;
                                final needsReplay =
                                    visibleTraces.contains(TraceType.gf99) ||
                                        visibleTraces
                                            .contains(TraceType.ceiling);
                                final gasMixes = _decodeGasMixes();
                                DecoReplayResult? decoReplay;
                                if (needsReplay) {
                                  final algo = _annotationsNotifier
                                              .displayDecoAlgorithm ==
                                          'vpmb'
                                      ? DecoAlgorithm.vpmb
                                      : DecoAlgorithm.zhl16c;
                                  decoReplay = _decoEngine.replay(
                                    diveId: widget.dive.id,
                                    samples: _SampleSetAdapter(samples),
                                    gasMixes: gasMixes,
                                    algorithm: algo,
                                    vpmbConservatism: widget
                                        .settingsNotifier.vpmbConservatism,
                                    gfLow: widget.dive.gfLow,
                                    gfHigh: widget.dive.gfHigh,
                                    surfacePressureBar: _surfacePressureBar,
                                  );
                                }
```

with (always compute — the engine caches by key, and `_buildStatsRow` already runs the same call, so this is a cache hit, not a second simulation):

```dart
                                final samples = _notifier.samples!;
                                final gasMixes = _decodeGasMixes();
                                final algo = _annotationsNotifier
                                            .displayDecoAlgorithm ==
                                        'vpmb'
                                    ? DecoAlgorithm.vpmb
                                    : DecoAlgorithm.zhl16c;
                                final decoReplay = _decoEngine.replay(
                                  diveId: widget.dive.id,
                                  samples: _SampleSetAdapter(samples),
                                  gasMixes: gasMixes,
                                  algorithm: algo,
                                  vpmbConservatism:
                                      widget.settingsNotifier.vpmbConservatism,
                                  gfLow: widget.dive.gfLow,
                                  gfHigh: widget.dive.gfHigh,
                                  surfacePressureBar: _surfacePressureBar,
                                );
```

`decoReplay` is now non-null `DecoReplayResult`. `ProfileChart`'s param is `DecoReplayResult?`, so passing it (line ~684 `decoReplay: decoReplay`) still compiles unchanged, and `ProfileChart` still gates trace drawing on `visibleTraces` — no visual change to the chart.

- [ ] **Step 2: Pass `decoReplay` to the dive-detail `CrosshairTooltip`**

In the same file, in the `CrosshairTooltip(...)` constructed at lines ~712–728, add `decoReplay: decoReplay,` (e.g. right after `gasMixes: _decodeGasMixes(),`):

```dart
                                      CrosshairTooltip(
                                        samples: _notifier.samples!,
                                        sampleIndex: _notifier.crosshairIndex!,
                                        visibleTraces: visibleTraces,
                                        chartX: 40 +
                                            (_notifier.crosshairIndex! /
                                                    (_notifier.samples!
                                                            .sampleCount -
                                                        1)) *
                                                (constraints.maxWidth - 84),
                                        chartWidth: constraints.maxWidth,
                                        cellsBySlot: _notifier.activeCells,
                                        tanks: _decodeTanks(),
                                        mappedCylinders:
                                            _notifier.mappedCylinders,
                                        gasMixes: _decodeGasMixes(),
                                        decoReplay: decoReplay,
                                      ),
```

- [ ] **Step 3: Pass `decoReplay` to the fullscreen `CrosshairTooltip`**

In `lib/ui/screens/fullscreen_chart_screen.dart`, in the `CrosshairTooltip(...)` at lines ~213–227, add `decoReplay: widget.decoReplay,` after `gasMixes: widget.gasMixes,`:

```dart
                  CrosshairTooltip(
                    samples: samples,
                    sampleIndex: _crosshairIndex!,
                    visibleTraces: widget.visibleTraces,
                    chartX: 40 +
                        ((_crosshairIndex! / (samples.sampleCount - 1) -
                                    _viewStart) /
                                (_viewEnd - _viewStart)) *
                            (constraints.maxWidth - 84),
                    chartWidth: constraints.maxWidth,
                    cellsBySlot: widget.cellsBySlot,
                    tanks: widget.tanks,
                    mappedCylinders: widget.mappedCylinders,
                    gasMixes: widget.gasMixes,
                    decoReplay: widget.decoReplay,
                  ),
```

- [ ] **Step 4: Verify analyze + full tests**

Run: `flutter analyze`
Expected: `No issues found!` (in particular, no "unused variable `needsReplay`" — its declaration was removed).
Run: `flutter test`
Expected: PASS (all suites, including `test/ui/screens/merged_dive_detail_test.dart`).

- [ ] **Step 5: Commit**

```bash
git add lib/ui/screens/dive_detail_screen.dart \
        lib/ui/screens/fullscreen_chart_screen.dart
git commit -m "feat(deco): always compute replay, feed GF99/ceiling to crosshair" \
           -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: Total-deco summary tiles

**Files:**
- Modify: `lib/ui/screens/dive_detail_screen.dart` (`_buildStatsRow`: add computation near line 1361; add two tiles after the `GF` tile near line 1507)

> No new automated test here: the numbers are already covered by Task 1's unit tests, and rendering `_buildStatsRow` in isolation would require standing up the full screen with notifiers/DAOs. Gate on `flutter analyze` + the existing screen tests + a manual check (below).

- [ ] **Step 1: Compute the deco numbers**

In `_buildStatsRow`, after the `vSpeed` block (currently ends ~line 1361, `verticalSpeedExtremes(...)`), insert:

```dart
    final timeInDecoSec = totalTimeInDecoSeconds(
      decoStopDepthMeters: samples.decoStopDepthMeters,
      sampleCount: samples.sampleCount,
      sampleIntervalMs: samples.sampleIntervalMs,
    );
    final peakTtsSec = peakTtsSeconds(
      ttsSeconds: samples.ttsSeconds,
      sampleCount: samples.sampleCount,
    );
    final showDeco = timeInDecoSec > 0;
    var deepestStopM = 0.0; // for the Deco tile hint
    for (var i = 0; i < n; i++) {
      final d = samples.decoStopDepthMeters[i];
      if (!d.isNaN && d > deepestStopM) deepestStopM = d;
    }
```

(`n`, `samples`, and the `totalTimeInDecoSeconds`/`peakTtsSeconds` helpers from `dive_stats.dart` are already in scope — the file imports `dive_stats.dart` for `computeOtu`/`minAvgMax`.)

- [ ] **Step 2: Add the two tiles after the `GF` tile**

In the `cells` list, immediately after the existing `GF` `StatTile` (the one with `value: maxGf.round().toString()`, ~lines 1502–1507), insert:

```dart
        if (showDeco)
          StatTile(
            label: 'Deco',
            unit: 'min',
            value: '${(timeInDecoSec / 60).round()}',
            hint: 'max ${deepestStopM.toStringAsFixed(0)} m',
          ),
        if (showDeco)
          StatTile(
            label: 'TTS',
            unit: 'min',
            value: '${(peakTtsSec / 60).round()}',
          ),
```

(No `valueColor` — neutral white is intentional, see the spec's Visual design section.)

- [ ] **Step 3: Verify analyze + full tests**

Run: `flutter analyze`
Expected: `No issues found!`
Run: `flutter test`
Expected: PASS (all suites).

- [ ] **Step 4: Manual verification**

Run the app (`flutter run`), open a **deco dive**: the stats grid shows `DECO ## min` (with a `max # m` hint) and `TTS ## min`; long-press the profile to confirm the crosshair shows the deco group (Stop/Stop time/TTS/Ceiling/GF99, GF99 colour-banded), and digits don't jitter while scrubbing. Open an **NDL dive**: the two summary tiles are absent and the crosshair shows `NDL`.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/screens/dive_detail_screen.dart
git commit -m "feat(deco): show time-in-deco + peak TTS in dive summary" \
           -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Done criteria

- `flutter analyze` clean, `flutter test` green.
- Crosshair shows Stop/Stop time (or NDL), TTS, Ceiling, and band-coloured GF99; values use tabular figures; the deco group is set off by a hairline.
- Dive summary shows `Deco` and `TTS` tiles on deco dives (with deepest-stop hint), hidden on NDL dives.
- `gfBandColor` is the single source for GF colour across the tooltip and the stat tiles.
- Behaviour verified on a real deco dive and an NDL dive.
- Open a PR (`feat/deco-crosshair-total` → main); CI runs analyze + test; squash-merge per the repo workflow.
