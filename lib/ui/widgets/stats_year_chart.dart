import 'package:flutter/material.dart';

import '../../analysis/stats/stats_result.dart';
import '../theme/tokens.dart';

/// Simple dives-per-year bar chart. Expects [years] newest-first; renders
/// oldest→newest left→right.
class StatsYearChart extends StatelessWidget {
  final List<PeriodStat> years;
  const StatsYearChart(this.years, {super.key});

  @override
  Widget build(BuildContext context) {
    if (years.length < 2) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final ordered = years.reversed.toList();
    final maxCount =
        ordered.map((y) => y.diveCount).fold<int>(1, (a, b) => b > a ? b : a);
    return Container(
      height: 96,
      padding: const EdgeInsets.fromLTRB(Spacing.sm, Spacing.sm, Spacing.sm, 6),
      decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: .35),
          borderRadius: BorderRadius.circular(14)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final y in ordered)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text('${y.diveCount}',
                        style: AppTypography.caption
                            .copyWith(color: scheme.outlineVariant)),
                    const SizedBox(height: 3),
                    Expanded(
                      child: FractionallySizedBox(
                        heightFactor: (y.diveCount / maxCount).clamp(0.04, 1.0),
                        alignment: Alignment.bottomCenter,
                        child: Container(
                          decoration: BoxDecoration(
                            color: scheme.primary,
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(4)),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text("'${y.year % 100}",
                        style: AppTypography.caption
                            .copyWith(color: scheme.outlineVariant)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
