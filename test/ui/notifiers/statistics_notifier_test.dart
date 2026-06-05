import 'package:ccrlogger/analysis/stats/stats_result.dart';
import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/data/db/dive_derived_stats_dao.dart';
import 'package:ccrlogger/data/models/sample_set.dart';
import 'package:ccrlogger/ui/notifiers/statistics_notifier.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:typed_data';

/// Minimal fake of the data seam the notifier calls.
class _FakeDives implements StatsDiveSource {
  final List<StatsDiveInput> dives;
  final Map<String, SampleSet> samples;
  int sampleLoads = 0;
  _FakeDives(this.dives, this.samples);
  @override
  Future<List<StatsDiveInput>> loadDiveInputs() async => dives;
  @override
  Future<SampleSet?> loadSamples(String id) async {
    sampleLoads++;
    return samples[id];
  }
  @override
  Future<Map<String, String?>> loadSiteNames(List<String> ids) async => const {};
  @override
  int parserVersionFor(String id) => 1;
}

SampleSet _samples({required double temp, required double stop}) {
  Float32List f(double v) => Float32List.fromList([v, v, v]);
  return SampleSet(
    diveId: 'x', sampleCount: 3, sampleIntervalMs: 10000,
    depthMeters: f(20), temperatureCelsius: f(temp), ppo2Bar: f(1),
    cellMv0: f(50), cellMv1: f(50), cellMv2: f(50), setpointBar: f(1.3),
    cns: f(0), decoStopDepthMeters: f(stop),
    decoTimeSeconds: Int32List.fromList([0, 0, 0]),
    ttsSeconds: Int32List.fromList([0, 0, 0]),
    gasMixIndex: Uint8List.fromList([0, 0, 0]),
    statusFlags: Uint8List.fromList([0, 0, 0]),
  );
}

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  test('load computes derived stats, caches them, and aggregates', () async {
    final source = _FakeDives(
      [
        const StatsDiveInput(
            id: 'a', startTime: 1737363600, durationSeconds: 3600,
            maxDepthMm: 52000, diveMode: 0),
      ],
      {'a': _samples(temp: 3.6, stop: 6.0)}, // in-deco (stop>0) → time-in-deco
    );
    final n = StatisticsNotifier(
        source: source, cacheDao: DiveDerivedStatsDao(db));
    await n.load();

    expect(n.loading, isFalse);
    expect(n.result!.totalDives, 1);
    expect(n.result!.coldest!.value, closeTo(3.6, 1e-3));
    expect(n.result!.longestDeco!.value, 30); // 3 samples × 10 s = 30 s
    expect(source.sampleLoads, 1);
  });

  test('second load reads cache instead of re-decoding samples', () async {
    final source = _FakeDives(
      [
        const StatsDiveInput(
            id: 'a', startTime: 1737363600, durationSeconds: 3600,
            maxDepthMm: 52000, diveMode: 0),
      ],
      {'a': _samples(temp: 3.6, stop: 0.0)},
    );
    final cacheDao = DiveDerivedStatsDao(db);
    await StatisticsNotifier(source: source, cacheDao: cacheDao).load();
    expect(source.sampleLoads, 1);
    await StatisticsNotifier(source: source, cacheDao: cacheDao).load();
    expect(source.sampleLoads, 1); // same parser version → cache hit, no re-decode
  });

  test('resultForScope filters by year and month', () async {
    // 2025-01-20 UTC
    const dive2025Jan = StatsDiveInput(
        id: 'jan2025', startTime: 1737363600, durationSeconds: 3600,
        maxDepthMm: 40000, diveMode: 0);
    // 2024-06-15 UTC
    const dive2024Jun = StatsDiveInput(
        id: 'jun2024', startTime: 1718445600, durationSeconds: 1800,
        maxDepthMm: 30000, diveMode: 0);

    final source = _FakeDives(
      [dive2025Jan, dive2024Jun],
      {
        'jan2025': _samples(temp: 4.0, stop: 0.0),
        'jun2024': _samples(temp: 20.0, stop: 0.0),
      },
    );
    final n = StatisticsNotifier(
        source: source, cacheDao: DiveDerivedStatsDao(db));
    await n.load();

    expect(n.resultForScope(const StatsScope.total()).totalDives, 2);
    expect(n.resultForScope(const StatsScope.year(2025)).totalDives, 1);
    expect(n.resultForScope(const StatsScope.month(2025, 1)).totalDives, 1);
    expect(n.resultForScope(const StatsScope.month(2025, 2)).totalDives, 0);
  });
}
