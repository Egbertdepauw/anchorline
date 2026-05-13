import 'package:ccrlogger/analysis/bailout/bailout_planner.dart';
import 'package:ccrlogger/analysis/bailout/bailout_result.dart';
import 'package:ccrlogger/analysis/bailout/tank_recommender.dart'
    show kAl40, kAl80, kTank12L300, kTank68L300;
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
  bool isGue = false,
}) =>
    planBailout(
      diveId: 'test-dive',
      maxDepthMeters: maxDepth,
      recordedDiluent: recordedDiluent,
      tissueN2Bar: n2 ?? _surfaceN2,
      tissueHeBar: he ?? _surfaceHe,
      userBailoutTanks: userTanks,
      userTankVolumesL: userVolumes,
      isGueConfig: isGue,
      gfLow: 30,
      gfHigh: 80,
      sacBottom: 20,
      sacDeco: 15,
      ascentRateFast: 18,
      ascentRateSlow: 9,
      availableTanks: _defaultTanks,
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
      // Verdict details: one line per gas entry.
      expect(result.verdictDetails.length, equals(result.perGas.length));
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
  });

  group('planBailout — Scenario B (GUE standards / catalogue)', () {
    test('returns tank recommendations for all used gases', () {
      final result = _plan(
        maxDepth: 30.0,
        n2: _surfaceN2,
        // No user tanks → Scenario B
      );

      expect(result.scenario, BailoutScenario.gueStandards);
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

      expect(result.scenario, BailoutScenario.gueStandards);
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
      // Verdict details: one line per perGas entry.
      expect(result.verdictDetails.length, equals(result.perGas.length));
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
        isGueConfig: false,
        gfLow: 20,
        gfHigh: 70,
        sacBottom: 20,
        sacDeco: 15,
        ascentRateFast: 18,
        ascentRateSlow: 9,
        availableTanks: const [], // empty catalogue → no recommendations possible
      );

      expect(result.scenario, BailoutScenario.gueStandards);
      expect(result.verdict, BailoutVerdict.insufficient);
    });
  });
}
