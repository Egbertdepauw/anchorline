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
    test('18/45 trimix ≈ 0.76 g/L', () {
      // N₂ constant is calibrated to ISA air (1.225 g/L), not 25 °C pure N₂,
      // so the trimix 1-ATA density is 0.756, not 0.74.
      expect(mixDensityAt1Atm(0.18, 0.45), closeTo(0.76, 0.01));
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
      final depth = Float32List.fromList([30.0]);
      final mixIndex = Uint8List.fromList([0]);
      final gasMixes = [
        DiveGasMix(oxygenPercent: 21, heliumPercent: 0, isDiluent: true),
      ];
      final series = computeDensitySeries(
        depthMeters: depth,
        gasMixIndex: mixIndex,
        gasMixes: gasMixes,
        atmosphericPressureMbar: 1013,
      );
      expect(series.length, 1);
      expect(series[0], closeTo(4.9, 0.05));
    });

    test('18/45 trimix at 60 m ≈ 5.3 g/L', () {
      // With N₂ calibrated to ISA air the 1-ATA trimix density is 0.756 g/L,
      // giving 0.756 × 7.013 bar ≈ 5.30 g/L at 60 m.
      final depth = Float32List.fromList([60.0]);
      final mixIndex = Uint8List.fromList([0]);
      final gasMixes = [
        DiveGasMix(oxygenPercent: 18, heliumPercent: 45, isDiluent: true),
      ];
      final series = computeDensitySeries(
        depthMeters: depth,
        gasMixIndex: mixIndex,
        gasMixes: gasMixes,
        atmosphericPressureMbar: 1013,
      );
      expect(series[0], closeTo(5.3, 0.05));
    });

    test('EAN 50 at 6 m ≈ 2.0 g/L', () {
      final depth = Float32List.fromList([6.0]);
      final mixIndex = Uint8List.fromList([0]);
      final gasMixes = [
        DiveGasMix(oxygenPercent: 50, heliumPercent: 0, isDiluent: false),
      ];
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
