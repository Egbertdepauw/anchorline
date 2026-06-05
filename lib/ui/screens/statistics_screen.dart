import 'package:flutter/material.dart';

import '../../analysis/stats/stats_result.dart';
import '../../data/db/dive_annotations_dao.dart';
import '../../data/db/dive_dao.dart';
import '../../data/db/dive_derived_stats_dao.dart';
import '../components/stat_tile.dart';
import '../notifiers/statistics_notifier.dart';
import '../theme/tokens.dart';
import '../util/format.dart';
import '../widgets/stats_bar_chart.dart';
import '../widgets/stats_mode_breakdown.dart';

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
  StatsScopeKind _kind = StatsScopeKind.year; // default: yearly, current year
  int _year = 0;
  int _month = 1;
  bool _defaultsSet = false;

  static const _monthAbbr = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

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

  void _onChanged() {
    final r = _notifier.result;
    if (!_defaultsSet && r != null && r.years.isNotEmpty) {
      // Default to the most-recent (≈ current) year + month.
      _year = r.years.first.year;
      _month = r.years.first.months.isNotEmpty
          ? r.years.first.months.first.month!
          : 1;
      _defaultsSet = true;
    }
    setState(() {});
  }

  StatsScope get _scope => switch (_kind) {
        StatsScopeKind.total => const StatsScope.total(),
        StatsScopeKind.year => StatsScope.year(_year),
        StatsScopeKind.month => StatsScope.month(_year, _month),
      };

  @override
  Widget build(BuildContext context) {
    final all = _notifier.result;
    return Scaffold(
      appBar: AppBar(title: const Text('Statistics')),
      body: _notifier.loading && all == null
          ? const Center(child: CircularProgressIndicator())
          : (all == null || all.isEmpty)
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('No dives yet — import some to see your stats',
                        textAlign: TextAlign.center),
                  ),
                )
              : _content(context, all, _notifier.resultForScope(_scope)),
    );
  }

  Widget _content(BuildContext context, StatsResult all, StatsResult r) {
    final scheme = Theme.of(context).colorScheme;

    Widget sectionLabel(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(t.toUpperCase(),
              style:
                  AppTypography.label.copyWith(color: scheme.outlineVariant)),
        );

    String tempStr(num v) => v.toDouble().toStringAsFixed(1);
    String hint(RecordStat s) {
      final site = s.siteName;
      final date = s.startTime == null ? '' : formatMonthYear(s.startTime!);
      return [if (site != null && site.isNotEmpty) site, date]
          .where((e) => e.isNotEmpty)
          .join(' · ');
    }

    final records = <Widget>[
      _card(scheme, StatTile(label: 'Total dives', value: '${r.totalDives}')),
      _card(scheme,
          StatTile(label: 'Total time', value: formatDuration(r.totalSeconds))),
      if (r.deepest != null)
        _card(
            scheme,
            StatTile(
                label: 'Deepest',
                unit: 'm',
                value: ((r.deepest!.value as int) / 1000).toStringAsFixed(1),
                hint: hint(r.deepest!))),
      if (r.longestDeco != null)
        _card(
            scheme,
            StatTile(
                label: 'Longest deco',
                unit: 'min',
                value: '${((r.longestDeco!.value as int) / 60).round()}',
                hint: hint(r.longestDeco!))),
      if (r.coldest != null)
        _card(
            scheme,
            StatTile(
                label: 'Coldest',
                unit: '°C',
                value: tempStr(r.coldest!.value),
                hint: hint(r.coldest!))),
      if (r.warmest != null)
        _card(
            scheme,
            StatTile(
                label: 'Warmest',
                unit: '°C',
                value: tempStr(r.warmest!.value),
                hint: hint(r.warmest!))),
    ];

    final List<Widget> chips;
    if (_kind == StatsScopeKind.year) {
      chips = [
        for (final y in all.years)
          _chip(scheme, '${y.year}', _year == y.year,
              () => setState(() => _year = y.year)),
      ];
    } else if (_kind == StatsScopeKind.month) {
      final months = [for (final y in all.years) ...y.months];
      chips = [
        for (final m in months)
          _chip(scheme, '${_monthAbbr[m.month! - 1]} ${m.year}',
              _year == m.year && _month == m.month, () {
            setState(() {
              _year = m.year;
              _month = m.month!;
            });
          }),
      ];
    } else {
      chips = const [];
    }

    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: SegmentedButton<StatsScopeKind>(
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: const [
              ButtonSegment(value: StatsScopeKind.total, label: Text('Total')),
              ButtonSegment(value: StatsScopeKind.year, label: Text('Yearly')),
              ButtonSegment(
                  value: StatsScopeKind.month, label: Text('Monthly')),
            ],
            selected: {_kind},
            onSelectionChanged: (s) => setState(() => _kind = s.first),
          ),
        ),
        if (chips.isNotEmpty)
          SizedBox(
            height: 46,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
              children: [
                for (final c in chips)
                  Padding(padding: const EdgeInsets.only(right: 8), child: c),
              ],
            ),
          ),
        sectionLabel('Records'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _recordsGrid(records),
        ),
        if (r.modeTotals.isNotEmpty) ...[
          sectionLabel('By dive mode'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: StatsModeBreakdown(r.modeTotals),
          ),
        ],
        ..._chartSection(context, r),
        const SizedBox(height: 24),
      ],
    );
  }

  List<Widget> _chartSection(BuildContext context, StatsResult r) {
    final scheme = Theme.of(context).colorScheme;
    Widget label(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(t.toUpperCase(),
              style:
                  AppTypography.label.copyWith(color: scheme.outlineVariant)),
        );
    Widget wrap(Widget c) =>
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: c);

    switch (_kind) {
      case StatsScopeKind.total:
        if (r.years.length < 2) return const [];
        return [label('Dives per year'), wrap(StatsBarChart(r.years))];
      case StatsScopeKind.year:
        final months = r.years.isNotEmpty ? r.years.first.months : <PeriodStat>[];
        if (months.isEmpty) return const [];
        return [label('Dives per month'), wrap(StatsBarChart(months))];
      case StatsScopeKind.month:
        return const [];
    }
  }

  Widget _card(ColorScheme scheme, Widget child) => Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: .35),
            borderRadius: BorderRadius.circular(14)),
        child: Align(alignment: Alignment.centerLeft, child: child),
      );

  /// Two-column records layout whose rows grow to fit their content (so a long
  /// hint can't overflow into the next section). `IntrinsicHeight` keeps the two
  /// cells in a row the same height.
  Widget _recordsGrid(List<Widget> tiles) {
    final rows = <Widget>[];
    for (var i = 0; i < tiles.length; i += 2) {
      final right = i + 1 < tiles.length ? tiles[i + 1] : null;
      rows.add(IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: tiles[i]),
            const SizedBox(width: 10),
            Expanded(child: right ?? const SizedBox.shrink()),
          ],
        ),
      ));
      if (i + 2 < tiles.length) rows.add(const SizedBox(height: 10));
    }
    return Column(children: rows);
  }

  Widget _chip(
      ColorScheme scheme, String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: selected
              ? scheme.primary
              : scheme.surfaceContainerHighest.withValues(alpha: .4),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: AppTypography.body.copyWith(
                color: selected ? scheme.onPrimary : scheme.onSurface,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400)),
      ),
    );
  }
}
