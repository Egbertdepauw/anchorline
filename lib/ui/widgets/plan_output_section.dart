/// PlanOutputSection — renders the dive-plan output (stop ladder + summary
/// chips) or an empty-state hint when no plan has been computed yet.
library;

import 'package:flutter/material.dart';

import '../../analysis/bailout/ascent_simulator.dart' show AscentStop;
import '../../analysis/planner/plan_result.dart';
import '../../data/models/dive_plan.dart' show DivePlanMode;
import '../theme/tokens.dart';
import 'stop_ladder_table.dart' show StopLadderTable;

class PlanOutputSection extends StatelessWidget {
  const PlanOutputSection({
    super.key,
    required this.result,
    required this.scheme,
    this.mode = DivePlanMode.cc,
    this.emptyMessage,
  });

  final PlanResult? result;
  final ColorScheme scheme;

  /// Drives which consumption chip is shown — CC plans surface the
  /// metabolic O2 burn (loop math), OC plans surface total breathing-
  /// gas litres (cylinder-capacity sanity).
  final DivePlanMode mode;

  /// Replaces the default empty-state hint when [result] is null for a
  /// reason other than missing input (e.g. a segment that is too deep).
  final String? emptyMessage;

  @override
  Widget build(BuildContext context) {
    final r = result;
    if (r == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: Spacing.lg),
        child: Text(
            emptyMessage ?? 'Add gases and segments to see the dive plan.',
            style: AppTypography.caption),
      );
    }

    // Combine the simulator's descent + bottom + transit legs with the
    // deco ascent. Both lists are AscentStops carrying setpointBar
    // (when CCR), so StopLadderTable renders the loop PPO2 instead of
    // OC gas-times-ambient.
    final allSteps = <AscentStop>[...r.profile, ...r.diveAscent];
    final hasDeco = r.diveAscent.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('OUTPUT — DIVE PLAN', style: AppTypography.label),
        if (allSteps.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: Spacing.sm),
            child: Text('Add gases and segments to see the dive plan.',
                style: AppTypography.caption),
          )
        else ...[
          StopLadderTable(stops: allSteps, scheme: scheme),
          if (!hasDeco)
            const Padding(
              padding: EdgeInsets.only(top: Spacing.xs),
              child: Text('NDL — no decompression required.',
                  style: AppTypography.caption),
            ),
        ],
        const SizedBox(height: Spacing.sm),
        Wrap(
          spacing: 16,
          runSpacing: 4,
          children: [
            Text('CNS ${r.cnsPercent.toStringAsFixed(1)} %',
                style: AppTypography.caption),
            Text('OTU ${r.otuTotal.toStringAsFixed(0)}',
                style: AppTypography.caption),
            Text('ρ max ${r.maxDensityGramsPerLitre.toStringAsFixed(1)} g/L',
                style: AppTypography.caption),
            Text('TTS ${r.totalRuntime.inMinutes} min',
                style: AppTypography.caption),
            // CC: metabolic O2 (loop is closed, no gas litres to report).
            // OC: per-gas breakdown so the diver sees which tank
            // carries the bulk of the consumption ("Tx18/45 3400 L ·
            // EAN50 980 L"). Falls back to a single "Gas N L" chip
            // when only one gas is in play.
            if (mode == DivePlanMode.cc)
              Text('O₂ ${r.oxygenConsumedLitres.round()} L',
                  style: AppTypography.caption)
            else if (r.gasConsumedByMix.isEmpty)
              Text('Gas ${r.gasConsumedLitres.round()} L',
                  style: AppTypography.caption)
            else
              for (final entry in r.gasConsumedByMix)
                Text(
                  '${StopLadderTable.mixLabel(entry.gas)} '
                  '${entry.litres.round()} L',
                  style: AppTypography.caption,
                ),
          ],
        ),
      ],
    );
  }
}
