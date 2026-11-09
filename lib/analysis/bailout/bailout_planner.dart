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

import '../../analysis/gas_density.dart' show mixDensityAt1Atm;
import '../../data/models/dive.dart' show DiveGasMix;
import 'ascent_simulator.dart' show AscentPlan, simulateAscent;
import 'bailout_result.dart';
import 'mix_resolver.dart' show resolveBottomMix;
import 'standard_mixes.dart'
    show kDecoMixes, kO2, kTx2135, kTx3525, minimalDecoGasesForDepth;
import 'tank_recommender.dart' show TankSpec, recommend;
import '../gas_naming.dart';

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
/// [bailoutCapableDiluent] Whether the diluent is bailout-capable; picks the
///                       bottom-mix table and PPO2 limit for mix resolution.
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
  required bool bailoutCapableDiluent,
  required int gfLow,
  required int gfHigh,
  required int sacBottom,
  required int sacDeco,
  required int ascentRateFast,
  required int ascentRateSlow,
  required List<TankSpec> availableTanks,
  double? triggerDepthMeters,
}) {
  // The OC ascent starts from where the bailout was triggered (typically
  // the latest substantial-depth sample on a multi-level dive). Bottom
  // mix selection + deco-staging tier still go off true max depth so the
  // mix is breathable at the deepest point the diver actually visited.
  final triggerDepth = triggerDepthMeters ?? maxDepthMeters;
  // -------------------------------------------------------------------------
  // 1. Detect scenario
  // -------------------------------------------------------------------------
  final scenario = userBailoutTanks.isNotEmpty
      ? BailoutScenario.tanksDefined
      : BailoutScenario.standardGases;

  // -------------------------------------------------------------------------
  // 2. Build available-gas list
  // -------------------------------------------------------------------------
  List<DiveGasMix> gases;

  if (scenario == BailoutScenario.tanksDefined) {
    // Scenario A: sort user tanks so the bottom mix (lowest O2) comes first,
    // then deco gases in ascending MOD order (ascending O2 %). If the user
    // hasn't defined a tank that's safe at trigger depth, fall back to a
    // resolved standard bottom mix — the diver still needs something to
    // breathe at depth, and the planner shouldn't silently pick a deco gas.
    gases = _sortGasesForAscent(List<DiveGasMix>.from(userBailoutTanks));
    final ppo2Limit = bailoutCapableDiluent ? 1.4 : 1.6;
    if (gases.isEmpty || !_isSafeAtDepth(gases.first, maxDepthMeters, ppo2Limit)) {
      final fallbackBottom = resolveBottomMix(
        recordedDiluent: recordedDiluent,
        maxDepthMeters: maxDepthMeters,
        bailoutCapableDiluent: bailoutCapableDiluent,
      );
      gases = [fallbackBottom, ...gases];
    }
  } else {
    // Scenario B: resolve an OC bottom mix and prepend it to a
    // depth-appropriate deco gas list. The bottom mix is mandatory — the
    // diver is on OC bailout, so even if the CCR diluent would have been
    // breathable at depth, OC bailout still needs a gas that can be
    // inhaled at trigger depth.
    final bottomMix = resolveBottomMix(
      recordedDiluent: recordedDiluent,
      maxDepthMeters: maxDepthMeters,
      bailoutCapableDiluent: bailoutCapableDiluent,
    );

    // Depth-based staging applies to Scenario B regardless of the user's
    // Settings → bailout-capable diluent toggle. The toggle controls bottom-mix
    // selection + PPO2 limits during [resolveBottomMix]; the deco-gas
    // ladder is a planning convention (1/2/3 stages by depth) that holds
    // for any technical OC bailout.
    final decoGases = minimalDecoGasesForDepth(maxDepthMeters);
    gases = [bottomMix, ...decoGases];
  }

  // -------------------------------------------------------------------------
  // 3. Run ascent simulator (with volume-driven escalation in Scenario B)
  // -------------------------------------------------------------------------
  // Scenario B starts from the minimum ladder (see [minimalDecoGasesForDepth])
  // and escalates only when an actual gas volume overflows the largest
  // tank in the catalogue:
  //
  //   - bottom-mix overflow → insert TX 21/35 (deeper switch first), then
  //     TX 35/25 if even that isn't enough. The diver carries the fewest
  //     intermediate stages that keep bottom-mix inside one tank.
  //   - deco-gas overflow with no O₂ yet → add O₂ to shorten the EAN 50
  //     leg (covers the 22–65 m window where the minimum ladder is just
  //     [bottom, EAN50]).
  //
  // Bounded to one of each escalation step, so the loop is guaranteed to
  // terminate.
  AscentPlan plan;
  while (true) {
    plan = simulateAscent(
      triggerDepthMeters: triggerDepth,
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
    if (scenario != BailoutScenario.standardGases) break;
    final largestTankCapacityL = availableTanks.isEmpty
        ? 0.0
        : availableTanks
            .map((t) => t.waterCapacityL * t.ratedPressureBar)
            .reduce((a, b) => a > b ? a : b);

    // Find the first gas (if any) whose required volume overflows one tank.
    DiveGasMix? overflowGas;
    for (final entry in plan.volumeByGas.entries) {
      if (entry.value > largestTankCapacityL) {
        overflowGas = entry.key;
        break;
      }
    }
    if (overflowGas == null) break;

    // Identify the bottom mix as the lowest-O2 gas currently in the list.
    final bottomMix = gases
        .reduce((a, b) => a.oxygenPercent <= b.oxygenPercent ? a : b);

    var escalated = false;
    if (overflowGas == bottomMix) {
      // Insert intermediate trimixes deepest-first. Only useful if the
      // dive is actually deeper than the intermediate's switch depth.
      if (maxDepthMeters > 57 && !gases.contains(kTx2135)) {
        gases = [...gases, kTx2135];
        escalated = true;
      } else if (maxDepthMeters > 36 && !gases.contains(kTx3525)) {
        gases = [...gases, kTx3525];
        escalated = true;
      }
    }
    if (!escalated && !gases.contains(kO2)) {
      // Deco-gas overflow (or unhandled bottom-mix overflow at shallow
      // depths) — add O₂ if it isn't already on the list.
      gases = [...gases, kO2];
      escalated = true;
    }
    if (!escalated) break; // exhausted escalations, accept the overflow
  }

  // -------------------------------------------------------------------------
  // 3b. Trivial-gas pruning (Scenario B only)
  // -------------------------------------------------------------------------
  // The simulator picks the "best gas" at every depth, so on an NDL
  // bailout from say 25 m it switches to EAN 50 at the 21 m switch
  // and uses 30 L of it on the way to surface. That isn't a real
  // "stage to carry" — no one carries an AL40 for 30 L of gas. Drop
  // deco gases whose consumption is below the meaningful-stage
  // threshold and re-simulate so the table + perGas reflect the
  // actually-needed ladder.
  if (scenario == BailoutScenario.standardGases) {
    const minUsefulStageL = 200.0;
    final bottomMix = gases
        .reduce((a, b) => a.oxygenPercent <= b.oxygenPercent ? a : b);
    final trivial = plan.volumeByGas.entries
        .where((e) => e.key != bottomMix && e.value < minUsefulStageL)
        .map((e) => e.key)
        .toSet();
    if (trivial.isNotEmpty) {
      gases = gases.where((g) => !trivial.contains(g)).toList();
      plan = simulateAscent(
        triggerDepthMeters: triggerDepth,
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
    }
  }

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
  // Prepend a one-line summary of the bottom-mix's worst-case PPO2 and
  // gas density at TRUE max depth (not the trigger). The diver needs to
  // know the mix is breathable at the deepest moment they actually
  // visited, not just where the bailout would start.
  final bottomMix = gases.first;
  final ambientAtMax = 1.013 + maxDepthMeters / 10.0;
  final bottomPpo2 = (bottomMix.oxygenPercent / 100.0) * ambientAtMax;
  final bottomDensity = mixDensityAt1Atm(
        bottomMix.oxygenPercent / 100.0,
        bottomMix.heliumPercent / 100.0,
      ) *
      ambientAtMax;
  final bottomLabel = _gasLabel(bottomMix);
  final bottomLine = 'Bottom $bottomLabel @ ${maxDepthMeters.toStringAsFixed(0)} m'
      ' · PPO2 ${bottomPpo2.toStringAsFixed(2)}'
      ' · ρ ${bottomDensity.toStringAsFixed(1)} g/L';

  final details = [bottomLine, ..._buildVerdictDetails(perGas, scenario)];

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

/// True when [gas]'s PPO2 at [depthMeters] is ≤ [ppo2Limit] bar.
bool _isSafeAtDepth(DiveGasMix gas, double depthMeters, double ppo2Limit) {
  final ambient = 1.013 + depthMeters / 10.0;
  return (gas.oxygenPercent / 100.0) * ambient <= ppo2Limit;
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

/// Verdict for Scenario B (standard gases / catalogue recommendation).
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
        final qty = rec.count > 1 ? '${rec.count}× ' : '';
        lines.add(
          '$label ${reqL}L → $qty${rec.tank.name} @ ${rec.minFillPressureBar} bar',
        );
      } else {
        lines.add('$label ${reqL}L → no suitable tank in catalogue');
      }
    }
  }

  return lines;
}

/// Short human-readable label for a gas mix.
String _gasLabel(DiveGasMix gas) =>
    gasMixName(gas.oxygenPercent, gas.heliumPercent);
