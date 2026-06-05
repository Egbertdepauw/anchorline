import 'package:flutter/material.dart';

import '../../analysis/stats/stats_result.dart';
import '../theme/tokens.dart';
import '../util/format.dart';

/// Renders the year (expandable→months) / month breakdown. [byMonth] flattens
/// to a reverse-chronological month list; otherwise shows expandable years.
class StatsPeriodList extends StatelessWidget {
  final List<PeriodStat> years; // newest first, each with months
  final bool byMonth;
  const StatsPeriodList(this.years, {required this.byMonth, super.key});

  String _periodLabel(PeriodStat p) {
    if (p.month == null) return '${p.year}';
    const names = [
      'Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'
    ];
    return '${names[p.month! - 1]} ${p.year}';
  }

  String _summary(PeriodStat p) {
    final temp = p.minWaterTempC == null
        ? ''
        : ' · ${p.minWaterTempC!.toStringAsFixed(1)}°C';
    return '${p.diveCount} dives · ${formatDuration(p.totalSeconds)} · '
        '${formatDepth(p.maxDepthMm)}$temp';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (years.isEmpty) return const SizedBox.shrink();

    if (byMonth) {
      final months = [for (final y in years) ...y.months];
      return Column(
        children: [for (final m in months) _row(context, scheme, m, indent: false)],
      );
    }
    return Column(
      children: [
        for (final y in years)
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: 14),
              childrenPadding: EdgeInsets.zero,
              title: Text(_periodLabel(y),
                  style: AppTypography.title.copyWith(color: scheme.onSurface)),
              subtitle: Text(_summary(y),
                  style: AppTypography.caption
                      .copyWith(color: scheme.outlineVariant)),
              children: [
                for (final m in y.months) _row(context, scheme, m, indent: true)
              ],
            ),
          ),
      ],
    );
  }

  Widget _row(BuildContext context, ColorScheme scheme, PeriodStat p,
      {required bool indent}) {
    return Padding(
      padding: EdgeInsets.fromLTRB(indent ? 28 : 14, 8, 14, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(_periodLabel(p),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.body.copyWith(color: scheme.onSurface)),
          Flexible(
            child: Text(_summary(p),
                textAlign: TextAlign.right,
                style: AppTypography.caption
                    .copyWith(color: scheme.outlineVariant)),
          ),
        ],
      ),
    );
  }
}
