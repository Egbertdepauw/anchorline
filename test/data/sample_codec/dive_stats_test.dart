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
}
