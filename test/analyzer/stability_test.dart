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

/// Deterministic pseudo-noise in [-amplitude, +amplitude].
double noise(int t, double amplitude) => amplitude * math.sin(t * 2.39996);

void main() {
  group('StabilityDetector', () {
    test('starts in noData', () {
      final d = StabilityDetector();
      expect(d.state, ReadingStability.noData);
      expect(d.sampleCount, 0);
    });

    test('fewer than window samples is settling, even if perfectly flat', () {
      final d = StabilityDetector();
      final states = feed(d, 19, (_) => 20.9);
      expect(states, everyElement(ReadingStability.settling));
      expect(d.add(20.9, 0), ReadingStability.stable);
    });

    test('flat signal with noise inside tolerance is stable', () {
      final d = StabilityDetector();
      final states = feed(
        d,
        40,
        (t) => 32.0 + noise(t, 0.05),
        (t) => 10.0 + noise(t + 7, 0.05),
      );
      expect(states.take(19), everyElement(ReadingStability.settling));
      expect(states.skip(19), everyElement(ReadingStability.stable));
    });

    test('noise exceeding the spread tolerance is not stable', () {
      final d = StabilityDetector();
      final states = feed(d, 40, (t) => 21.0 + (t.isEven ? 0.15 : -0.15));
      expect(states, isNot(contains(ReadingStability.stable)));
    });

    test('exponential settling of a galvanic cell is not stable early', () {
      // 20.0 → 21.0 with tau = 15 s.
      double o2(int t) => 21.0 - 1.0 * math.exp(-t / 15.0);
      final d = StabilityDetector();
      final states = feed(d, 120, o2);
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
        windowSize: 8,
        spreadTolerance: 0.15,
        maxSlopePerSecond: double.infinity,
      );
      final v1First = feed(v1, 120, o2).indexOf(ReadingStability.stable);
      expect(v1First, lessThan(firstStable));
    });

    test('slow linear drift is caught by the slope term at 1 Hz', () {
      // 0.0104 %/s over 19 s = 0.198 spread, just inside 0.2, but the slope
      // exceeds 0.01 %/s.
      final d = StabilityDetector();
      final states = feed(d, 60, (t) => 21.0 + 0.0104 * t);
      expect(states, isNot(contains(ReadingStability.stable)));
      // Same drift passes when only the spread is checked.
      final spreadOnly = StabilityDetector(maxSlopePerSecond: double.infinity);
      expect(
        feed(spreadOnly, 60, (t) => 21.0 + 0.0104 * t).last,
        ReadingStability.stable,
      );
    });

    test('0.02 %/s drift with spread under 0.2 (2 Hz timestamps) is not '
        'stable', () {
      // At 2 Hz the window spans 9.5 s: spread 0.19, slope 0.02 %/s.
      final d = StabilityDetector();
      final start = DateTime.utc(2026, 10, 28, 12);
      ReadingStability? last;
      for (var i = 0; i < 60; i++) {
        final secs = i * 0.5;
        last = d.add(
          21.0 + 0.02 * secs,
          0,
          at: start.add(Duration(milliseconds: i * 500)),
        );
        expect(last, isNot(ReadingStability.stable));
      }
      final w = d.window;
      expect(
        StabilityDetector.leastSquaresSlope(
          w.map((s) => s.seconds).toList(),
          w.map((s) => s.o2).toList(),
        ),
        closeTo(0.02, 1e-9),
      );
    });

    test('He drifting while O2 is flat is not stable', () {
      final d = StabilityDetector();
      final states = feed(d, 60, (_) => 18.0, (t) => 45.0 + 0.0104 * t);
      expect(states, isNot(contains(ReadingStability.stable)));
    });

    test('null He (O2-only analyzer) is treated as 0', () {
      final d = StabilityDetector();
      final states = feed(d, 20, (_) => 20.9, (_) => null);
      expect(states.last, ReadingStability.stable);
      expect(d.window.last.he, 0);
    });

    test('NaN gives sensorError and recovery needs a full fresh window', () {
      final d = StabilityDetector();
      feed(d, 25, (_) => 20.9);
      expect(d.state, ReadingStability.stable);

      expect(d.add(double.nan, 0), ReadingStability.sensorError);
      expect(d.sampleCount, 0);

      final after = feed(d, 20, (_) => 20.9);
      expect(after.take(19), everyElement(ReadingStability.settling));
      expect(after.last, ReadingStability.stable);

      expect(d.add(20.9, double.nan), ReadingStability.sensorError);
      expect(d.add(null, 0), ReadingStability.sensorError);
      expect(d.add(20.9, 0), ReadingStability.settling);
    });

    test('custom parameters are respected', () {
      final d = StabilityDetector(
        windowSize: 5,
        spreadTolerance: 0.5,
        maxSlopePerSecond: 0.1,
      );
      final states = feed(d, 10, (t) => 21.0 + 0.05 * t);
      expect(states.take(4), everyElement(ReadingStability.settling));
      expect(states.skip(4), everyElement(ReadingStability.stable));
      expect(d.sampleCount, 5);

      final strict = StabilityDetector(windowSize: 5, maxSlopePerSecond: 0.04);
      expect(
        feed(strict, 10, (t) => 21.0 + 0.05 * t),
        isNot(contains(ReadingStability.stable)),
      );
    });

    test('defaults match the documented v2 rule', () {
      final d = StabilityDetector();
      expect(d.windowSize, 20);
      expect(d.spreadTolerance, 0.2);
      expect(d.maxSlopePerSecond, 0.01);
    });

    test('reset() returns to noData and restarts the window', () {
      final d = StabilityDetector();
      feed(d, 20, (_) => 20.9);
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
