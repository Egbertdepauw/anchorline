import 'package:flutter/material.dart';

import '../../analysis/stats/stats_result.dart';
import '../../data/db/dive_annotations_dao.dart';
import '../../data/db/dive_dao.dart';
import '../../data/db/dive_derived_stats_dao.dart';
import '../components/stat_tile.dart';
import '../notifiers/statistics_notifier.dart';
import '../theme/tokens.dart';
import '../util/format.dart';
import '../widgets/stats_mode_breakdown.dart';
import '../widgets/stats_period_list.dart';
import '../widgets/stats_year_chart.dart';

class StatisticsScreen extends StatefulWidget {
  final DiveDao diveDao;
  final DiveAnnotationsDao annotationsDao;
  final DiveDerivedStatsDao derivedStatsDao;
  const StatisticsScreen({
    super.key,
    required this.diveDao,
    required this.annotationsDao,
    required this.derivedStatsDao,
  });

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  late final StatisticsNotifier _notifier;
  bool _byMonth = false;

  @override
  void initState() {
    super.initState();
    _notifier = StatisticsNotifier.fromDaos(
      diveDao: widget.diveDao,
      annotationsDao: widget.annotationsDao,
      cacheDao: widget.derivedStatsDao,
    );
    _notifier.addListener(_onChanged);
    _notifier.load();
  }

  @override
  void dispose() {
    _notifier.removeListener(_onChanged);
    _notifier.dispose();
    super.dispose();
  }

  void _onChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final r = _notifier.result;
    return Scaffold(
      appBar: AppBar(title: const Text('Statistics')),
      body: _notifier.loading && r == null
          ? const Center(child: CircularProgressIndicator())
          : (r == null || r.isEmpty)
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('No dives yet — import some to see your stats',
                        textAlign: TextAlign.center),
                  ),
                )
              : _content(context, r),
    );
  }

  Widget _content(BuildContext context, StatsResult r) {
    final scheme = Theme.of(context).colorScheme;
    Widget section(String label, Widget child) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label.toUpperCase(),
                  style: AppTypography.label
                      .copyWith(color: scheme.outlineVariant)),
              const SizedBox(height: 10),
              child,
            ],
          ),
        );

    String tempStr(num v) => (v as double).toStringAsFixed(1);
    String hint(RecordStat s) {
      final site = s.siteName;
      final date = s.startTime == null ? '' : formatMonthYear(s.startTime!);
      return [if (site != null && site.isNotEmpty) site, date]
          .where((e) => e.isNotEmpty)
          .join(' · ');
    }

    final records = <Widget>[
      StatTile(label: 'Total dives', value: '${r.totalDives}'),
      StatTile(label: 'Total time', value: formatDuration(r.totalSeconds)),
      if (r.deepest != null)
        StatTile(
            label: 'Deepest', unit: 'm',
            value: ((r.deepest!.value as int) / 1000).toStringAsFixed(1),
            hint: hint(r.deepest!)),
      if (r.longestDeco != null)
        StatTile(
            label: 'Longest deco', unit: 'min',
            value: '${((r.longestDeco!.value as int) / 60).round()}',
            hint: hint(r.longestDeco!)),
      if (r.coldest != null)
        StatTile(
            label: 'Coldest', unit: '°C',
            value: tempStr(r.coldest!.value), hint: hint(r.coldest!)),
      if (r.warmest != null)
        StatTile(
            label: 'Warmest', unit: '°C',
            value: tempStr(r.warmest!.value), hint: hint(r.warmest!)),
    ];

    return ListView(
      children: [
        section(
          'Records',
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 2.4,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            children: [
              for (final t in records)
                Container(
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                      color:
                          scheme.surfaceContainerHighest.withValues(alpha: .35),
                      borderRadius: BorderRadius.circular(14)),
                  child: Align(alignment: Alignment.centerLeft, child: t),
                ),
            ],
          ),
        ),
        if (r.modeTotals.isNotEmpty)
          section('By dive mode', StatsModeBreakdown(r.modeTotals)),
        if (r.years.length >= 2)
          section('Dives per year', StatsYearChart(r.years)),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
          child: Row(
            children: [
              Text('BREAKDOWN',
                  style: AppTypography.label
                      .copyWith(color: scheme.outlineVariant)),
              const Spacer(),
              SegmentedButton<bool>(
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: const [
                  ButtonSegment(value: false, label: Text('By year')),
                  ButtonSegment(value: true, label: Text('By month')),
                ],
                selected: {_byMonth},
                onSelectionChanged: (s) => setState(() => _byMonth = s.first),
              ),
            ],
          ),
        ),
        StatsPeriodList(r.years, byMonth: _byMonth),
        const SizedBox(height: 24),
      ],
    );
  }
}
