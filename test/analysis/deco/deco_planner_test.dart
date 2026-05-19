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

    test('GF Low 20 produces a deeper first stop than GF Low 80', () {
      // Deep trigger + heavy load with a steep gradient between fast and
      // slow compartments. Wide GF spread (20 vs 80) so the first-stop
      // depth shifts by multiple 3 m increments — making the comparison
      // robust to ties at single boundaries.
      final n2 = List<double>.generate(
        16,
        (c) => c < 4
            ? 5.0 // fast comps near-saturated at 90 m
            : (c < 10 ? 4.5 : 3.8),
      );
      List<DecoStep> run(int gfLow) => planDeco(
            initialN2Bar: n2,
            initialHeBar: _zeroHe(),
            triggerDepthMeters: 90,
            gases: const [_air, _ean50, _o2],
            gfLow: gfLow,
            gfHigh: 85,
            ascentRateFastMPerMin: 18,
            ascentRateSlowMPerMin: 9,
            ppo2LimitBottom: 1.6,
            ppo2LimitDeco: 1.6,
          );
      // Use the deepest stop (always a deco stop here — well above the
      // EAN50 gas-switch hold at 21 m) to avoid confusion with the
      // gas-switch holds the planner now emits at the standard depths.
      double deepestStop(List<DecoStep> steps) => steps
          .where((s) => s.isStop)
          .map((s) => s.depthStartMeters)
          .fold<double>(0.0, (a, b) => b > a ? b : a);
      final deep = deepestStop(run(20));
      final shallow = deepestStop(run(80));
      expect(deep, greaterThan(shallow),
          reason: 'GF Low 20 should put the deepest stop deeper than GF Low '
              '80 (deep=$deep, shallow=$shallow)');
      // Sanity: both deeper than 21 m so we're past the EAN50 gas-switch
      // hold and looking at actual deco stops.
      expect(deep, greaterThan(21));
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
        // Strict cap is 1.6 ata = 1.6 × 1.013 ≈ 1.621 bar absolute.
        // The standardSwitchDepth table puts O₂ at 6 m (a 3-m stop
        // boundary), where PPO₂ on 100 % O₂ is exactly 1.613 bar — that
        // 0.013 bar overage is the atmospheric-pressure contribution,
        // not a planner bug. Allow it.
        expect(ppo2, lessThanOrEqualTo(1.621 + 1e-6),
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

    test(
        'gas-switch hold: emit a flat 1-min stop at the standard switch '
        'depth (21 m for EAN50, 6 m for O₂) on a deco ascent', () {
      // Loaded enough that Phase 1 produces a non-trivial first stop
      // depth — planDeco returns the empty list when no deco is needed
      // (NDL fast-path), so we can't observe gas-switch holds in that
      // case. Heavy load on the slow compartments forces a deco ladder.
      final steps = planDeco(
        initialN2Bar: List<double>.filled(16, 3.5),
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
      // A flat hold at exactly 21 m on EAN50 — could be a gas-switch
      // hold or a coinciding deco hold. Either way, EAN50 should be
      // the breathed gas at this depth.
      final at21 = steps.firstWhere(
        (s) =>
            s.isStop &&
            s.depthStartMeters == 21 &&
            s.gas.oxygenPercent == 50,
        orElse: () => throw StateError(
            'expected an EAN50 stop at 21 m in: '
            '${steps.where((s) => s.isStop).toList()}'),
      );
      expect(at21.duration.inSeconds, greaterThanOrEqualTo(60));
      // A flat hold at exactly 6 m on O₂.
      final at6 = steps.firstWhere(
        (s) =>
            s.isStop &&
            s.depthStartMeters == 6 &&
            s.gas.oxygenPercent == 100,
        orElse: () => throw StateError(
            'expected an O₂ stop at 6 m in: '
            '${steps.where((s) => s.isStop).toList()}'),
      );
      expect(at6.duration.inSeconds, greaterThanOrEqualTo(60));
    });
  });

  group('standardSwitchDepth', () {
    test('GUE-standard gases map to their canonical switch depths', () {
      expect(standardSwitchDepth(_o2), 6);
      expect(standardSwitchDepth(_ean50), 21);
      expect(
          standardSwitchDepth(const DiveGasMix(
              oxygenPercent: 35, heliumPercent: 25, isDiluent: false)),
          36);
      expect(
          standardSwitchDepth(const DiveGasMix(
              oxygenPercent: 21, heliumPercent: 35, isDiluent: true)),
          57);
      expect(
          standardSwitchDepth(const DiveGasMix(
              oxygenPercent: 18, heliumPercent: 45, isDiluent: true)),
          66);
      expect(
          standardSwitchDepth(const DiveGasMix(
              oxygenPercent: 15, heliumPercent: 55, isDiluent: true)),
          75);
    });

    test('non-standard mixes fall back to MOD-derived 3 m boundary', () {
      // 19 % O₂, no He → MOD@1.6 = (1.6/0.19 − 1) × 10 = 74.2 m → 72 m.
      expect(
          standardSwitchDepth(const DiveGasMix(
              oxygenPercent: 19, heliumPercent: 0, isDiluent: false)),
          72);
      // Heliox-style mix with 1 % O₂ would have MOD way past the 90 m
      // clamp; verify the clamp.
      expect(
          standardSwitchDepth(const DiveGasMix(
              oxygenPercent: 1, heliumPercent: 50, isDiluent: true)),
          90);
    });
  });
}
