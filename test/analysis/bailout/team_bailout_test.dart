import 'package:ccrlogger/analysis/bailout/bailout_result.dart';
import 'package:ccrlogger/analysis/bailout/tank_recommender.dart'
    show kAl40, kAl80, kTank12L300;
import 'package:ccrlogger/analysis/bailout/team_bailout.dart';
import 'package:ccrlogger/data/models/dive.dart' show DiveGasMix;
import 'package:flutter_test/flutter_test.dart';

const _tx968 =
    DiveGasMix(oxygenPercent: 9, heliumPercent: 68, isDiluent: true);
const _tx2135 =
    DiveGasMix(oxygenPercent: 21, heliumPercent: 35, isDiluent: false);
const _ean50 =
    DiveGasMix(oxygenPercent: 50, heliumPercent: 0, isDiluent: false);
const _o2 =
    DiveGasMix(oxygenPercent: 100, heliumPercent: 0, isDiluent: false);

const _tanks = [kAl40, kAl80, kTank12L300];

BailoutResult _result(Map<DiveGasMix, double> volumes) => BailoutResult(
      scenario: BailoutScenario.gueStandards,
      totalTime: Duration.zero,
      stops: const [],
      perGas: {
        for (final e in volumes.entries) e.key: GasUsage(requiredL: e.value),
      },
      verdict: BailoutVerdict.sufficient,
      verdictDetails: const [],
    );

void main() {
  test('teamSize 1 → empty (solo plan IS the carry)', () {
    final out = distributeForTeam(
      solo: _result({_tx968: 1800, _ean50: 770, _o2: 600}),
      teamSize: 1,
      availableTanks: _tanks,
    );
    expect(out, isEmpty);
  });

  test('team of 2 splits 3-stage solo plan: each diver carries bottom + 1 deco',
      () {
    final out = distributeForTeam(
      solo: _result({_tx968: 1800, _ean50: 770, _o2: 600}),
      teamSize: 2,
      availableTanks: _tanks,
    );
    expect(out.length, 2);

    // Both divers carry bottom mix.
    final bottomCarriers =
        out.where((d) => d.stages.any((s) => s.gas == _tx968)).length;
    expect(bottomCarriers, 2);

    // Bottom-mix per-stage volume = solo / 2 = 900 L.
    final bottomStage =
        out.first.stages.firstWhere((s) => s.gas == _tx968);
    expect(bottomStage.perStageVolumeL, closeTo(900, 1));

    // EAN 50 and O₂ each carried by exactly one diver.
    final eanCarriers =
        out.where((d) => d.stages.any((s) => s.gas == _ean50)).length;
    final o2Carriers =
        out.where((d) => d.stages.any((s) => s.gas == _o2)).length;
    expect(eanCarriers, 1);
    expect(o2Carriers, 1);

    // Each diver carries 2 stages total.
    expect(out.every((d) => d.stages.length == 2), isTrue);
  });

  test('team of 3 with 3-stage solo: one diver carries only bottom', () {
    final out = distributeForTeam(
      solo: _result({_tx968: 1800, _ean50: 770, _o2: 600}),
      teamSize: 3,
      availableTanks: _tanks,
    );
    expect(out.length, 3);

    // Each diver carries bottom mix.
    expect(out.every((d) => d.stages.any((s) => s.gas == _tx968)), isTrue);

    // Bottom per-stage volume = 1800 / 3 = 600 L.
    final bottom = out.first.stages.firstWhere((s) => s.gas == _tx968);
    expect(bottom.perStageVolumeL, closeTo(600, 1));

    // One diver ends up with bottom-only (the round-robin assigns
    // EAN 50 to one, O₂ to the next, nothing to the third).
    final stageCounts = out.map((d) => d.stages.length).toList()..sort();
    expect(stageCounts, [1, 2, 2]);
  });

  test('team of 2 with 5-stage solo (deep dive): each carries bottom + 2 deco',
      () {
    final out = distributeForTeam(
      solo: _result({
        _tx968: 4000,
        _tx2135: 600,
        _ean50: 800,
        _o2: 600,
      }),
      teamSize: 2,
      availableTanks: _tanks,
    );
    expect(out.length, 2);
    // 4 distinct gases, 2 divers → bottom on both, 3 deco gases split
    // unevenly (2 on one diver, 1 on the other).
    final stageCounts = out.map((d) => d.stages.length).toList()..sort();
    expect(stageCounts, [2, 3]);
  });

  test('empty solo plan returns empty', () {
    final out = distributeForTeam(
      solo: _result(const {}),
      teamSize: 3,
      availableTanks: _tanks,
    );
    expect(out, isEmpty);
  });
}
