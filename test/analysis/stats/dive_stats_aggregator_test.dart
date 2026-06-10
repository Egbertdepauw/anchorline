import 'package:ccrlogger/analysis/stats/dive_stats_aggregator.dart';
import 'package:ccrlogger/analysis/stats/stats_result.dart';
import 'package:flutter_test/flutter_test.dart';

// 2024-06-15T10:00:00Z and 2025-01-20T09:00:00Z as epoch seconds.
const _t2024Jun = 1718445600;
const _t2025Jan = 1737363600;
const _t2025Feb = 1739872800; // 2025-02-18

StatsDiveInput _d(String id, int t, int dur, int depthMm, int mode) =>
    StatsDiveInput(
        id: id,
        startTime: t,
        durationSeconds: dur,
        maxDepthMm: depthMm,
        diveMode: mode);

void main() {
  test('empty input → empty result', () {
    final r = DiveStatsAggregator.aggregate(const [], const {}, const {});
    expect(r.isEmpty, isTrue);
    expect(r.totalDives, 0);
    expect(r.deepest, isNull);
    expect(r.years, isEmpty);
  });

  test('totals, deepest, and site hint', () {
    final dives = [
      _d('a', _t2024Jun, 3600, 40000, 0), // 40.0 m
      _d('b', _t2025Jan, 1800, 78400, 0), // 78.4 m  ← deepest
    ];
    final r = DiveStatsAggregator.aggregate(
      dives, const {}, {'b': 'Jadran'});
    expect(r.totalDives, 2);
    expect(r.totalSeconds, 5400);
    expect(r.deepest!.value, 78400);
    expect(r.deepest!.diveId, 'b');
    expect(r.deepest!.siteName, 'Jadran');
  });

  test('longest dive picks max duration; empty → null', () {
    final empty = DiveStatsAggregator.aggregate(const [], const {}, const {});
    expect(empty.longestDive, isNull);

    final dives = [
      _d('a', _t2024Jun, 3600, 40000, 0),
      _d('b', _t2025Jan, 5520, 30000, 0), // 1h 32min ← longest
    ];
    final r = DiveStatsAggregator.aggregate(dives, const {}, {'b': 'Jadran'});
    expect(r.longestDive!.value, 5520);
    expect(r.longestDive!.diveId, 'b');
    expect(r.longestDive!.startTime, _t2025Jan);
    expect(r.longestDive!.siteName, 'Jadran');
  });

  test('longest deco picks max time-in-deco; none → null', () {
    final dives = [_d('a', _t2024Jun, 3600, 40000, 0), _d('b', _t2025Jan, 1800, 30000, 0)];
    final none = DiveStatsAggregator.aggregate(dives, const {}, const {});
    expect(none.longestDeco, isNull); // all NDL (no derived rows → 0)

    final derived = {
      'a': const DerivedStats(timeInDecoSeconds: 600),
      'b': const DerivedStats(timeInDecoSeconds: 1500),
    };
    final r = DiveStatsAggregator.aggregate(dives, derived, const {});
    expect(r.longestDeco!.value, 1500);
    expect(r.longestDeco!.diveId, 'b');
  });

  test('coldest/warmest ignore dives without temp; null when none', () {
    final dives = [_d('a', _t2024Jun, 3600, 40000, 0), _d('b', _t2025Jan, 1800, 30000, 0)];
    final noTemp = DiveStatsAggregator.aggregate(dives, const {}, const {});
    expect(noTemp.coldest, isNull);
    expect(noTemp.warmest, isNull);

    final derived = {
      'a': const DerivedStats(minWaterTempC: 4.0, maxWaterTempC: 14.0),
      'b': const DerivedStats(minWaterTempC: 26.0, maxWaterTempC: 28.5),
    };
    final r = DiveStatsAggregator.aggregate(dives, derived, const {});
    expect(r.coldest!.value, 4.0);
    expect(r.coldest!.diveId, 'a');
    expect(r.warmest!.value, 28.5);
    expect(r.warmest!.diveId, 'b');
  });

  test('mode totals bucket CC variants together; sorted by count', () {
    final dives = [
      _d('a', _t2024Jun, 3600, 40000, 0), // cc
      _d('b', _t2025Jan, 1800, 30000, 5), // cc2 → same "Closed circuit" bucket
      _d('c', _t2025Feb, 1200, 20000, 1), // ocTec
    ];
    final r = DiveStatsAggregator.aggregate(dives, const {}, const {});
    expect(r.modeTotals.first.label, 'Closed circuit');
    expect(r.modeTotals.first.count, 2);
    expect(r.modeTotals.first.totalSeconds, 5400);
    expect(r.modeTotals.any((m) => m.label == 'Open circuit' && m.count == 1), isTrue);
  });

  test('year/month grouping with per-period deepest + coldest', () {
    final dives = [
      _d('a', _t2025Jan, 3600, 30000, 0),
      _d('b', _t2025Feb, 1800, 52000, 0), // deeper, Feb 2025
      _d('c', _t2024Jun, 1200, 20000, 0),
    ];
    final derived = {
      'a': const DerivedStats(minWaterTempC: 4.0),
      'b': const DerivedStats(minWaterTempC: 3.2),
      'c': const DerivedStats(minWaterTempC: 18.0),
    };
    final r = DiveStatsAggregator.aggregate(dives, derived, const {});
    // newest year first
    expect(r.years.first.year, 2025);
    expect(r.years.first.diveCount, 2);
    expect(r.years.first.totalSeconds, 5400);
    expect(r.years.first.maxDepthMm, 52000);
    expect(r.years.first.minWaterTempC, 3.2);
    // months newest first within 2025: Feb then Jan
    expect(r.years.first.months.map((m) => m.month).toList(), [2, 1]);
    expect(r.years.last.year, 2024);
  });
}
