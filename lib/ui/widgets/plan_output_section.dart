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

    // Convert DecoStep list → AscentStop list for StopLadderTable.
    // volumeLitresConsumed is unknown at this layer (no SAC applied yet),
    // so it is zeroed; the table only uses it for the VOL column which is
    // not meaningful for a pure deco schedule display.
    final ascentStops = r.diveAscent
        .map((s) => AscentStop(
              depthStartMeters: s.depthStartMeters,
              depthEndMeters: s.depthEndMeters,
              duration: s.duration,
              gas: s.gas,
              volumeLitresConsumed: 0,
            ))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('OUTPUT — DIVE PLAN', style: AppTypography.label),
        if (ascentStops.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: Spacing.sm),
            child: Text('NDL — no decompression required.',
                style: AppTypography.caption),
          )
        else
          StopLadderTable(stops: ascentStops, scheme: scheme),
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
