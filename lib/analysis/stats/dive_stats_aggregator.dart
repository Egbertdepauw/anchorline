import 'package:subsurface_core/shearwater/parser/constants.dart' show DiveMode;
import 'stats_result.dart';

/// Pure aggregation of dives + cached derived stats into a [StatsResult].
class DiveStatsAggregator {
  const DiveStatsAggregator._();

  static StatsResult aggregate(
    List<StatsDiveInput> dives,
    Map<String, DerivedStats> derived,
    Map<String, String?> sites,
  ) {
    if (dives.isEmpty) {
      return const StatsResult(totalDives: 0, totalSeconds: 0);
    }

    DerivedStats dOf(String id) => derived[id] ?? const DerivedStats();

    var totalSeconds = 0;
    StatsDiveInput? deepest, longestDive, longestDeco, coldest, warmest;

    // mode buckets keyed by label
    final modeAcc = <String, ({int rep, int count, int secs})>{};
    // period buckets keyed by year
    final yearAcc = <int, _PeriodAcc>{};

    for (final d in dives) {
      totalSeconds += d.durationSeconds;
      final ds = dOf(d.id);

      if (deepest == null || d.maxDepthMm > deepest.maxDepthMm) deepest = d;
      if (longestDive == null ||
          d.durationSeconds > longestDive.durationSeconds) {
        longestDive = d;
      }
      if (ds.timeInDecoSeconds > 0 &&
          (longestDeco == null ||
              ds.timeInDecoSeconds > dOf(longestDeco.id).timeInDecoSeconds)) {
        longestDeco = d;
      }
      if (ds.minWaterTempC != null &&
          (coldest == null ||
              ds.minWaterTempC! < dOf(coldest.id).minWaterTempC!)) {
        coldest = d;
      }
      if (ds.maxWaterTempC != null &&
          (warmest == null ||
              ds.maxWaterTempC! > dOf(warmest.id).maxWaterTempC!)) {
        warmest = d;
      }

      final (label, rep) = _modeGroup(d.diveMode);
      final m = modeAcc[label];
      modeAcc[label] = (
        rep: rep,
        count: (m?.count ?? 0) + 1,
        secs: (m?.secs ?? 0) + d.durationSeconds,
      );

      final dt = DateTime.fromMillisecondsSinceEpoch(d.startTime * 1000, isUtc: true);
      (yearAcc[dt.year] ??= _PeriodAcc()).add(dt.month, d, ds);
    }

    RecordStat? rec(StatsDiveInput? d, num Function(StatsDiveInput) val) =>
        d == null ? null : RecordStat(
            value: val(d), diveId: d.id, startTime: d.startTime, siteName: sites[d.id]);

    final modeTotals = modeAcc.entries
        .map((e) => ModeTotal(
            label: e.key,
            representativeModeValue: e.value.rep,
            count: e.value.count,
            totalSeconds: e.value.secs))
        .toList()
      ..sort((a, b) => b.count.compareTo(a.count));

    final years = (yearAcc.keys.toList()..sort((a, b) => b.compareTo(a)))
        .map((y) => yearAcc[y]!.toPeriod(y))
        .toList();

    return StatsResult(
      totalDives: dives.length,
      totalSeconds: totalSeconds,
      deepest: rec(deepest, (d) => d.maxDepthMm),
      longestDive: rec(longestDive, (d) => d.durationSeconds),
      longestDeco: rec(longestDeco, (d) => dOf(d.id).timeInDecoSeconds),
      coldest: rec(coldest, (d) => dOf(d.id).minWaterTempC!),
      warmest: rec(warmest, (d) => dOf(d.id).maxWaterTempC!),
      modeTotals: modeTotals,
      years: years,
    );
  }

  /// Mirrors `dive_mode_color.dart` grouping so colours stay consistent.
  static (String, int) _modeGroup(int modeValue) {
    switch (DiveMode.fromValue(modeValue)) {
      case DiveMode.cc:
      case DiveMode.cc2:
        return ('Closed circuit', DiveMode.cc.value);
      case DiveMode.ocTec:
      case DiveMode.ocRec:
      case DiveMode.avelo:
        return ('Open circuit', DiveMode.ocTec.value);
      case DiveMode.sc:
        return ('Semi-closed', DiveMode.sc.value);
      case DiveMode.gauge:
      case DiveMode.ppo2:
        return ('Gauge', DiveMode.gauge.value);
      case DiveMode.freedive:
        return ('Freedive', DiveMode.freedive.value);
    }
  }
}

class _PeriodAcc {
  int count = 0, secs = 0, maxDepthMm = 0;
  double? minTemp;
  final Map<int, _PeriodAcc> _months = {};
  bool _isMonth = false;

  void add(int month, StatsDiveInput d, DerivedStats ds) {
    _tally(d, ds);
    (_months[month] ??= _PeriodAcc().._isMonth = true)._tally(d, ds);
  }

  void _tally(StatsDiveInput d, DerivedStats ds) {
    count++;
    secs += d.durationSeconds;
    if (d.maxDepthMm > maxDepthMm) maxDepthMm = d.maxDepthMm;
    if (ds.minWaterTempC != null &&
        (minTemp == null || ds.minWaterTempC! < minTemp!)) {
      minTemp = ds.minWaterTempC;
    }
  }

  PeriodStat toPeriod(int year, {int? month}) => PeriodStat(
        year: year,
        month: month,
        diveCount: count,
        totalSeconds: secs,
        maxDepthMm: maxDepthMm,
        minWaterTempC: minTemp,
        months: _isMonth
            ? const []
            : (_months.keys.toList()..sort((a, b) => b.compareTo(a)))
                .map((mo) => _months[mo]!.toPeriod(year, month: mo))
                .toList(),
      );
}
