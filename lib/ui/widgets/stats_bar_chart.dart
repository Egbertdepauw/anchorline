import 'package:flutter/material.dart';

import '../../analysis/stats/stats_result.dart';
import '../theme/tokens.dart';

/// Horizontally-scrollable bar chart of dive counts per period (years or
/// months). Fixed-width bars keep labels legible; the row scrolls when there
/// are many periods. Expects [periods] newest-first; renders oldest→newest.
class StatsBarChart extends StatelessWidget {
  final List<PeriodStat> periods;
  const StatsBarChart(this.periods, {super.key});

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  String _label(PeriodStat p) => p.month == null
      ? "'${(p.year % 100).toString().padLeft(2, '0')}"
      : _months[p.month! - 1];

  @override
  Widget build(BuildContext context) {
    if (periods.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final ordered = periods.reversed.toList(); // oldest → newest
    final maxCount =
        ordered.map((p) => p.diveCount).fold<int>(1, (a, b) => b > a ? b : a);
    const barWidth = 46.0;
    return Container(
      height: 104,
      decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: .35),
          borderRadius: BorderRadius.circular(14)),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding:
            const EdgeInsets.fromLTRB(Spacing.sm, Spacing.sm, Spacing.sm, 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final p in ordered)
              SizedBox(
                width: barWidth,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text('${p.diveCount}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.caption
                            .copyWith(color: scheme.outlineVariant)),
                    const SizedBox(height: 3),
                    Expanded(
                      child: FractionallySizedBox(
                        heightFactor: (p.diveCount / maxCount).clamp(0.04, 1.0),
                        widthFactor: 0.62,
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
                    Text(_label(p),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.caption
                            .copyWith(color: scheme.outlineVariant)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
