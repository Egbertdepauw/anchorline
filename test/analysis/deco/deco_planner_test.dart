import 'package:ccrlogger/analysis/deco/deco_planner.dart';
import 'package:ccrlogger/analysis/deco/deco_step.dart';
import 'package:ccrlogger/data/models/dive.dart' show DiveGasMix;
import 'package:flutter_test/flutter_test.dart';

const _air = DiveGasMix(oxygenPercent: 21, heliumPercent: 0, isDiluent: false);
const _ean50 = DiveGasMix(oxygenPercent: 50, heliumPercent: 0, isDiluent: false);
const _o2 = DiveGasMix(oxygenPercent: 100, heliumPercent: 0, isDiluent: false);

List<double> _surfaceN2() =>
    List<double>.filled(16, (1.013 - 0.0627) * 0.79);
List<double> _zeroHe() => List<double>.filled(16, 0.0);

/// Heavily loaded across all compartments — represents a long deep dive.
List<double> _heavilyLoadedN2() => List<double>.filled(16, 4.0);

void main() {
  group('planDeco', () {
    test('NDL dive returns no stops', () {
      final steps = planDeco(
        initialN2Bar: _surfaceN2(),
        initialHeBar: _zeroHe(),
        triggerDepthMeters: 20,
        gases: const [_air],
        gfLow: 50,
        gfHigh: 95,
        ascentRateFastMPerMin: 18,
        ascentRateSlowMPerMin: 9,
        ppo2LimitBottom: 1.6,
        ppo2LimitDeco: 1.4,
      );
      expect(steps.where((s) => s.isStop), isEmpty);
    });

    test('first stop depth lies on a 3m multiple', () {
      final steps = planDeco(
        initialN2Bar: _heavilyLoadedN2(),
        initialHeBar: _zeroHe(),
        triggerDepthMeters: 40,
        gases: const [_air, _ean50, _o2],
        gfLow: 50,
        gfHigh: 95,
        ascentRateFastMPerMin: 18,
        ascentRateSlowMPerMin: 9,
        ppo2LimitBottom: 1.6,
        ppo2LimitDeco: 1.6,
      );
      final stops = steps.where((s) => s.isStop).toList();
      expect(stops, isNotEmpty);
      for (final s in stops) {
        expect(s.depthStartMeters % 3, 0,
            reason: 'every stop must be at a 3m multiple');
      }
    });

    test('GF Low 30 produces a deeper first stop than GF Low 70', () {
      // Realistic gradient: fast compartments well-loaded from a moderate
      // 40m bottom time, slow compartments still at near-surface levels.
      // This way the GF-sensitive middle compartments are limiting, so
      // changing gfLow visibly shifts the first stop.
      final n2 = List<double>.generate(
        16,
        (c) => c < 6 ? 3.2 : (3.2 - (c - 5) * 0.30).clamp(0.85, 3.2),
      );
      List<DecoStep> run(int gfLow) => planDeco(
            initialN2Bar: n2,
            initialHeBar: _zeroHe(),
            triggerDepthMeters: 40,
            gases: const [_air, _ean50, _o2],
            gfLow: gfLow,
            gfHigh: 85,
            ascentRateFastMPerMin: 18,
            ascentRateSlowMPerMin: 9,
            ppo2LimitBottom: 1.6,
            ppo2LimitDeco: 1.6,
          );
      double firstStop(List<DecoStep> steps) => steps
          .firstWhere((s) => s.isStop, orElse: () => steps.first)
          .depthStartMeters;
      expect(firstStop(run(30)), greaterThan(firstStop(run(70))));
    });

    test('every stop depth is divisible by 3', () {
      final steps = planDeco(
        initialN2Bar: _heavilyLoadedN2(),
        initialHeBar: _zeroHe(),
        triggerDepthMeters: 45,
        gases: const [_air, _ean50, _o2],
        gfLow: 50,
        gfHigh: 95,
        ascentRateFastMPerMin: 18,
        ascentRateSlowMPerMin: 9,
        ppo2LimitBottom: 1.6,
        ppo2LimitDeco: 1.6,
      );
      for (final s in steps.where((s) => s.isStop)) {
        expect(s.depthStartMeters % 3, 0);
      }
    });

    test('heavier tissue loading produces longer total stop time', () {
      Duration totalStopTime(List<double> n2) {
        final steps = planDeco(
          initialN2Bar: n2,
          initialHeBar: _zeroHe(),
          triggerDepthMeters: 40,
          gases: const [_air, _ean50, _o2],
          gfLow: 50,
          gfHigh: 95,
          ascentRateFastMPerMin: 18,
          ascentRateSlowMPerMin: 9,
          ppo2LimitBottom: 1.6,
          ppo2LimitDeco: 1.6,
        );
        return steps.where((s) => s.isStop).fold(
              Duration.zero,
              (sum, s) => sum + s.duration,
            );
      }

      final heavy = List<double>.filled(16, 4.5);
      final lighter = List<double>.filled(16, 3.0);
      expect(totalStopTime(heavy), greaterThan(totalStopTime(lighter)));
    });

    test('every leg respects PPO2 ≤ 1.6 on the chosen gas', () {
      final steps = planDeco(
        initialN2Bar: _heavilyLoadedN2(),
        initialHeBar: _zeroHe(),
        triggerDepthMeters: 40,
        gases: const [_air, _ean50, _o2],
        gfLow: 50,
        gfHigh: 95,
        ascentRateFastMPerMin: 18,
        ascentRateSlowMPerMin: 9,
        ppo2LimitBottom: 1.6,
        ppo2LimitDeco: 1.6,
      );
      for (final s in steps) {
        final ambient = 1.013 + s.depthStartMeters / 10.0;
        final ppo2 = (s.gas.oxygenPercent / 100.0) * ambient;
        expect(ppo2, lessThanOrEqualTo(1.6 + 1e-6),
            reason: 'breathing ${s.gas.oxygenPercent}% at '
                '${s.depthStartMeters}m gives PPO2 $ppo2');
      }
    });

    test('plan terminates at the surface (final depthEnd == 0)', () {
      final steps = planDeco(
        initialN2Bar: _heavilyLoadedN2(),
        initialHeBar: _zeroHe(),
        triggerDepthMeters: 40,
        gases: const [_air, _ean50, _o2],
        gfLow: 50,
        gfHigh: 95,
        ascentRateFastMPerMin: 18,
        ascentRateSlowMPerMin: 9,
        ppo2LimitBottom: 1.6,
        ppo2LimitDeco: 1.6,
      );
      expect(steps, isNotEmpty);
      expect(steps.last.depthEndMeters, 0);
    });
  });
}
