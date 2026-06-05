import 'package:flutter/foundation.dart';

import '../../analysis/stats/dive_stats_aggregator.dart';
import '../../analysis/stats/stats_result.dart';
import '../../data/db/dive_annotations_dao.dart';
import '../../data/db/dive_dao.dart';
import '../../data/db/dive_derived_stats_dao.dart';
import '../../data/models/sample_set.dart';
import '../../data/sample_codec/dive_stats.dart';

enum StatsScopeKind { total, year, month }

/// What slice of the logbook the Statistics screen is showing.
class StatsScope {
  final StatsScopeKind kind;
  final int year; // used for year/month
  final int month; // used for month (1-12)
  const StatsScope.total()
      : kind = StatsScopeKind.total, year = 0, month = 0;
  const StatsScope.year(this.year)
      : kind = StatsScopeKind.year, month = 0;
  const StatsScope.month(this.year, this.month)
      : kind = StatsScopeKind.month;
}

/// Narrow seam over the PowerSync-backed dive data, so the notifier is testable
/// with fakes. Production impl is [_DaoStatsDiveSource].
abstract class StatsDiveSource {
  Future<List<StatsDiveInput>> loadDiveInputs();
  Future<Map<String, String?>> loadSiteNames(List<String> ids);
  Future<SampleSet?> loadSamples(String id);
  int parserVersionFor(String id);
}

class StatisticsNotifier extends ChangeNotifier {
  final StatsDiveSource _source;
  final DiveDerivedStatsDao _cacheDao;

  StatisticsNotifier({
    required StatsDiveSource source,
    required DiveDerivedStatsDao cacheDao,
  })  : _source = source,
        _cacheDao = cacheDao;

  /// Production constructor wiring real DAOs.
  factory StatisticsNotifier.fromDaos({
    required DiveDao diveDao,
    required DiveAnnotationsDao annotationsDao,
    required DiveDerivedStatsDao cacheDao,
  }) =>
      StatisticsNotifier(
          source: _DaoStatsDiveSource(diveDao, annotationsDao),
          cacheDao: cacheDao);

  bool _loading = false;
  bool get loading => _loading;
  StatsResult? _result;
  StatsResult? get result => _result;

  List<StatsDiveInput> _dives = const [];
  Map<String, DerivedStats> _derived = const {};
  Map<String, String?> _sites = const {};

  Future<void> load() async {
    _loading = true;
    notifyListeners();

    final dives = await _source.loadDiveInputs();
    final ids = dives.map((d) => d.id).toList();
    final sites = await _source.loadSiteNames(ids);
    final cached = await _cacheDao.getByIds(ids);

    final derived = <String, DerivedStats>{};
    final toUpsert =
        <({String diveId, int parserVersion, DerivedStats stats})>[];
    for (final d in dives) {
      final pv = _source.parserVersionFor(d.id);
      final c = cached[d.id];
      if (c != null && c.parserVersion == pv) {
        derived[d.id] = c.stats;
      } else {
        final ds = await _compute(d.id);
        derived[d.id] = ds;
        toUpsert.add((diveId: d.id, parserVersion: pv, stats: ds));
      }
    }
    if (toUpsert.isNotEmpty) await _cacheDao.upsertAll(toUpsert);

    _dives = dives;
    _derived = derived;
    _sites = sites;
    _result = DiveStatsAggregator.aggregate(dives, derived, sites);
    _loading = false;
    notifyListeners();
  }

  /// Re-aggregate for a period scope. Total reuses the already-computed
  /// all-time result; year/month filter the retained dives and re-run the
  /// (pure, cheap) aggregator.
  StatsResult resultForScope(StatsScope scope) {
    if (scope.kind == StatsScopeKind.total) {
      return _result ?? const StatsResult(totalDives: 0, totalSeconds: 0);
    }
    final filtered = _dives.where((d) {
      final dt =
          DateTime.fromMillisecondsSinceEpoch(d.startTime * 1000, isUtc: true);
      if (dt.year != scope.year) return false;
      if (scope.kind == StatsScopeKind.month && dt.month != scope.month) {
        return false;
      }
      return true;
    }).toList();
    return DiveStatsAggregator.aggregate(filtered, _derived, _sites);
  }

  Future<DerivedStats> _compute(String diveId) async {
    final s = await _source.loadSamples(diveId);
    if (s == null) return const DerivedStats();
    final temp = minAvgMax(s.temperatureCelsius, s.sampleCount);
    final deco = totalTimeInDecoSeconds(
      decoStopDepthMeters: s.decoStopDepthMeters,
      sampleCount: s.sampleCount,
      sampleIntervalMs: s.sampleIntervalMs,
    );
    return DerivedStats(
      minWaterTempC: temp?.min,
      maxWaterTempC: temp?.max,
      timeInDecoSeconds: deco,
    );
  }
}

class _DaoStatsDiveSource implements StatsDiveSource {
  final DiveDao _diveDao;
  final DiveAnnotationsDao _annotationsDao;
  final Map<String, int> _parserVersions = {};
  _DaoStatsDiveSource(this._diveDao, this._annotationsDao);

  @override
  Future<List<StatsDiveInput>> loadDiveInputs() async {
    final dives = await _diveDao.getAllDives();
    _parserVersions
      ..clear()
      ..addEntries(dives.map((d) => MapEntry(d.id, d.parserVersion)));
    return dives
        .map((d) => StatsDiveInput(
              id: d.id,
              startTime: d.startTime,
              durationSeconds: d.durationSeconds,
              maxDepthMm: d.maxDepthMm,
              diveMode: d.diveMode,
            ))
        .toList();
  }

  @override
  Future<Map<String, String?>> loadSiteNames(List<String> ids) async {
    final ann = await _annotationsDao.getAnnotationsForDives(ids);
    return {for (final e in ann.entries) e.key: e.value.siteName};
  }

  @override
  Future<SampleSet?> loadSamples(String id) => _diveDao.getSamples(id);

  @override
  int parserVersionFor(String id) => _parserVersions[id] ?? 1;
}
