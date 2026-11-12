import 'dart:typed_data';
import 'package:subsurface_core/data/sample_codec/dive_stats.dart';
import 'package:test/test.dart';

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

  test('minAvgMax ignores NaN values (merged-dive surface gaps)', () {
    // Surface-gap samples are NaN; they must not poison the average.
    final values = Float32List.fromList([10.0, double.nan, 20.0, double.nan]);
    final stats = minAvgMax(values, 4);
    expect(stats?.min, closeTo(10.0, 1e-6));
    expect(stats?.max, closeTo(20.0, 1e-6));
    expect(stats?.avg, closeTo(15.0, 1e-6));
  });

  test('minAvgMax returns null when every value is NaN', () {
    final values = Float32List.fromList([double.nan, double.nan]);
    expect(minAvgMax(values, 2), isNull);
  });

  test('computeOtu skips NaN ppo2 (merged-dive surface gaps)', () {
    // 60 real samples at 1.0 bar (=1.0 OTU/min over 1 min) plus NaN gaps.
    final ppo2 = Float32List.fromList([...List.filled(60, 1.0), double.nan, double.nan]);
    final otu = computeOtu(
        ppo2Bar: ppo2, sampleCount: 62, sampleIntervalMs: 1000);
    expect(otu, closeTo(1.0, 1e-3));
    expect(otu.isNaN, isFalse);
  });

  group('verticalSpeedExtremes', () {
    test('returns zero when fewer than two samples', () {
      final res = verticalSpeedExtremes(
          depthMeters: Float32List.fromList([5.0]),
          sampleCount: 1,
          sampleIntervalMs: 10000);
      expect(res.maxAscentMpm, 0.0);
      expect(res.maxDescentMpm, 0.0);
      expect(res.maxAscentEndIndex, 0);
      expect(res.maxDescentEndIndex, 0);
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
      // 30 m/min between i=0 and i=1 → endIndex=1. Worst ascent: 4m /
      // 10s = 24 m/min between i=2 and i=3 → endIndex=3.
      final depth = Float32List.fromList([0, 5, 6, 2, 3]);
      final res = verticalSpeedExtremes(
          depthMeters: depth, sampleCount: 5, sampleIntervalMs: 10000);
      expect(res.maxDescentMpm, closeTo(30.0, 1e-3));
      expect(res.maxAscentMpm, closeTo(24.0, 1e-3));
      expect(res.maxDescentEndIndex, 1);
      expect(res.maxAscentEndIndex, 3);
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
      // Descent into the blip ends at i=6; ascent back out ends at i=7.
      expect(res.maxDescentEndIndex, 6);
      expect(res.maxAscentEndIndex, 7);
    });
  });

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

    test('totalTimeInDecoSeconds is 0 for empty input (sampleCount 0)', () {
      // Exercises the sampleCount==0 early-return, not the loop body.
      final stops = Float32List.fromList([6, 6, 6]);
      expect(
        totalTimeInDecoSeconds(
            decoStopDepthMeters: stops, sampleCount: 0, sampleIntervalMs: 10000),
        0,
      );
    });

    test('peakTtsSeconds is 0 for empty input (sampleCount 0)', () {
      // Exercises the sampleCount==0 early-return, not the loop body.
      expect(
        peakTtsSeconds(ttsSeconds: Int32List.fromList([1380]), sampleCount: 0),
        0,
      );
    });
  });
}
