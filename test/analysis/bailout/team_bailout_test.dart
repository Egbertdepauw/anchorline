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
      scenario: BailoutScenario.standardGases,
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

  test('team of 2 with 3-stage solo: both carry bottom + EAN 50, '
      'one additionally carries O₂ — each at FULL solo volume', () {
    final out = distributeForTeam(
      solo: _result({_tx968: 1800, _ean50: 770, _o2: 600}),
      teamSize: 2,
      availableTanks: _tanks,
    );
    expect(out.length, 2);

    // Every diver carries bottom AND EAN 50 (must-have shallow deco).
    expect(out.every((d) => d.stages.any((s) => s.gas == _tx968)), isTrue);
    expect(out.every((d) => d.stages.any((s) => s.gas == _ean50)), isTrue);

    // Full-redundancy volumes — each diver's stage = full solo requirement
    // (NOT divided across the team). A separated diver must self-bailout
    // on their own gas.
    final bottom = out.first.stages.firstWhere((s) => s.gas == _tx968);
    expect(bottom.perStageVolumeL, closeTo(1800, 1));
    final ean = out.first.stages.firstWhere((s) => s.gas == _ean50);
    expect(ean.perStageVolumeL, closeTo(770, 1));

    // O₂ is carried by exactly one diver — only one stage in the team.
    final o2Carriers =
        out.where((d) => d.stages.any((s) => s.gas == _o2)).length;
    expect(o2Carriers, 1);

    final stageCounts = out.map((d) => d.stages.length).toList()..sort();
    expect(stageCounts, [2, 3]);
  });

  test('team of 3 with 3-stage solo: every diver has bottom + EAN 50 '
      '(no one is left with only bottom mix)', () {
    final out = distributeForTeam(
      solo: _result({_tx968: 1800, _ean50: 770, _o2: 600}),
      teamSize: 3,
      availableTanks: _tanks,
    );
    expect(out.length, 3);

    // Every diver carries bottom AND EAN 50 — minimum self-bailout chain
    // to the 6 m stop. This was the original gap the user flagged.
    expect(out.every((d) => d.stages.any((s) => s.gas == _tx968)), isTrue);
    expect(out.every((d) => d.stages.any((s) => s.gas == _ean50)), isTrue);

    // Full solo volume on every diver's stage (no division by team size).
    final bottom = out.first.stages.firstWhere((s) => s.gas == _tx968);
    expect(bottom.perStageVolumeL, closeTo(1800, 1));

    // O₂ carried by exactly one diver.
    final o2Carriers =
        out.where((d) => d.stages.any((s) => s.gas == _o2)).length;
    expect(o2Carriers, 1);

    // Two divers carry 2 stages (bottom + EAN50), one carries 3
    // (bottom + EAN50 + O2).
    final stageCounts = out.map((d) => d.stages.length).toList()..sort();
    expect(stageCounts, [2, 2, 3]);
  });

  test('team of 3 with 5-stage solo (deep dive): every diver carries '
      'bottom + EAN 50; intermediates split symmetrically', () {
    final out = distributeForTeam(
      solo: _result({
        _tx968: 4000,
        _tx2135: 600,
        _ean50: 800,
        _o2: 600,
      }),
      teamSize: 3,
      availableTanks: _tanks,
    );
    expect(out.length, 3);

    // Every diver has the must-haves.
    expect(out.every((d) => d.stages.any((s) => s.gas == _tx968)), isTrue);
    expect(out.every((d) => d.stages.any((s) => s.gas == _ean50)), isTrue);

    // Remaining gases (TX 21/35 + O₂) distributed across the 3 divers
    // so each carries 3 stages total.
    final stageCounts = out.map((d) => d.stages.length).toList()..sort();
    expect(stageCounts, [2, 3, 3]);
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
