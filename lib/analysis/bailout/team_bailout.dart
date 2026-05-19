/// Team bailout distribution — splits a solo bailout plan across a
/// buddy team so the per-diver carry shrinks.
///
/// Model: total team-carried volume per gas equals the solo-required
/// volume (one OC bailout, the team supports the bailing-out diver).
///
/// Distribution rules:
///   1. Every diver carries one stage of the bottom mix. Each diver's
///      stage holds `solo_bottom_volume / team_size` litres — the team's
///      total bottom-mix carry equals the solo requirement.
///   2. Each deco-gas stage is carried by ONE diver (you can't half-fill
///      an O₂ tank across two people). Stages are assigned round-robin
///      to whichever diver has the smallest count of stages so far.
///   3. For deco gases, per-stage volume = solo-required / N_carriers.
///   4. Tank picks come from the same [recommend] used for solo plans.
library;

import '../../data/models/dive.dart' show DiveGasMix;
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

  // Track per-diver gas assignments.
  final assigned = List.generate(teamSize, (_) => <DiveGasMix>[]);

  // Step 1: every diver carries one bottom-mix stage.
  for (final list in assigned) {
    list.add(bottomMix);
  }

  // Step 2: distribute deco-gas stages round-robin to the diver with
  // the fewest stages so far.
  for (final entry in usedGases) {
    final gas = entry.key;
    if (gas == bottomMix) continue;
    var minIdx = 0;
    for (var i = 1; i < teamSize; i++) {
      if (assigned[i].length < assigned[minIdx].length) minIdx = i;
    }
    assigned[minIdx].add(gas);
  }

  // Step 3: build TeamCarry records. Per-stage volume = required / N_carriers.
  final carriersByGas = <DiveGasMix, int>{};
  for (final list in assigned) {
    for (final gas in list) {
      carriersByGas[gas] = (carriersByGas[gas] ?? 0) + 1;
    }
  }
  final volumeByGas = {
    for (final entry in usedGases) entry.key: entry.value.requiredL,
  };

  final out = <TeamCarry>[];
  for (var i = 0; i < teamSize; i++) {
    final stages = <TeamGasStage>[];
    for (final gas in assigned[i]) {
      final perStage = volumeByGas[gas]! / carriersByGas[gas]!;
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
