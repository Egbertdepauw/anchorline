/// PlanOutputSection — renders the dive-plan output (stop ladder + summary
/// chips) or an empty-state hint when no plan has been computed yet.
library;

import 'package:flutter/material.dart';

import '../../analysis/bailout/ascent_simulator.dart' show AscentStop;
import '../../analysis/planner/plan_result.dart';
import '../theme/tokens.dart';
import 'stop_ladder_table.dart' show StopLadderTable;

class PlanOutputSection extends StatelessWidget {
  const PlanOutputSection({
    super.key,
    required this.result,
    required this.scheme,
  });

  final PlanResult? result;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final r = result;
    if (r == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: Spacing.lg),
        child: Text('Add gases and segments to see the dive plan.',
            style: AppTypography.caption),
      );
    }

    // Combine the simulator's descent + bottom + transit legs with the
    // deco ascent. The simulator emits AscentStops directly; the deco
    // schedule is mapped 1:1 (DecoStep ↔ AscentStop have the same shape).
    // volumeLitresConsumed is unknown at this layer (no SAC applied),
    // so it is zeroed — the VOL column isn't shown on dive-plan output.
    final ascentFromDeco = r.diveAscent.map((s) => AscentStop(
          depthStartMeters: s.depthStartMeters,
          depthEndMeters: s.depthEndMeters,
          duration: s.duration,
          gas: s.gas,
          volumeLitresConsumed: 0,
        ));
    final allSteps = <AscentStop>[...r.profile, ...ascentFromDeco];
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
          children: [
            Text('CNS ${r.cnsPercent.toStringAsFixed(1)} %',
                style: AppTypography.caption),
            Text('OTU ${r.otuTotal.toStringAsFixed(0)}',
                style: AppTypography.caption),
            Text('ρ max ${r.maxDensityGramsPerLitre.toStringAsFixed(1)} g/L',
                style: AppTypography.caption),
            Text('TTS ${r.totalRuntime.inMinutes} min',
                style: AppTypography.caption),
          ],
        ),
      ],
    );
  }
}
