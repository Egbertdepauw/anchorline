/// Team bailout distribution — splits the SET of bailout stages across
/// a buddy team so the per-diver carry count shrinks.
///
/// Volume model: full redundancy, NOT shared. Every stage a diver carries
/// holds the same volume the solo plan requires — if a diver is the one
/// bailing out and gets separated from the team, their own stages must
/// last the whole ascent. Sharing volumes across divers (so each carries
/// 1/N of the requirement) creates a dependency on team handoffs that
/// fails the moment the team is split.
///
/// Distribution rules:
///   1. Every diver carries one stage of the bottom mix at the FULL
///      solo-required volume.
///   2. Every diver ALSO carries the "must-have" shallow deco gas (the
///      richest non-O₂ deco gas in the plan — typically EAN 50) at the
///      FULL solo-required volume. Together with the bottom mix, this
///      gives every diver an independent self-bailout chain to the 6 m
///      stop even if the team is separated.
///   3. Remaining deco-gas stages (intermediates, O₂) are carried by
///      one diver each, also at the full solo-required volume. Stages
///      assigned round-robin to whichever diver has the fewest stages
///      so far.
///   4. Tank picks come from the same [recommend] used for solo plans.
library;

import 'package:subsurface_core/data/models/dive.dart' show DiveGasMix;
import 'bailout_result.dart' show BailoutResult;
import 'tank_recommender.dart' show TankRecommendation, TankSpec, recommend;

/// One diver's contribution to the team carry.
class TeamCarry {
  /// 1-based diver index.
  final int diverIndex;

  /// Stages this diver carries. Each stage = one tank of one gas.
  final List<TeamGasStage> stages;

  const TeamCarry({required this.diverIndex, required this.stages});
}

/// A single stage carried by one team member.
class TeamGasStage {
  final DiveGasMix gas;

  /// Litres of gas in this individual stage (one diver, one tank).
  final double perStageVolumeL;

  /// Tank recommendation for [perStageVolumeL]. Null only when the tank
  /// catalogue is empty.
  final TankRecommendation? tank;

  const TeamGasStage({
    required this.gas,
    required this.perStageVolumeL,
    required this.tank,
  });
}

/// Distribute the [solo] plan across a team of [teamSize] divers and
/// return one [TeamCarry] per diver.
///
/// Returns an empty list when [teamSize] ≤ 1 (no distribution needed
/// — the solo plan IS the carry).
List<TeamCarry> distributeForTeam({
  required BailoutResult solo,
  required int teamSize,
  required List<TankSpec> availableTanks,
}) {
  if (teamSize <= 1) return const [];

  // Used gases sorted largest-volume first so the biggest stages go to
  // empty divers earliest (keeps the carry count balanced).
  final usedGases = solo.perGas.entries
      .where((e) => e.value.requiredL > 0)
      .toList()
    ..sort((a, b) => b.value.requiredL.compareTo(a.value.requiredL));
  if (usedGases.isEmpty) return const [];

  // Bottom mix = the lowest-O₂ gas the plan actually used.
  final bottomMix = usedGases
      .map((e) => e.key)
      .reduce((a, b) => a.oxygenPercent <= b.oxygenPercent ? a : b);

  // Must-have shallow deco gas = richest non-O₂ deco gas in the plan,
  // typically EAN 50. The "minimum self-bailout chain" is bottom +
  // this gas, getting any diver from depth to a 6 m hold solo. Null
  // when the plan has no deco gas at all (shallow dive) or only O₂.
  DiveGasMix? mustHaveDeco;
  for (final entry in usedGases) {
    final gas = entry.key;
    if (gas == bottomMix) continue;
    if (gas.oxygenPercent >= 100) continue; // skip pure O₂
    if (mustHaveDeco == null ||
        gas.oxygenPercent > mustHaveDeco.oxygenPercent) {
      mustHaveDeco = gas;
    }
  }

  // Track per-diver gas assignments.
  final assigned = List.generate(teamSize, (_) => <DiveGasMix>[]);

  // Step 1: every diver carries one bottom-mix stage.
  for (final list in assigned) {
    list.add(bottomMix);
  }

  // Step 2: every diver also carries the must-have shallow deco gas.
  if (mustHaveDeco != null) {
    for (final list in assigned) {
      list.add(mustHaveDeco);
    }
  }

  // Step 3: remaining deco gases distribute round-robin to the diver
  // with the fewest stages so far.
  for (final entry in usedGases) {
    final gas = entry.key;
    if (gas == bottomMix) continue;
    if (gas == mustHaveDeco) continue;
    var minIdx = 0;
    for (var i = 1; i < teamSize; i++) {
      if (assigned[i].length < assigned[minIdx].length) minIdx = i;
    }
    assigned[minIdx].add(gas);
  }

  // Step 4: build TeamCarry records. Per-stage volume = full solo
  // requirement (NOT divided across carriers — see redundancy note in
  // the library doc above).
  final volumeByGas = {
    for (final entry in usedGases) entry.key: entry.value.requiredL,
  };

  final out = <TeamCarry>[];
  for (var i = 0; i < teamSize; i++) {
    final stages = <TeamGasStage>[];
    for (final gas in assigned[i]) {
      final perStage = volumeByGas[gas]!;
      stages.add(TeamGasStage(
        gas: gas,
        perStageVolumeL: perStage,
        tank: recommend(
          volumeLitres: perStage,
          availableTanks: availableTanks,
        ),
      ));
    }
    out.add(TeamCarry(diverIndex: i + 1, stages: stages));
  }
  return out;
}
