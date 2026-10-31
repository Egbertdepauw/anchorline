import 'dart:math' as math;

import 'package:ccrlogger/analyzer/stability.dart';
import 'package:flutter_test/flutter_test.dart';

/// Feeds [n] samples at 1 Hz (implicit spacing) and returns every state.
List<ReadingStability> feed(
  StabilityDetector d,
  int n,
  double Function(int t) o2, [
  double? Function(int t)? he,
]) => [for (var t = 0; t < n; t++) d.add(o2(t), he == null ? 0.0 : he(t))];

/// Feeds samples at [hz] for [seconds] of real time, passing the elapsed
/// time explicitly, and returns `(time, state)` per sample.
List<(double, ReadingStability)> feedAt(
  StabilityDetector d,
  double hz,
  double seconds,
  double Function(double t) o2, [
  double Function(double t)? he,
]) {
  final out = <(double, ReadingStability)>[];
  final n = (seconds * hz).round();
  for (var i = 0; i < n; i++) {
    final t = i / hz;
    final state = d.add(
      o2(t),
      he == null ? 0.0 : he(t),
      elapsed: Duration(microseconds: (t * 1e6).round()),
    );
    out.add((t, state));
  }
  return out;
}

/// Time of the first STABLE state, or null.
double? firstStableAt(List<(double, ReadingStability)> states) {
  for (final (t, s) in states) {
    if (s == ReadingStability.stable) return t;
  }
  return null;
}

/// Deterministic pseudo-noise in [-amplitude, +amplitude].
double noise(num t, double amplitude) => amplitude * math.sin(t * 2.39996);

/// Galvanic cell settling 20.0 → 21.0 with tau = 15 s.
double settlingO2(num t) => 21.0 - 1.0 * math.exp(-t / 15.0);

void main() {
  group('StabilityDetector', () {
    test('starts in noData', () {
      final d = StabilityDetector();
      expect(d.state, ReadingStability.noData);
      expect(d.sampleCount, 0);
    });

    test('settling until the data spans the full 20 s, even if flat', () {
      final d = StabilityDetector();
      // t = 0..19: 20 samples, but only 19 s of data.
      final states = feed(d, 20, (_) => 20.9);
      expect(states, everyElement(ReadingStability.settling));
      expect(d.add(20.9, 0), ReadingStability.stable, reason: 't = 20 s');
    });

    test('flat signal with noise inside tolerance is stable', () {
      final d = StabilityDetector();
      final states = feed(
        d,
        40,
        (t) => 32.0 + noise(t, 0.05),
        (t) => 10.0 + noise(t + 7, 0.05),
      );
      expect(states.take(20), everyElement(ReadingStability.settling));
      expect(states.skip(20), everyElement(ReadingStability.stable));
    });

    test('noise exceeding the spread tolerance is not stable', () {
      final d = StabilityDetector();
      final states = feed(d, 40, (t) => 21.0 + (t.isEven ? 0.15 : -0.15));
      expect(states, isNot(contains(ReadingStability.stable)));
    });

    test('exponential settling of a galvanic cell is not stable early', () {
      final d = StabilityDetector();
      final states = feed(d, 120, settlingO2);
      final firstStable = states.indexOf(ReadingStability.stable);
      expect(firstStable, greaterThan(0));
      // The instantaneous slope (1/15)·e^(−t/15) only drops below 0.01 %/s
      // at t ≈ 28.5 s; the window must not call it before then.
      expect(firstStable, greaterThan(28));
      // Once it has settled it stays stable.
      expect(states.skip(firstStable), everyElement(ReadingStability.stable));
      // v1 (8 samples, spread ≤ 0.15, no slope) would have fired much
      // earlier; sanity-check that the v2 rule is the stricter one.
      final v1 = StabilityDetector(
        window: const Duration(seconds: 7),
        minSamples: 8,
        spreadTolerance: 0.15,
        maxSlopePerSecond: double.infinity,
      );
      final v1First =
          feed(v1, 120, settlingO2).indexOf(ReadingStability.stable);
      expect(v1First, lessThan(firstStable));
    });

    test('slow linear drift is caught by the slope term', () {
      // 0.0115 %/s over 20 s = 0.23 spread, inside a 0.25 tolerance, but
      // the slope exceeds 0.01 %/s.
      final d = StabilityDetector(spreadTolerance: 0.25);
      final states = feed(d, 60, (t) => 21.0 + 0.0115 * t);
      expect(states, isNot(contains(ReadingStability.stable)));
      // Same drift passes when only the spread is checked.
      final spreadOnly = StabilityDetector(
        spreadTolerance: 0.25,
        maxSlopePerSecond: double.infinity,
      );
      expect(
        feed(spreadOnly, 60, (t) => 21.0 + 0.0115 * t).last,
        ReadingStability.stable,
      );
    });

    test('the slope is per second of real time, not per sample', () {
      for (final hz in [1.0, 5.0]) {
        final d = StabilityDetector(spreadTolerance: 0.25);
        final states = feedAt(d, hz, 60, (t) => 21.0 + 0.0115 * t);
        expect(firstStableAt(states), isNull, reason: '$hz Hz');
        final w = d.samples;
        expect(
          StabilityDetector.leastSquaresSlope(
            w.map((s) => s.seconds).toList(),
            w.map((s) => s.o2).toList(),
          ),
          closeTo(0.0115, 1e-9),
          reason: '$hz Hz',
        );
      }
    });

    test('a flat signal at 5 Hz is not stable before 20 s', () {
      final d = StabilityDetector();
      final states = feedAt(d, 5, 40, (t) => 20.9 + noise(t, 0.05));
      expect(firstStableAt(states), closeTo(20, 1e-9));
      // The window holds 20 s of samples, not 20 samples.
      expect(d.sampleCount, 101);
    });

    test('exponential settling behaves the same at 1 Hz and 5 Hz', () {
      final at1 =
          firstStableAt(feedAt(StabilityDetector(), 1, 120, settlingO2));
      final at5 =
          firstStableAt(feedAt(StabilityDetector(), 5, 120, settlingO2));
      expect(at1, isNotNull);
      expect(at5, isNotNull);
      expect(at5, greaterThan(28), reason: 'slope only < 0.01 %/s at 28.5 s');
      expect(at5, closeTo(at1!, 1.0));
    });

    test('He settling at 5 Hz with flat O2 is not stable early', () {
      final states = feedAt(
        StabilityDetector(),
        5,
        120,
        (_) => 18.2,
        (t) => 45.0 - 3.0 * math.exp(-t / 10.0),
      );
      final first = firstStableAt(states);
      expect(first, isNotNull);
      // He slope 0.3·e^(−t/10) only drops below 0.01 %/s at t ≈ 34 s.
      expect(first, greaterThan(34));
    });

    test('too few samples in the window is not stable', () {
      // One sample every 5 s: the 20 s window never holds 10.
      final d = StabilityDetector();
      final states = feedAt(d, 0.2, 120, (_) => 20.9);
      expect(firstStableAt(states), isNull);
      // With a lower minimum the same data is stable.
      final lenient = StabilityDetector(minSamples: 4);
      expect(firstStableAt(feedAt(lenient, 0.2, 120, (_) => 20.9)), 20);
    });

    test('a gap in the data empties the window and needs re-earning', () {
      final d = StabilityDetector();
      feed(d, 30, (_) => 20.9);
      expect(d.state, ReadingStability.stable);
      // 30 s of silence, then data again.
      expect(
        d.add(20.9, 0, elapsed: const Duration(seconds: 60)),
        ReadingStability.settling,
      );
      expect(d.sampleCount, 1);
    });

    test('DateTime timestamps still work', () {
      final d = StabilityDetector();
      final start = DateTime.utc(2026, 10, 28, 12);
      ReadingStability? last;
      for (var i = 0; i <= 100; i++) {
        last = d.add(20.9, 0, at: start.add(Duration(milliseconds: i * 200)));
        if (i < 100) expect(last, ReadingStability.settling);
      }
      expect(last, ReadingStability.stable);
    });

    test('He drifting while O2 is flat is not stable', () {
      final d = StabilityDetector();
      final states = feed(d, 60, (_) => 18.0, (t) => 45.0 + 0.0104 * t);
      expect(states, isNot(contains(ReadingStability.stable)));
    });

    test('null He (O2-only analyzer) is treated as 0', () {
      final d = StabilityDetector();
      final states = feed(d, 21, (_) => 20.9, (_) => null);
      expect(states.last, ReadingStability.stable);
      expect(d.samples.last.he, 0);
    });

    test('NaN gives sensorError and recovery needs a full fresh window', () {
      final d = StabilityDetector();
      feed(d, 25, (_) => 20.9);
      expect(d.state, ReadingStability.stable);

      expect(d.add(double.nan, 0), ReadingStability.sensorError);
      expect(d.sampleCount, 0);

      final after = feed(d, 21, (_) => 20.9);
      expect(after.take(20), everyElement(ReadingStability.settling));
      expect(after.last, ReadingStability.stable);

      expect(d.add(20.9, double.nan), ReadingStability.sensorError);
      expect(d.add(null, 0), ReadingStability.sensorError);
      expect(d.add(20.9, 0), ReadingStability.settling);
    });

    test('custom parameters are respected', () {
      final d = StabilityDetector(
        window: const Duration(seconds: 4),
        minSamples: 5,
        spreadTolerance: 0.5,
        maxSlopePerSecond: 0.1,
      );
      final states = feed(d, 10, (t) => 21.0 + 0.05 * t);
      expect(states.take(4), everyElement(ReadingStability.settling));
      expect(states.skip(4), everyElement(ReadingStability.stable));
      expect(d.sampleCount, 5);

      final strict = StabilityDetector(
        window: const Duration(seconds: 4),
        minSamples: 5,
        maxSlopePerSecond: 0.04,
      );
      expect(
        feed(strict, 10, (t) => 21.0 + 0.05 * t),
        isNot(contains(ReadingStability.stable)),
      );
    });

    test('defaults match the documented v2 rule', () {
      final d = StabilityDetector();
      expect(d.window, const Duration(seconds: 20));
      expect(d.minSamples, 10);
      expect(d.spreadTolerance, 0.2);
      expect(d.maxSlopePerSecond, 0.01);
    });

    test('reset() returns to noData and restarts the window', () {
      final d = StabilityDetector();
      feed(d, 21, (_) => 20.9);
      expect(d.state, ReadingStability.stable);
      d.reset();
      expect(d.state, ReadingStability.noData);
      expect(d.sampleCount, 0);
      expect(d.add(32.0, 0), ReadingStability.settling);
    });

    test('leastSquaresSlope handles degenerate input', () {
      expect(StabilityDetector.leastSquaresSlope([], []), 0);
      expect(StabilityDetector.leastSquaresSlope([1, 1, 1], [1, 2, 3]), 0);
      expect(
        StabilityDetector.leastSquaresSlope([0, 1, 2, 3], [1, 3, 5, 7]),
        closeTo(2, 1e-12),
      );
    });
  });
}
