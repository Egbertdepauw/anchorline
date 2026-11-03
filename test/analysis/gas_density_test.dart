import 'dart:typed_data';

import 'package:ccrlogger/analysis/gas_density.dart';
import 'package:subsurface_core/data/models/dive.dart' show DiveGasMix;
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

  group('computeDensitySeries — CCR loop-gas mode', () {
    test(
        'regression: dive 702 — 22/41 diluent at 55.3 m, sp 1.4 → '
        '~5.1 g/L (was 8 g/L from bailout air)', () {
      // Live reproduction of the user's 2026-05-19 bug report. Even
      // though the per-sample gasMixIndex points at mix 2 (21/0
      // bailout air), passing a positive ppo2Bar forces the
      // density computation against the diluent's loop gas.
      final series = computeDensitySeries(
        depthMeters: Float32List.fromList([55.3]),
        gasMixIndex: Uint8List.fromList([2]),
        gasMixes: [
          DiveGasMix(oxygenPercent: 22, heliumPercent: 41, isDiluent: true),
          DiveGasMix(oxygenPercent: 99, heliumPercent: 0, isDiluent: false),
          DiveGasMix(oxygenPercent: 21, heliumPercent: 0, isDiluent: false),
        ],
        atmosphericPressureMbar: 1013,
        ppo2Bar: Float32List.fromList([1.4]),
      );
      // Loop gas: o2≈0.214, he≈0.413, n2≈0.373
      // Density at 1 ATA: 0.214×1.314 + 0.413×0.166 + 0.373×1.2013
      //                 ≈ 0.281 + 0.069 + 0.448 = 0.798 g/L
      // At 6.543 bar: 5.22 g/L (we accept ±0.3 around 5.1)
      expect(series[0], closeTo(5.2, 0.3));
      // Specifically NOT the buggy ~8 g/L (air at depth).
      expect(series[0], lessThan(6.5));
    });

    test(
        'regression: dive 692 (145.6 m cave) — sample wrongly indexed at a '
        'non-diluent deco gas (50/0) falls back to the deepest diluent '
        '(8/70), NOT the first diluent in the list', () {
      // Reproduces dive-692 max-density bug: Subsurface had spurious
      // gaschange events to 50/0 (a deco gas) at depth on a CCR dive
      // whose actual loop diluent was 8/70. Density spiked to 10.6 g/L
      // because the old fallback was "first diluent in list" (which was
      // 50/0 with isDiluent=true — a weird configuration artifact).
      // Falling back to the deepest diluent (lowest O₂, 8/70) gives the
      // correct ~7.7 g/L instead.
      final series = computeDensitySeries(
        depthMeters: Float32List.fromList([145.6]),
        gasMixIndex: Uint8List.fromList([1]), // 50/0 non-diluent
        gasMixes: [
          DiveGasMix(oxygenPercent: 99, heliumPercent: 0, isDiluent: false),
          DiveGasMix(oxygenPercent: 50, heliumPercent: 0, isDiluent: false),
          DiveGasMix(oxygenPercent: 20, heliumPercent: 48, isDiluent: false),
          DiveGasMix(oxygenPercent: 10, heliumPercent: 70, isDiluent: false),
          DiveGasMix(oxygenPercent: 50, heliumPercent: 0, isDiluent: true),
          DiveGasMix(oxygenPercent: 20, heliumPercent: 48, isDiluent: true),
          DiveGasMix(oxygenPercent: 10, heliumPercent: 70, isDiluent: true),
          DiveGasMix(oxygenPercent: 8, heliumPercent: 70, isDiluent: true),
        ],
        atmosphericPressureMbar: 1013,
        ppo2Bar: Float32List.fromList([1.4]),
      );
      // Loop gas on 8/70 (the deepest diluent) at 145.6 m, sp 1.4:
      //   pAmb = 15.57, loopO2 = 0.090
      //   loopHe = (1 − 0.090) × 0.70 / 0.92 = 0.692
      //   loopN2 = 0.218
      // Density 1 ATA: ≈ 0.497 → at 15.57 bar ≈ 7.7 g/L (the right
      // answer). The buggy old value (10.6 from a no-He fallback) is
      // explicitly rejected.
      expect(series[0], closeTo(7.7, 0.3));
      expect(series[0], lessThan(9.0));
    });

    test(
        'regression: dive 691 multi-diluent — sample on second diluent uses '
        'IT, not the first one in the list', () {
      // Dive 691 carries two diluents: 9/68 (idx 0) and 10/70 (idx 3).
      // At max depth the diver is on the 10/70 diluent (gasMixIndex=3).
      // The active diluent — not the first one in the list — must drive
      // the loop-gas calculation; otherwise multi-diluent dives display
      // ~5 % wrong density at depth (we got 8.08 vs the correct 7.6).
      final series = computeDensitySeries(
        depthMeters: Float32List.fromList([145.6]),
        gasMixIndex: Uint8List.fromList([3]),
        gasMixes: [
          DiveGasMix(oxygenPercent: 9, heliumPercent: 68, isDiluent: true),
          DiveGasMix(oxygenPercent: 100, heliumPercent: 0, isDiluent: false),
          DiveGasMix(oxygenPercent: 50, heliumPercent: 0, isDiluent: true),
          DiveGasMix(oxygenPercent: 10, heliumPercent: 70, isDiluent: true),
          DiveGasMix(oxygenPercent: 20, heliumPercent: 48, isDiluent: false),
          DiveGasMix(oxygenPercent: 100, heliumPercent: 0, isDiluent: false),
        ],
        atmosphericPressureMbar: 1013,
        ppo2Bar: Float32List.fromList([1.41]),
      );
      // Loop gas on 10/70 at 145.6 m, sp 1.41:
      //   pAmb = 15.57 bar, loopO2 = 1.41/15.57 = 0.0906
      //   loopHe = (1 − 0.0906) × (0.70 / 0.90) = 0.707
      //   loopN2 = 1 − 0.0906 − 0.707 = 0.202
      // Density 1 ATA: 0.091×1.314 + 0.707×0.166 + 0.202×1.2013 ≈ 0.480
      // At 15.57 bar: ~7.5 g/L (we accept ±0.3)
      expect(series[0], closeTo(7.5, 0.4));
      // And NOT the wrong-diluent (9/68) value of ~8.1.
      expect(series[0], lessThan(7.9));
    });

    test('OC dive (no ppo2Bar) preserves the static-mix behaviour', () {
      final series = computeDensitySeries(
        depthMeters: Float32List.fromList([55.3]),
        gasMixIndex: Uint8List.fromList([2]),
        gasMixes: [
          DiveGasMix(oxygenPercent: 22, heliumPercent: 41, isDiluent: true),
          DiveGasMix(oxygenPercent: 99, heliumPercent: 0, isDiluent: false),
          DiveGasMix(oxygenPercent: 21, heliumPercent: 0, isDiluent: false),
        ],
        atmosphericPressureMbar: 1013,
        // ppo2Bar omitted → uses static mix 2 (21/0 air).
      );
      // Air density at 1 ATA ≈ 1.225 g/L, × 6.543 bar ≈ 8.0 g/L.
      expect(series[0], closeTo(8.0, 0.1));
    });
  });
}
