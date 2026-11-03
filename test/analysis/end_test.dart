import 'dart:typed_data';

import 'package:ccrlogger/analysis/end.dart';
import 'package:subsurface_core/data/models/dive.dart' show DiveGasMix;
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

  group('computeEndSeries — CCR loop-gas mode', () {
    test(
        'regression: dive 702 — 22/41 diluent at 55.3 m on setpoint 1.4 → '
        'END ≈ 28.5 m, NOT 55 m', () {
      // Reproduces the user-reported bug from 2026-05-19: per-sample
      // gasMixIndex pointed at the OC bailout (21/0 air) on a CCR dive,
      // giving END = depth (55 m) instead of using the diluent. Passing
      // a positive ppo2Bar must trigger loop-gas computation against
      // the diluent regardless of what gasMixIndex says.
      final series = computeEndSeries(
        depthMeters: Float32List.fromList([55.3]),
        gasMixIndex: Uint8List.fromList([2]), // pretend the parser
                                              // wrongly chose the
                                              // bailout air
        gasMixes: [
          DiveGasMix(oxygenPercent: 22, heliumPercent: 41, isDiluent: true),
          DiveGasMix(oxygenPercent: 99, heliumPercent: 0, isDiluent: false),
          DiveGasMix(oxygenPercent: 21, heliumPercent: 0, isDiluent: false),
        ],
        countsOxygen: true,
        ppo2Bar: Float32List.fromList([1.4]),
      );
      // Loop gas at 55.3 m, sp 1.4, diluent 22/41:
      //   pAmb = 1.013 + 5.53 = 6.543 bar
      //   loopO2 = 1.4 / 6.543 = 0.214
      //   loopHe = (1 − 0.214) × 0.41 / 0.78 = 0.413
      // END A = (55.3 + 10) × (1 − 0.413) − 10 = 65.3 × 0.587 − 10
      //       ≈ 28.3
      expect(series[0], closeTo(28.3, 0.5));
      // And specifically NOT the buggy ~55 m value.
      expect(series[0], lessThan(35.0));
    });

    test('OC dive (no ppo2Bar) preserves the static-mix behaviour', () {
      // When ppo2Bar is null, the function must match the pre-fix
      // behaviour exactly — used by OC dives where the static
      // gasMixIndex is correct.
      final series = computeEndSeries(
        depthMeters: Float32List.fromList([55.3]),
        gasMixIndex: Uint8List.fromList([2]),
        gasMixes: [
          DiveGasMix(oxygenPercent: 22, heliumPercent: 41, isDiluent: true),
          DiveGasMix(oxygenPercent: 99, heliumPercent: 0, isDiluent: false),
          DiveGasMix(oxygenPercent: 21, heliumPercent: 0, isDiluent: false),
        ],
        countsOxygen: true,
        // ppo2Bar omitted → static mix at index 2 (21/0 air).
      );
      // (55.3 + 10) × (1 − 0) − 10 = 55.3.
      expect(series[0], closeTo(55.3, 0.1));
    });

    test('per-sample ppo2 = 0 (e.g. surface) falls back to static gas', () {
      final series = computeEndSeries(
        depthMeters: Float32List.fromList([0, 30, 55]),
        gasMixIndex: Uint8List.fromList([0, 0, 0]),
        gasMixes: [
          DiveGasMix(oxygenPercent: 22, heliumPercent: 41, isDiluent: true),
        ],
        countsOxygen: true,
        // Surface sample has 0 PPO2 → static gas path.
        ppo2Bar: Float32List.fromList([0, 1.3, 1.4]),
      );
      // Surface: static 22/41 → END = (0+10)*(1-0.41)-10 = 5.9 - 10 < 0 → 0
      expect(series[0], 0.0);
      // 30 m with sp 1.3: loop O2 = 1.3/4.013 ≈ 0.324, loop He = 0.676 × 0.526 ≈ 0.356
      //   END = (30+10)*(1-0.356)-10 = 40*0.644-10 = 15.76
      expect(series[1], closeTo(15.8, 1.0));
      // 55 m: roughly 28 m (as above)
      expect(series[2], closeTo(28.5, 1.0));
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
