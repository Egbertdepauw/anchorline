/// Bailout planner orchestrator.
///
/// [planBailout] is the single entry point for the bailout planning feature.
/// It detects the planning scenario, builds the gas list, runs the ascent
/// simulator, and wraps the result in a [BailoutResult].
///
/// **Scenario A** — user has defined explicit bailout tanks.
///   - Gas list: user-supplied tanks, sorted bottom-mix first.
///   - Verdict: compares required vs available volume for every gas.
///
/// **Scenario B** — no user tanks supplied; planner picks standard mixes and
///   recommends a tank from the supplied catalogue.
///   - Gas list: resolved bottom mix + [kDecoMixes].
///   - Verdict: sufficient if a tank recommendation exists for every gas.
library;

import '../../data/models/dive.dart' show DiveGasMix;
import 'ascent_simulator.dart' show AscentPlan, simulateAscent;
import 'bailout_result.dart';
import 'mix_resolver.dart' show resolveBottomMix;
import 'standard_mixes.dart' show kDecoMixes;
import 'tank_recommender.dart' show TankSpec, recommend;

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Plan an open-circuit bailout ascent.
///
/// Parameters
/// ----------
/// [diveId]              Identifier of the dive (unused in the calculation,
///                       forwarded to the caller for correlation).
/// [maxDepthMeters]      Maximum depth reached on the dive (metres).
/// [recordedDiluent]     Diluent recorded by the dive computer, if known.
/// [tissueN2Bar]         16-element list: N2 tissue loads at trigger point.
/// [tissueHeBar]         16-element list: He tissue loads at trigger point.
/// [userBailoutTanks]    User-defined bailout gas mixes (Scenario A).
///                       Pass an empty list to trigger Scenario B.
/// [userTankVolumesL]    Available volume in litres per user tank (Scenario A).
/// [isGueConfig]         Whether to apply GUE standards for mix resolution and
///                       gas list construction.
/// [gfLow]               Low gradient factor (1–100).
/// [gfHigh]              High gradient factor (1–100).
/// [sacBottom]           Surface-equivalent air consumption at depth (L/min).
/// [sacDeco]             Surface-equivalent air consumption at deco (L/min).
/// [ascentRateFast]      Ascent rate used above the slowdown depth (m/min).
/// [ascentRateSlow]      Ascent rate used below the slowdown depth (m/min).
/// [availableTanks]      Tank catalogue for Scenario B recommendations.
///                       Should be sorted smallest-to-largest by water
///                       capacity so [recommend] picks the smallest viable
///                       option first.
BailoutResult planBailout({
  required String diveId,
  required double maxDepthMeters,
  required DiveGasMix? recordedDiluent,
  required List<double> tissueN2Bar,
  required List<double> tissueHeBar,
  required List<DiveGasMix> userBailoutTanks,
  required Map<DiveGasMix, double> userTankVolumesL,
  required bool isGueConfig,
  required int gfLow,
  required int gfHigh,
  required int sacBottom,
  required int sacDeco,
  required int ascentRateFast,
  required int ascentRateSlow,
  required List<TankSpec> availableTanks,
}) {
  // -------------------------------------------------------------------------
  // 1. Detect scenario
  // -------------------------------------------------------------------------
  final scenario = userBailoutTanks.isNotEmpty
      ? BailoutScenario.tanksDefined
      : BailoutScenario.gueStandards;

  // -------------------------------------------------------------------------
  // 2. Build available-gas list
  // -------------------------------------------------------------------------
  final List<DiveGasMix> gases;

  if (scenario == BailoutScenario.tanksDefined) {
    // Scenario A: sort user tanks so the bottom mix (lowest O2) comes first,
    // then deco gases in ascending MOD order (ascending O2 %).
    gases = _sortGasesForAscent(List<DiveGasMix>.from(userBailoutTanks));
  } else {
    // Scenario B: resolve bottom mix then add standard deco gases.
    final bottomMix = resolveBottomMix(
      recordedDiluent: recordedDiluent,
      maxDepthMeters: maxDepthMeters,
      isGueConfig: isGueConfig,
    );

    // For GUE configurations, if the diluent is known and its O2 is suitable
    // (PPO2 ≤ 1.6 at max depth), omit the explicit bottom mix from the
    // bailout gas list — the diluent covers the initial leg.
    final omitBottomMix = isGueConfig &&
        recordedDiluent != null &&
        _isSuitableAtDepth(recordedDiluent, maxDepthMeters);

    gases = [
      if (!omitBottomMix) bottomMix,
      ...kDecoMixes,
    ];
  }

  // -------------------------------------------------------------------------
  // 3. Run ascent simulator
  // -------------------------------------------------------------------------
  final AscentPlan plan = simulateAscent(
    triggerDepthMeters: maxDepthMeters,
    initialN2Bar: tissueN2Bar,
    initialHeBar: tissueHeBar,
    availableGases: gases,
    gfLow: gfLow,
    gfHigh: gfHigh,
    ascentRateFast: ascentRateFast,
    ascentRateSlow: ascentRateSlow,
    sacBottom: sacBottom,
    sacDeco: sacDeco,
  );

  // -------------------------------------------------------------------------
  // 4. Build per-gas usage
  // -------------------------------------------------------------------------
  final perGas = <DiveGasMix, GasUsage>{};

  if (scenario == BailoutScenario.tanksDefined) {
    // Scenario A: compare required vs available.
    for (final entry in plan.volumeByGas.entries) {
      final gas = entry.key;
      final required = entry.value;
      final available = userTankVolumesL[gas]; // null if not in map
      perGas[gas] = GasUsage(
        requiredL: required,
        availableL: available ?? 0.0,
      );
    }
    // Also include user tanks that weren't used (required = 0).
    for (final gas in userBailoutTanks) {
      if (!perGas.containsKey(gas)) {
        perGas[gas] = GasUsage(
          requiredL: 0.0,
          availableL: userTankVolumesL[gas] ?? 0.0,
        );
      }
    }
  } else {
    // Scenario B: recommend a tank for each gas that was used.
    for (final entry in plan.volumeByGas.entries) {
      final gas = entry.key;
      final required = entry.value;
      final rec = recommend(
        volumeLitres: required,
        availableTanks: availableTanks,
      );
      perGas[gas] = GasUsage(
        requiredL: required,
        recommendedTank: rec,
      );
    }
  }

  // -------------------------------------------------------------------------
  // 5. Compute verdict
  // -------------------------------------------------------------------------
  final BailoutVerdict verdict;
  if (scenario == BailoutScenario.tanksDefined) {
    verdict = _verdictScenarioA(perGas);
  } else {
    verdict = _verdictScenarioB(perGas);
  }

  // -------------------------------------------------------------------------
  // 6. Build verdict details
  // -------------------------------------------------------------------------
  final details = _buildVerdictDetails(perGas, scenario);

  return BailoutResult(
    scenario: scenario,
    totalTime: plan.totalTime,
    stops: plan.stops,
    perGas: perGas,
    verdict: verdict,
    verdictDetails: details,
  );
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

/// Sorts gases so the lowest-O2 mix comes first (bottom mix), then deco
/// gases are ordered by ascending O2 % (ascending MOD from deep to shallow).
List<DiveGasMix> _sortGasesForAscent(List<DiveGasMix> gases) {
  gases.sort((a, b) => a.oxygenPercent.compareTo(b.oxygenPercent));
  return gases;
}

/// True if [gas] has a PPO2 ≤ 1.6 bar at [depthMeters].
bool _isSuitableAtDepth(DiveGasMix gas, double depthMeters) {
  final ambient = (depthMeters + 10.0) / 10.0;
  final ppo2 = (gas.oxygenPercent / 100.0) * ambient;
  return ppo2 <= 1.6;
}

/// Verdict for Scenario A (user-defined tanks).
BailoutVerdict _verdictScenarioA(Map<DiveGasMix, GasUsage> perGas) {
  var anyShortfall = false;
  var anyZeroAvailable = false;
  var anyOk = false;

  for (final usage in perGas.values) {
    if (usage.requiredL <= 0.0) continue; // unused gas, skip
    final available = usage.availableL ?? 0.0;
    if (available <= 0.0) {
      anyZeroAvailable = true;
    } else if (available < usage.requiredL) {
      anyShortfall = true;
    } else {
      anyOk = true;
    }
  }

  if (anyZeroAvailable) return BailoutVerdict.insufficient;
  if (anyShortfall) {
    return anyOk
        ? BailoutVerdict.partialShortfall
        : BailoutVerdict.insufficient;
  }
  return BailoutVerdict.sufficient;
}

/// Verdict for Scenario B (GUE standards / catalogue recommendation).
BailoutVerdict _verdictScenarioB(Map<DiveGasMix, GasUsage> perGas) {
  for (final usage in perGas.values) {
    if (usage.requiredL <= 0.0) continue;
    if (usage.recommendedTank == null) return BailoutVerdict.insufficient;
  }
  return BailoutVerdict.sufficient;
}

/// Builds one human-readable line per gas.
List<String> _buildVerdictDetails(
  Map<DiveGasMix, GasUsage> perGas,
  BailoutScenario scenario,
) {
  final lines = <String>[];

  for (final entry in perGas.entries) {
    final gas = entry.key;
    final usage = entry.value;
    final label = _gasLabel(gas);
    final reqL = usage.requiredL.round();

    if (scenario == BailoutScenario.tanksDefined) {
      final avail = (usage.availableL ?? 0.0).round();
      final delta = avail - reqL;
      if (delta >= 0) {
        lines.add('$label ${reqL}L ✓ (+${delta}L available)');
      } else {
        lines.add('$label ${reqL}L short = need +${(-delta)}L');
      }
    } else {
      final rec = usage.recommendedTank;
      if (rec != null) {
        lines.add(
          '$label ${reqL}L → ${rec.tank.name} @ ${rec.minFillPressureBar} bar',
        );
      } else {
        lines.add('$label ${reqL}L → no suitable tank in catalogue');
      }
    }
  }

  return lines;
}

/// Short human-readable label for a gas mix.
String _gasLabel(DiveGasMix gas) {
  if (gas.heliumPercent > 0) {
    return 'TMX ${gas.oxygenPercent}/${gas.heliumPercent}';
  }
  if (gas.oxygenPercent == 100) return 'O2';
  if (gas.oxygenPercent == 21) return 'Air';
  return 'EAN ${gas.oxygenPercent}';
}
