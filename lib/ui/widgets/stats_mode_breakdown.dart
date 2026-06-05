import 'package:flutter/material.dart';

import '../../analysis/stats/stats_result.dart';
import '../theme/tokens.dart';
import '../util/dive_mode_color.dart';
import '../util/format.dart';

class StatsModeBreakdown extends StatelessWidget {
  final List<ModeTotal> totals;
  const StatsModeBreakdown(this.totals, {super.key});

  @override
  Widget build(BuildContext context) {
    if (totals.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final maxCount = totals.first.count; // sorted desc
    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: .35),
          borderRadius: BorderRadius.circular(14)),
      child: Column(
        children: [
          for (final m in totals)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(children: [
                SizedBox(
                    width: 110,
                    child: Text(m.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.body
                            .copyWith(color: scheme.onSurface))),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: LinearProgressIndicator(
                      value: maxCount == 0 ? 0 : m.count / maxCount,
                      minHeight: 8,
                      backgroundColor: scheme.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation(
                          diveModeColor(m.representativeModeValue)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text('${m.count} · ${formatDuration(m.totalSeconds)}',
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.caption
                          .copyWith(color: scheme.outlineVariant)),
                ),
              ]),
            ),
        ],
      ),
    );
  }
}
