import 'package:ccrlogger/analysis/bailout/bailout_planner.dart';
import 'package:ccrlogger/analysis/bailout/bailout_result.dart';
import 'package:ccrlogger/analysis/bailout/tank_recommender.dart'
    show TankSpec, kAl40, kAl80, kTank12L300, kTank68L300;
import 'package:ccrlogger/data/models/dive.dart' show DiveGasMix;
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Shared fixtures
// ---------------------------------------------------------------------------

/// Minimal 16-compartment tissue state: air-saturated at surface.
/// N2 ≈ 0.75 bar (surface), He = 0 bar.
List<double> get _surfaceN2 => List.filled(16, 0.75);
List<double> get _surfaceHe => List.filled(16, 0.0);

/// A lightly loaded tissue state that produces a non-trivial but short deco
/// plan from 30 m.  Compartments are bumped up slightly from surface values
/// to guarantee at least one stop.
List<double> get _loadedN2 => List.generate(16, (i) => i < 4 ? 1.1 : 0.75);

/// Heavily-loaded tissue state representing a real tech bailout from
/// 80–145 m after ~30 min of bottom time. Forces multi-stop deco so
/// deco-gas consumption is non-trivial (above the planner's "useful
/// stage" threshold of 200 L). Surface tissues with deep depth give a
/// "blink-and-bailout" plan with trivial deco gas use, which the trivial-
/// gas filter correctly drops — useful behaviour but not what these
/// depth-driven tests are pinning.
List<double> get _techLoadedN2 =>
    List.generate(16, (i) => i < 8 ? 2.6 : 1.6);
List<double> get _techLoadedHe =>
    List.generate(16, (i) => i < 8 ? 0.7 : 0.3);

const _ean32 = DiveGasMix(oxygenPercent: 32, heliumPercent: 0, isDiluent: false);
const _ean50 = DiveGasMix(oxygenPercent: 50, heliumPercent: 0, isDiluent: false);
const _o2 = DiveGasMix(oxygenPercent: 100, heliumPercent: 0, isDiluent: false);
const _air = DiveGasMix(oxygenPercent: 21, heliumPercent: 0, isDiluent: false);

const _defaultTanks = [kAl40, kAl80, kTank68L300, kTank12L300];

BailoutResult _plan({
  double maxDepth = 30.0,
  DiveGasMix? recordedDiluent,
  List<double>? n2,
  List<double>? he,
  List<DiveGasMix> userTanks = const [],
  Map<DiveGasMix, double> userVolumes = const {},
  bool bailoutCapableDiluent = false,
  List<TankSpec> availableTanks = _defaultTanks,
  int sacBottom = 20,
}) =>
    planBailout(
      diveId: 'test-dive',
      maxDepthMeters: maxDepth,
      recordedDiluent: recordedDiluent,
      tissueN2Bar: n2 ?? _surfaceN2,
      tissueHeBar: he ?? _surfaceHe,
      userBailoutTanks: userTanks,
      userTankVolumesL: userVolumes,
      bailoutCapableDiluent: bailoutCapableDiluent,
      gfLow: 30,
      gfHigh: 80,
      sacBottom: sacBottom,
      sacDeco: 15,
      ascentRateFast: 18,
      ascentRateSlow: 9,
      availableTanks: availableTanks,
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('planBailout — Scenario A (user-defined tanks)', () {
    test('sufficient: every gas has ample volume', () {
      // Give very generous volumes so nothing can be short.
      final result = _plan(
        maxDepth: 25.0,
        userTanks: [_air, _ean50],
        userVolumes: {_air: 2000.0, _ean50: 2000.0},
        n2: _surfaceN2,
      );

      expect(result.scenario, BailoutScenario.tanksDefined);
      expect(result.verdict, BailoutVerdict.sufficient);
      // perGas must cover at least the gases returned by the simulator.
      expect(result.perGas, isNotEmpty);
      // Every used gas must have an availableL value.
      for (final usage in result.perGas.values) {
        expect(usage.availableL, isNotNull);
        expect(usage.recommendedTank, isNull);
      }
      // Verdict details: one line per gas entry, plus a leading
      // bottom-mix PPO2 / ρ summary line.
      expect(result.verdictDetails.length, equals(result.perGas.length + 1));
    });

    test('partialShortfall: one gas is short, another is fine', () {
      // EAN 50 gets generous volume; Air gets 0 L (the bottom mix will need
      // some volume, so this forces a shortfall on Air).
      final result = _plan(
        maxDepth: 25.0,
        userTanks: [_air, _ean50],
        userVolumes: {
          _air: 10.0,  // deliberately very small — below any real requirement
          _ean50: 2000.0,
        },
        n2: _loadedN2,
      );

      expect(result.scenario, BailoutScenario.tanksDefined);
      // The plan consumed some Air. 10 L is almost certainly not enough.
      // We expect either partialShortfall or insufficient depending on whether
      // EAN 50 is actually used. At minimum the verdict must NOT be sufficient.
      expect(
        result.verdict,
        anyOf(BailoutVerdict.partialShortfall, BailoutVerdict.insufficient),
      );
      expect(result.stops, isNotEmpty);
    });

    test('structure: stops list + totalTime are populated', () {
      final result = _plan(
        maxDepth: 30.0,
        userTanks: [_air, _ean32, _ean50, _o2],
        userVolumes: {
          _air: 3000.0,
          _ean32: 500.0,
          _ean50: 500.0,
          _o2: 200.0,
        },
        n2: _loadedN2,
      );

      expect(result.stops, isNotEmpty);
      expect(result.totalTime.inSeconds, greaterThan(0));
      // Number of perGas entries must be ≥ 1 (at least the bottom mix was used).
      expect(result.perGas.length, greaterThanOrEqualTo(1));
    });

    test(
        'bailout-capable diluent drops EAN 32: a 67 m dive bails out on TMX + EAN50 + O2 '
        'only, not EAN 32', () {
      const dil18_45 = DiveGasMix(
        oxygenPercent: 18,
        heliumPercent: 45,
        isDiluent: true,
      );
      final result = _plan(
        maxDepth: 67.0,
        recordedDiluent: dil18_45,
        bailoutCapableDiluent: true,
      );
      final gasesUsed = result.perGas.keys.toSet();
      expect(
        gasesUsed.any((g) => g.oxygenPercent == 32 && g.heliumPercent == 0),
        isFalse,
        reason: 'standard-gas bailout never carries EAN 32',
      );
    });

    test(
        'bailout-capable diluent: shallow dive (≤ 21 m) → only the bottom mix is in the '
        'gas list (no deco gases)', () {
      const dil21 = DiveGasMix(
        oxygenPercent: 21,
        heliumPercent: 0,
        isDiluent: true,
      );
      final result = _plan(
        maxDepth: 20.0,
        recordedDiluent: dil21,
        bailoutCapableDiluent: true,
      );
      // No EAN 50 or O2 in any used gas.
      for (final gas in result.perGas.keys) {
        expect(gas.oxygenPercent, lessThanOrEqualTo(21),
            reason:
                'shallow bailout (≤21 m) should not pick up EAN50 / O2');
      }
    });

    test(
        'bailout-capable diluent: 50 m dive → 2 stages (bottom + EAN50, no O2)', () {
      const dil21_35 = DiveGasMix(
        oxygenPercent: 21,
        heliumPercent: 35,
        isDiluent: true,
      );
      final result = _plan(
        maxDepth: 50.0,
        recordedDiluent: dil21_35,
        bailoutCapableDiluent: true,
      );
      final hasO2 = result.perGas.keys
          .any((g) => g.oxygenPercent == 100 && g.heliumPercent == 0);
      expect(hasO2, isFalse,
          reason:
              'bailout under 65 m should not need an O₂ deco stage');
    });

    test(
        'Scenario A with only deco gases at 51 m → planner injects a bottom '
        'mix so the first leg is not breathed on EAN 50', () {
      // User defined ONLY deco cylinders (50/100). At 51 m none of them are
      // safe (PPO2 > 1.6). The planner must prepend a resolved bottom mix
      // so the first ascent leg isn't pure-CNS-hit territory.
      const dil18_45 = DiveGasMix(
        oxygenPercent: 18,
        heliumPercent: 45,
        isDiluent: true,
      );
      final result = _plan(
        maxDepth: 51.0,
        recordedDiluent: dil18_45,
        userTanks: const [_ean50, _o2],
        userVolumes: const {_ean50: 1800.0, _o2: 1800.0},
        bailoutCapableDiluent: true,
      );
      expect(result.stops, isNotEmpty);
      final firstGas = result.stops.first.gas;
      const ambient51m = 1.013 + 5.1;
      final firstGasPpo2 = (firstGas.oxygenPercent / 100.0) * ambient51m;
      expect(firstGasPpo2, lessThanOrEqualTo(1.6),
          reason:
              'planner must prepend a depth-safe bottom mix when user tanks are deco-only');
    });
  });

  group('planBailout — Scenario B (standard gases / catalogue)', () {
    test('returns tank recommendations for all used gases', () {
      final result = _plan(
        maxDepth: 30.0,
        n2: _surfaceN2,
        // No user tanks → Scenario B
      );

      expect(result.scenario, BailoutScenario.standardGases);
      expect(result.perGas, isNotEmpty);
      // In Scenario B availableL must be null; recommendedTank may be non-null.
      for (final usage in result.perGas.values) {
        expect(usage.availableL, isNull);
      }
      // At least the bottom-mix gas must appear.
      expect(result.stops, isNotEmpty);
      expect(result.totalTime.inSeconds, greaterThan(0));
    });

    test('verdict is sufficient when catalogue covers all volumes', () {
      // At 20 m with surface tissues the required volumes are modest — the
      // default catalogue (AL40 → AL80 → 6.8L → 12L) should cover them.
      final result = _plan(
        maxDepth: 20.0,
        n2: _surfaceN2,
      );

      expect(result.scenario, BailoutScenario.standardGases);
      expect(result.verdict, BailoutVerdict.sufficient);
      // Every used gas must have a recommendation.
      for (final entry in result.perGas.entries) {
        if (entry.value.requiredL > 0) {
          expect(
            entry.value.recommendedTank,
            isNotNull,
            reason: 'No recommendation for ${entry.key}',
          );
        }
      }
      // Verdict details: one line per perGas entry, plus a leading
      // bottom-mix PPO2 / ρ summary line.
      expect(result.verdictDetails.length, equals(result.perGas.length + 1));
    });

    test('insufficient when no tank in catalogue can cover extreme volume', () {
      // Very deep dive with heavily loaded tissues → huge gas requirement.
      // Pass an empty availableTanks list so recommend() always returns null.
      final result = planBailout(
        diveId: 'deep-test',
        maxDepthMeters: 80.0,
        recordedDiluent: null,
        tissueN2Bar: List.filled(16, 2.5), // heavily loaded
        tissueHeBar: List.filled(16, 1.0),
        userBailoutTanks: const [],
        userTankVolumesL: const {},
        bailoutCapableDiluent: false,
        gfLow: 20,
        gfHigh: 70,
        sacBottom: 20,
        sacDeco: 15,
        ascentRateFast: 18,
        ascentRateSlow: 9,
        availableTanks: const [], // empty catalogue → no recommendations possible
      );

      expect(result.scenario, BailoutScenario.standardGases);
      expect(result.verdict, BailoutVerdict.insufficient);
    });

    test(
        'bailout-capable diluent at 51 m on 18/45 diluent uses a trimix bottom mix, never '
        'starts the ascent on a deco gas (CNS-hit regression)', () {
      // Reproducer for the EAN 50 @ 51 m bug: a CCR diver on 18/45 diluent
      // bails out at 51 m. The OC plan must NOT start on EAN 50 — PPO2
      // would be ~3 bar.
      const dil18_45 = DiveGasMix(
        oxygenPercent: 18,
        heliumPercent: 45,
        isDiluent: true,
      );
      final result = _plan(
        maxDepth: 51.0,
        recordedDiluent: dil18_45,
        bailoutCapableDiluent: true,
      );
      expect(result.stops, isNotEmpty);
      final firstGas = result.stops.first.gas;
      // The first breathed gas must be safe to inhale at 51 m (PPO2 ≤ 1.6).
      const ambient51m = 1.013 + 5.1;
      final firstGasPpo2 = (firstGas.oxygenPercent / 100.0) * ambient51m;
      expect(firstGasPpo2, lessThanOrEqualTo(1.6),
          reason: 'first bailout gas PPO2 at 51 m must be ≤ 1.6 bar');
      expect(firstGas.heliumPercent, greaterThan(0),
          reason: 'a 51 m bailout must start on trimix, not nitrox');
    });

    test(
        'bailout-capable diluent at 80 m with normal catalogue: NO intermediate trimix — '
        '3 stages (bottom + EAN50 + O2) is enough', () {
      // Volume-driven escalation: at 80 m on 18/45 with the default
      // catalogue (largest tank = 12L/300 = 3600 L), bottom-mix on the OC
      // ascent fits comfortably in one stage. No reason to carry TX 21/35.
      const dil18_45 = DiveGasMix(
        oxygenPercent: 18,
        heliumPercent: 45,
        isDiluent: true,
      );
      final result = _plan(
        maxDepth: 80.0,
        recordedDiluent: dil18_45,
        bailoutCapableDiluent: true,
        // Moderate tissue load — enough deco for EAN 50 / O₂ to see real
        // use (≥ 200 L, above the trivial-stage threshold) without
        // pushing bottom-mix volume past AL80. Heavier load would force
        // an intermediate trimix; lighter would filter EAN 50 out.
        n2: List.generate(16, (i) => i < 8 ? 2.0 : 1.2),
        he: List.generate(16, (i) => i < 8 ? 0.3 : 0.1),
      );
      final gases = result.perGas.keys.toSet();
      bool hasMix(int o2, int he) => gases.any(
          (g) => g.oxygenPercent == o2 && g.heliumPercent == he);
      expect(hasMix(21, 35), isFalse,
          reason: 'TX 21/35 not needed — bottom mix fits in one tank');
      expect(hasMix(35, 25), isFalse,
          reason: 'TX 35/25 not needed at 80 m');
      expect(hasMix(50, 0), isTrue);
      expect(hasMix(100, 0), isTrue);
    });

    test(
        'bailout-capable diluent at 145 m with constrained catalogue (AL80 only) adds '
        'intermediate trimixes when bottom-mix would overflow one tank', () {
      // Reproducer for the deep-cave-dive feedback (2026-05-19): once
      // bottom-mix volume overflows the largest tank in the catalogue,
      // the planner must insert TX 21/35 (57 m switch) and then TX 35/25
      // (36 m switch) to drop bottom-mix consumption.
      const dil10_70 = DiveGasMix(
        oxygenPercent: 10,
        heliumPercent: 70,
        isDiluent: true,
      );
      final result = _plan(
        maxDepth: 145.0,
        recordedDiluent: dil10_70,
        bailoutCapableDiluent: true,
        // Force overflow: AL80 (2575 L) caps the largest stage; a heavily
        // breathing diver tips bottom-mix over the edge at this depth.
        availableTanks: const [kAl40, kAl80],
        sacBottom: 50,
        // Realistic deep-trimix loading so the deco gases (EAN 50, O₂)
        // see meaningful use and survive the trivial-gas filter.
        n2: _techLoadedN2,
        he: _techLoadedHe,
      );
      final gases = result.perGas.keys.toSet();
      bool hasMix(int o2, int he) => gases.any(
          (g) => g.oxygenPercent == o2 && g.heliumPercent == he);
      expect(hasMix(21, 35), isTrue,
          reason: 'TX 21/35 must be added once bottom-mix overflows AL80');
      expect(hasMix(50, 0), isTrue, reason: 'EAN 50 must be present');
      expect(hasMix(100, 0), isTrue, reason: 'O₂ must be present');
    });
  });
}
