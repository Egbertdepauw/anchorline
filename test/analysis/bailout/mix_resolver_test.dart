import 'package:ccrlogger/analysis/bailout/mix_resolver.dart';
import 'package:ccrlogger/data/models/dive.dart' show DiveGasMix;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveBottomMix — DC-recorded diluent', () {
    test('returns the dive\'s recorded diluent verbatim', () {
      final mix = resolveBottomMix(
        recordedDiluent: const DiveGasMix(oxygenPercent: 18, heliumPercent: 45, isDiluent: true),
        maxDepthMeters: 60,
        isGueConfig: false,
      );
      expect(mix.oxygenPercent, 18);
      expect(mix.heliumPercent, 45);
    });
  });

  group('resolveBottomMix — non-GUE compute-and-snap', () {
    test('60 m max depth → snaps to 21/35', () {
      final mix = resolveBottomMix(
        recordedDiluent: null,
        maxDepthMeters: 60,
        isGueConfig: false,
      );
      expect(mix.oxygenPercent, 21);
      expect(mix.heliumPercent, 35);
    });

    test('40 m max depth → snaps to 21/35 (helium needed for END < 39m)', () {
      final mix = resolveBottomMix(
        recordedDiluent: null,
        maxDepthMeters: 40,
        isGueConfig: false,
      );
      expect(mix.oxygenPercent, 21);
      expect(mix.heliumPercent, 35);
    });

    test('80 m max depth → snaps to 15/55 (21/35 and 18/45 exceed PPO2 1.6, 15/55 closest to opt)', () {
      // At 80 m: ambient = 9 bar, opt fO2 = 1.6/9 ≈ 0.178.
      // 21/35 → PPO2 1.89 (filtered), 18/45 → PPO2 1.62 (filtered).
      // 15/55 → PPO2 1.35, delta 0.028; 12/65 → PPO2 1.08, delta 0.058.
      // 15/55 is closer to the optimum.
      final mix = resolveBottomMix(
        recordedDiluent: null,
        maxDepthMeters: 80,
        isGueConfig: false,
      );
      expect(mix.oxygenPercent, 15);
      expect(mix.heliumPercent, 55);
    });
  });

  group('resolveBottomMix — GUE compute-and-snap', () {
    test('60 m max depth → snaps to 15/55', () {
      final mix = resolveBottomMix(
        recordedDiluent: null,
        maxDepthMeters: 60,
        isGueConfig: true,
      );
      expect(mix.oxygenPercent, 15);
      expect(mix.heliumPercent, 55);
    });

    test('40 m max depth → snaps to 21/35', () {
      final mix = resolveBottomMix(
        recordedDiluent: null,
        maxDepthMeters: 40,
        isGueConfig: true,
      );
      expect(mix.oxygenPercent, 21);
      expect(mix.heliumPercent, 35);
    });
  });
}
