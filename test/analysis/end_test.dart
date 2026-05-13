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
        gasMixes: [
          DiveGasMix(oxygenPercent: 21, heliumPercent: 0, isDiluent: true),
        ],
        countsOxygen: true,
      );
      expect(series[0], closeTo(30.0, 0.1));
    });

    test('18/45 trimix at 60 m → END ≈ 28.5 m', () {
      // (60 + 10) × (1 - 0.45) - 10 = 70 × 0.55 - 10 = 28.5
      final series = computeEndSeries(
        depthMeters: Float32List.fromList([60]),
        gasMixIndex: Uint8List.fromList([0]),
        gasMixes: [
          DiveGasMix(oxygenPercent: 18, heliumPercent: 45, isDiluent: true),
        ],
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
        gasMixes: [
          DiveGasMix(oxygenPercent: 18, heliumPercent: 45, isDiluent: true),
        ],
        countsOxygen: false,
      );
      expect(series[0], closeTo(22.8, 0.1));
    });

    test('air at 30 m → END = 30 m (N2 ≈ 0.79, so formula collapses to depth)',
        () {
      final series = computeEndSeries(
        depthMeters: Float32List.fromList([30]),
        gasMixIndex: Uint8List.fromList([0]),
        gasMixes: [
          DiveGasMix(oxygenPercent: 21, heliumPercent: 0, isDiluent: true),
        ],
        countsOxygen: false,
      );
      expect(series[0], closeTo(30.0, 0.1));
    });
  });

  group('computeEndSeries — clamping', () {
    test('END never goes negative — heliox at shallow depth clamps to 0', () {
      final series = computeEndSeries(
        depthMeters: Float32List.fromList([5]),
        gasMixIndex: Uint8List.fromList([0]),
        gasMixes: [
          DiveGasMix(oxygenPercent: 5, heliumPercent: 95, isDiluent: true),
        ],
        countsOxygen: true,
      );
      expect(series[0], greaterThanOrEqualTo(0.0));
    });
  });
}
