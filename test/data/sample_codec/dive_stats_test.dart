import 'dart:typed_data';
import 'package:ccrlogger/data/sample_codec/dive_stats.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('computeOtu returns 0 when ppo2 is below threshold', () {
    final ppo2 = Float32List.fromList([0.21, 0.30, 0.40]);
    expect(
        computeOtu(
            ppo2Bar: ppo2, sampleCount: 3, sampleIntervalMs: 60000),
        0.0);
  });

  test('computeOtu accumulates above 0.5 atm', () {
    // 60 samples × 1s interval = 60s = 1 min total.
    // PO2 = 1.0 → ((1.0 - 0.5) / 0.5)^(5/6) = 1.0^(5/6) = 1.0 OTU/min.
    final ppo2 = Float32List.fromList(List.filled(60, 1.0));
    final otu = computeOtu(
        ppo2Bar: ppo2, sampleCount: 60, sampleIntervalMs: 1000);
    expect(otu, closeTo(1.0, 1e-3));
  });

  test('minAvgMax computes correctly', () {
    final values = Float32List.fromList([0.5, 1.0, 1.5]);
    final stats = minAvgMax(values, 3);
    expect(stats?.min, closeTo(0.5, 1e-6));
    expect(stats?.avg, closeTo(1.0, 1e-6));
    expect(stats?.max, closeTo(1.5, 1e-6));
  });

  test('minAvgMax returns null on empty input', () {
    expect(minAvgMax(Float32List(0), 0), isNull);
  });

  group('verticalSpeedExtremes', () {
    test('returns zero when fewer than two samples', () {
      final res = verticalSpeedExtremes(
          depthMeters: Float32List.fromList([5.0]),
          sampleCount: 1,
          sampleIntervalMs: 10000);
      expect(res.maxAscentMpm, 0.0);
      expect(res.maxDescentMpm, 0.0);
    });

    test('monotonic descent yields zero ascent', () {
      // 10s interval, depth grows by 3 m/sample → 18 m/min descent.
      final depth = Float32List.fromList([0, 3, 6, 9, 12]);
      final res = verticalSpeedExtremes(
          depthMeters: depth, sampleCount: 5, sampleIntervalMs: 10000);
      expect(res.maxDescentMpm, closeTo(18.0, 1e-3));
      expect(res.maxAscentMpm, 0.0);
    });

    test('monotonic ascent yields zero descent', () {
      // 10s interval, depth drops by 2 m/sample → 12 m/min ascent.
      final depth = Float32List.fromList([20, 18, 16, 14, 12]);
      final res = verticalSpeedExtremes(
          depthMeters: depth, sampleCount: 5, sampleIntervalMs: 10000);
      expect(res.maxAscentMpm, closeTo(12.0, 1e-3));
      expect(res.maxDescentMpm, 0.0);
    });

    test('mixed profile picks worst sample-pair', () {
      // 5 samples at 10s. With a 5s window rounded up to 1 sample (10s),
      // each adjacent pair is its own datum. Worst descent: 5m / 10s =
      // 30 m/min. Worst ascent: 4m / 10s = 24 m/min.
      final depth = Float32List.fromList([0, 5, 6, 2, 3]);
      final res = verticalSpeedExtremes(
          depthMeters: depth, sampleCount: 5, sampleIntervalMs: 10000);
      expect(res.maxDescentMpm, closeTo(30.0, 1e-3));
      expect(res.maxAscentMpm, closeTo(24.0, 1e-3));
    });

    test('single-sample 0.5m spike shows as 6 m/min at 5s sampling', () {
      // 13 samples at 5s. With the 5s window collapsed to one sample
      // interval, a 0.5m blip at i=6 reads at 0.5m/5s = 6 m/min in
      // both directions (descend into the blip, ascend back out).
      final depth = Float32List.fromList([
        10, 10, 10, 10, 10, 10, 10.5, 10, 10, 10, 10, 10, 10,
      ]);
      final res = verticalSpeedExtremes(
          depthMeters: depth, sampleCount: 13, sampleIntervalMs: 5000);
      expect(res.maxDescentMpm, closeTo(6.0, 1e-3));
      expect(res.maxAscentMpm, closeTo(6.0, 1e-3));
    });
  });
}
