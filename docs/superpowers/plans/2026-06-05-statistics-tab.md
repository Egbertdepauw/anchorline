# Statistics Tab Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A read-only Statistics screen (all-time records, dive-mode totals, dives-per-year chart, year/month breakdown) reached from the Dives app bar, backed by a local parser-version-tagged derived-stats cache.

**Architecture:** Most stats come from the cheap `dives` rows. Per-dive water-temp min/max and time-in-deco are computed from sample blobs and cached in a new local Drift table (`dive_derived_stats`), repopulated lazily when stale. A **pure** `DiveStatsAggregator` turns `(dives, derivedMap, sitesMap)` into a `StatsResult`; a `StatisticsNotifier` orchestrates load→cache→aggregate; `StatisticsScreen` renders it.

**Tech Stack:** Flutter/Dart, Drift (local cache table + codegen), PowerSync (dives/samples via existing `DiveDao`), `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-06-05-statistics-tab-design.md`

## Branch & conventions

- Work on a feature branch: `git switch -c feat/statistics-tab` (not `main`).
- `git add` only the exact files each task lists — NEVER `git add -A`/`.`/`-a` (repo has long-lived untracked files).
- Do NOT run `dart format` (churns unrelated lines); match surrounding style by hand.
- Flutter/build_runner commands are slow — use a generous Bash timeout (~600000 ms).
- Commit messages end with the co-author trailer shown in each commit step.

## File structure

**Create:**
- `lib/analysis/stats/stats_result.dart` — pure data: `StatsDiveInput`, `DerivedStats`, `RecordStat`, `ModeTotal`, `PeriodStat`, `StatsResult`.
- `lib/analysis/stats/dive_stats_aggregator.dart` — pure `aggregate(...) → StatsResult`.
- `lib/data/db/dive_derived_stats_dao.dart` — Drift CRUD for the cache table.
- `lib/ui/notifiers/statistics_notifier.dart` — orchestration.
- `lib/ui/screens/statistics_screen.dart` — the screen.
- `lib/ui/widgets/stats_mode_breakdown.dart`, `stats_year_chart.dart`, `stats_period_list.dart` — sections.
- Tests: `test/analysis/stats/dive_stats_aggregator_test.dart`, `test/data/db/dive_derived_stats_dao_test.dart`, `test/ui/notifiers/statistics_notifier_test.dart`.

**Modify:**
- `lib/data/db/tables.dart` — add `DiveDerivedStats` table.
- `lib/data/db/database.dart` — register table, bump `schemaVersion` 18→19, add migration.
- `lib/ui/app_shell.dart` — construct the cache DAO; add a stats `IconButton` (Dives-tab actions) that pushes `StatisticsScreen`.

---

## Task 1: Derived-stats cache table + migration

**Files:**
- Modify: `lib/data/db/tables.dart`
- Modify: `lib/data/db/database.dart`

- [ ] **Step 1: Add the table** — append to `lib/data/db/tables.dart`:

```dart
/// Local, device-only, re-derivable cache of per-dive stats that require
/// decoding the sample blob (water temperature extremes, time-in-deco).
/// Keyed by dive id; `parserVersion` mirrors the dive's parser version so a
/// re-parse invalidates the row. Not synced — recomputed per device.
class DiveDerivedStats extends Table {
  TextColumn get diveId => text()();
  IntColumn get parserVersion => integer()();
  RealColumn get minWaterTempC => real().nullable()();
  RealColumn get maxWaterTempC => real().nullable()();
  IntColumn get timeInDecoSeconds => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {diveId};
}
```

- [ ] **Step 2: Register the table + migration** in `lib/data/db/database.dart`.

Add `DiveDerivedStats` to the `@DriftDatabase(tables: [...])` list (after `SyncQuarantine`):

```dart
    SyncQuarantine,
    DiveDerivedStats,
```

Bump the schema version:

```dart
  @override
  int get schemaVersion => 19;
```

Add a migration step at the end of the `onUpgrade` chain (after the `if (from < 18)` block):

```dart
      if (from < 19) {
        await m.createTable(diveDerivedStats);
      }
```

- [ ] **Step 3: Run codegen**

Run: `dart run build_runner build --delete-conflicting-outputs` (generous timeout).
Expected: completes; `lib/data/db/database.g.dart` now contains `DiveDerivedStat` (row), `DiveDerivedStatsCompanion`, and a `diveDerivedStats` getter on `AppDatabase`.

- [ ] **Step 4: Verify analyze**

Run: `flutter analyze lib/data/db/`
Expected: `No issues found!`

- [ ] **Step 5: Commit (include spec + plan so they ride along)**

```bash
git add lib/data/db/tables.dart lib/data/db/database.dart lib/data/db/database.g.dart \
        docs/superpowers/specs/2026-06-05-statistics-tab-design.md \
        docs/superpowers/plans/2026-06-05-statistics-tab.md
git commit -m "feat(stats): add dive_derived_stats cache table (schema v19)" \
           -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Models + cache DAO

**Files:**
- Create: `lib/analysis/stats/stats_result.dart`
- Create: `lib/data/db/dive_derived_stats_dao.dart`
- Test: `test/data/db/dive_derived_stats_dao_test.dart`

- [ ] **Step 1: Create the models** — create `lib/analysis/stats/stats_result.dart` (both the DAO and, later, the aggregator import from this file):

```dart
/// Pure data types for the Statistics screen. No Flutter/Drift imports so the
/// aggregator and its tests stay dependency-free.

/// Minimal per-dive input the aggregator needs (mapped from the Drift Dive row
/// by the notifier, keeping this layer Drift-free).
class StatsDiveInput {
  final String id;
  final int startTime; // epoch seconds (DC wall clock)
  final int durationSeconds;
  final int maxDepthMm;
  final int diveMode; // DiveMode.value
  const StatsDiveInput({
    required this.id,
    required this.startTime,
    required this.durationSeconds,
    required this.maxDepthMm,
    required this.diveMode,
  });
}

/// Per-dive values decoded from the sample blob (cached).
class DerivedStats {
  final double? minWaterTempC;
  final double? maxWaterTempC;
  final int timeInDecoSeconds;
  const DerivedStats({
    this.minWaterTempC,
    this.maxWaterTempC,
    this.timeInDecoSeconds = 0,
  });
}

/// A single headline record (raw value + source for the hint; UI formats it).
class RecordStat {
  final num value; // depthMm (int) | seconds (int) | tempC (double)
  final String? diveId;
  final int? startTime;
  final String? siteName;
  const RecordStat({
    required this.value,
    this.diveId,
    this.startTime,
    this.siteName,
  });
}

/// Total for one dive-mode bucket.
class ModeTotal {
  final String label; // "Closed circuit"
  final int representativeModeValue; // for diveModeColor(...)
  final int count;
  final int totalSeconds;
  const ModeTotal({
    required this.label,
    required this.representativeModeValue,
    required this.count,
    required this.totalSeconds,
  });
}

/// Stats for one period (a year, or a month within a year).
class PeriodStat {
  final int year;
  final int? month; // null for a year row; 1-12 for a month row
  final int diveCount;
  final int totalSeconds;
  final int maxDepthMm;
  final double? minWaterTempC;
  final List<PeriodStat> months; // child months for a year row; else const []
  const PeriodStat({
    required this.year,
    this.month,
    required this.diveCount,
    required this.totalSeconds,
    required this.maxDepthMm,
    this.minWaterTempC,
    this.months = const [],
  });
}

/// Everything the screen renders.
class StatsResult {
  final int totalDives;
  final int totalSeconds;
  final RecordStat? deepest;
  final RecordStat? longestDeco;
  final RecordStat? coldest;
  final RecordStat? warmest;
  final List<ModeTotal> modeTotals; // present buckets, count desc
  final List<PeriodStat> years; // newest first, each with months (newest first)
  const StatsResult({
    required this.totalDives,
    required this.totalSeconds,
    this.deepest,
    this.longestDeco,
    this.coldest,
    this.warmest,
    this.modeTotals = const [],
    this.years = const [],
  });

  bool get isEmpty => totalDives == 0;
}
```

- [ ] **Step 2: Write the failing DAO test** — create `test/data/db/dive_derived_stats_dao_test.dart`:

```dart
import 'package:ccrlogger/analysis/stats/stats_result.dart';
import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/data/db/dive_derived_stats_dao.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late DiveDerivedStatsDao dao;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    dao = DiveDerivedStatsDao(db);
  });
  tearDown(() async => db.close());

  test('upsertAll then getByIds round-trips values', () async {
    await dao.upsertAll([
      (diveId: 'a', parserVersion: 1,
       stats: const DerivedStats(minWaterTempC: 4.0, maxWaterTempC: 12.0, timeInDecoSeconds: 600)),
      (diveId: 'b', parserVersion: 1,
       stats: const DerivedStats(minWaterTempC: null, maxWaterTempC: null, timeInDecoSeconds: 0)),
    ]);
    final got = await dao.getByIds(['a', 'b', 'missing']);
    expect(got.length, 2);
    expect(got['a']!.parserVersion, 1);
    expect(got['a']!.stats.minWaterTempC, 4.0);
    expect(got['a']!.stats.timeInDecoSeconds, 600);
    expect(got['b']!.stats.minWaterTempC, isNull);
    expect(got.containsKey('missing'), isFalse);
  });

  test('upsertAll updates an existing row (parser-version bump)', () async {
    await dao.upsertAll([
      (diveId: 'a', parserVersion: 1,
       stats: const DerivedStats(minWaterTempC: 4.0, timeInDecoSeconds: 600)),
    ]);
    await dao.upsertAll([
      (diveId: 'a', parserVersion: 2,
       stats: const DerivedStats(minWaterTempC: 5.5, timeInDecoSeconds: 720)),
    ]);
    final got = await dao.getByIds(['a']);
    expect(got['a']!.parserVersion, 2);
    expect(got['a']!.stats.minWaterTempC, 5.5);
    expect(got['a']!.stats.timeInDecoSeconds, 720);
  });

  test('getByIds returns empty for empty input', () async {
    expect(await dao.getByIds([]), isEmpty);
  });
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `flutter test test/data/db/dive_derived_stats_dao_test.dart`
Expected: FAIL — `dive_derived_stats_dao.dart` not found / `DiveDerivedStatsDao` undefined.

- [ ] **Step 4: Implement the DAO** — create `lib/data/db/dive_derived_stats_dao.dart`:

```dart
import 'package:drift/drift.dart';

import '../../analysis/stats/stats_result.dart';
import 'database.dart';

/// CRUD for the local `dive_derived_stats` cache. Stores per-dive values that
/// require decoding the sample blob, keyed by dive id and tagged with the
/// dive's parser version for invalidation.
class DiveDerivedStatsDao {
  final AppDatabase _db;
  DiveDerivedStatsDao(this._db);

  /// Cached rows for [ids], keyed by dive id. Missing dives are absent.
  Future<Map<String, ({int parserVersion, DerivedStats stats})>> getByIds(
      List<String> ids) async {
    if (ids.isEmpty) return {};
    final rows = await (_db.select(_db.diveDerivedStats)
          ..where((t) => t.diveId.isIn(ids)))
        .get();
    return {
      for (final r in rows)
        r.diveId: (
          parserVersion: r.parserVersion,
          stats: DerivedStats(
            minWaterTempC: r.minWaterTempC,
            maxWaterTempC: r.maxWaterTempC,
            timeInDecoSeconds: r.timeInDecoSeconds,
          ),
        ),
    };
  }

  /// Insert-or-replace the given entries (by dive id).
  Future<void> upsertAll(
      List<({String diveId, int parserVersion, DerivedStats stats})>
          entries) async {
    if (entries.isEmpty) return;
    await _db.batch((b) {
      b.insertAllOnConflictUpdate(_db.diveDerivedStats, [
        for (final e in entries)
          DiveDerivedStatsCompanion.insert(
            diveId: e.diveId,
            parserVersion: e.parserVersion,
            minWaterTempC: Value(e.stats.minWaterTempC),
            maxWaterTempC: Value(e.stats.maxWaterTempC),
            timeInDecoSeconds: Value(e.stats.timeInDecoSeconds),
          ),
      ]);
    });
  }
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `flutter test test/data/db/dive_derived_stats_dao_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 6: Commit**

```bash
git add lib/data/db/dive_derived_stats_dao.dart \
        test/data/db/dive_derived_stats_dao_test.dart \
        lib/analysis/stats/stats_result.dart
git commit -m "feat(stats): dive_derived_stats cache DAO" \
           -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Pure aggregator

**Files:**
- Create: `lib/analysis/stats/dive_stats_aggregator.dart`
- Test: `test/analysis/stats/dive_stats_aggregator_test.dart`

- [ ] **Step 1: Models already exist** — `lib/analysis/stats/stats_result.dart` (with `StatsDiveInput`, `DerivedStats`, `RecordStat`, `ModeTotal`, `PeriodStat`, `StatsResult`) was created in Task 2. This task only adds the aggregator, which imports those types. No file change in this step.

- [ ] **Step 2: Write the failing aggregator tests** — create `test/analysis/stats/dive_stats_aggregator_test.dart`:

```dart
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
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `flutter test test/analysis/stats/dive_stats_aggregator_test.dart`
Expected: FAIL — `dive_stats_aggregator.dart` not found.

- [ ] **Step 4: Implement the aggregator** — create `lib/analysis/stats/dive_stats_aggregator.dart`:

```dart
import '../../shearwater/parser/constants.dart' show DiveMode;
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
    StatsDiveInput? deepest, longestDeco, coldest, warmest;

    // mode buckets keyed by label
    final modeAcc = <String, ({int rep, int count, int secs})>{};
    // period buckets keyed by year, then month
    final yearAcc = <int, _PeriodAcc>{};

    for (final d in dives) {
      totalSeconds += d.durationSeconds;
      final ds = dOf(d.id);

      if (deepest == null || d.maxDepthMm > deepest.maxDepthMm) deepest = d;
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

  void add(int month, StatsDiveInput d, DerivedStats ds) {
    _tally(d, ds);
    (_months[month] ??= _PeriodAcc().._isMonth = true)._tally(d, ds);
  }

  bool _isMonth = false;
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
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `flutter test test/analysis/stats/dive_stats_aggregator_test.dart`
Expected: PASS (6 tests).

- [ ] **Step 6: Commit**

```bash
git add lib/analysis/stats/dive_stats_aggregator.dart \
        test/analysis/stats/dive_stats_aggregator_test.dart
git commit -m "feat(stats): pure dive-stats aggregator" \
           -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Statistics notifier

**Files:**
- Create: `lib/ui/notifiers/statistics_notifier.dart`
- Test: `test/ui/notifiers/statistics_notifier_test.dart`

The notifier depends on `DiveDao`, `DiveAnnotationsDao`, `DiveDerivedStatsDao`. To test it without real DBs, it takes those via narrow function-typed callbacks is overkill; instead we depend on the concrete DAOs but inject a tiny seam: the notifier calls `diveDao.getAllDives()`, `diveDao.getSamples(id)`, `annotationsDao.getAnnotationsForDives(ids)`, `cacheDao.getByIds(ids)`, `cacheDao.upsertAll(...)`. The test uses fakes implementing those method shapes via subclassing is impractical (concrete classes). **Test approach:** test the notifier against an in-memory `AppDatabase` for the cache DAO + lightweight fakes for the two PowerSync DAOs using `implements`.

- [ ] **Step 1: Write the failing notifier test** — create `test/ui/notifiers/statistics_notifier_test.dart`:

```dart
import 'package:ccrlogger/analysis/stats/stats_result.dart';
import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/data/db/dive_derived_stats_dao.dart';
import 'package:ccrlogger/data/models/sample_set.dart';
import 'package:ccrlogger/ui/notifiers/statistics_notifier.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:typed_data';

/// Minimal fakes for the two methods the notifier calls on each PowerSync DAO.
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
    expect(n.result!.longestDeco!.value, 30000); // 3 samples × 10s
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
    // fresh notifier, same cache + same parser version → no re-decode
    await StatisticsNotifier(source: source, cacheDao: cacheDao).load();
    expect(source.sampleLoads, 1);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/ui/notifiers/statistics_notifier_test.dart`
Expected: FAIL — `statistics_notifier.dart` / `StatsDiveSource` not found.

- [ ] **Step 3: Implement the notifier** — create `lib/ui/notifiers/statistics_notifier.dart`:

```dart
import 'package:flutter/foundation.dart';

import '../../analysis/stats/dive_stats_aggregator.dart';
import '../../analysis/stats/stats_result.dart';
import '../../data/db/dive_annotations_dao.dart';
import '../../data/db/dive_dao.dart';
import '../../data/db/dive_derived_stats_dao.dart';
import '../../data/models/sample_set.dart';
import '../../data/sample_codec/dive_stats.dart';

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

    _result = DiveStatsAggregator.aggregate(dives, derived, sites);
    _loading = false;
    notifyListeners();
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
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/ui/notifiers/statistics_notifier_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Verify analyze**

Run: `flutter analyze lib/ui/notifiers/statistics_notifier.dart`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/ui/notifiers/statistics_notifier.dart \
        test/ui/notifiers/statistics_notifier_test.dart
git commit -m "feat(stats): statistics notifier with lazy derived-stats cache" \
           -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: Section widgets

**Files:**
- Create: `lib/ui/widgets/stats_mode_breakdown.dart`, `lib/ui/widgets/stats_year_chart.dart`, `lib/ui/widgets/stats_period_list.dart`

These are presentational; verification is `flutter analyze` + a smoke widget test in Task 6. Build them with theme tokens (`Theme.of(context).colorScheme`, `AppTypography`, `Spacing`) and reuse `diveModeColor` + `format.dart`.

- [ ] **Step 1: Mode breakdown** — create `lib/ui/widgets/stats_mode_breakdown.dart`:

```dart
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
                Text('${m.count} · ${formatDuration(m.totalSeconds)}',
                    style: AppTypography.caption
                        .copyWith(color: scheme.outlineVariant)),
              ]),
            ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Year chart** — create `lib/ui/widgets/stats_year_chart.dart`:

```dart
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
                    FractionallySizedBox(
                      heightFactor: (y.diveCount / maxCount).clamp(0.04, 1.0),
                      child: Container(
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(4)),
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
```

(Note: the bar `Container` needs a bounded height — it sits inside the 96px box; `FractionallySizedBox` inside the `Column`'s `end` alignment expands within the available column height. If layout proves finicky, wrap the bar+labels区 differently — see Task 6 smoke test which will catch overflow.)

- [ ] **Step 3: Period list** — create `lib/ui/widgets/stats_period_list.dart`:

```dart
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
```

- [ ] **Step 4: Verify analyze**

Run: `flutter analyze lib/ui/widgets/stats_mode_breakdown.dart lib/ui/widgets/stats_year_chart.dart lib/ui/widgets/stats_period_list.dart`
Expected: `No issues found!` (if `surfaceContainerHighest` is unavailable in the project's Flutter, substitute `scheme.surface` — confirm during implementation and adjust.)

- [ ] **Step 5: Commit**

```bash
git add lib/ui/widgets/stats_mode_breakdown.dart lib/ui/widgets/stats_year_chart.dart \
        lib/ui/widgets/stats_period_list.dart
git commit -m "feat(stats): statistics section widgets" \
           -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: Statistics screen

**Files:**
- Create: `lib/ui/screens/statistics_screen.dart`
- Test: `test/ui/screens/statistics_screen_test.dart`

- [ ] **Step 1: Implement the screen** — create `lib/ui/screens/statistics_screen.dart`:

```dart
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

    String tempStr(num v) => '${(v as double).toStringAsFixed(1)}';
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
```

- [ ] **Step 2: Write a smoke widget test** — create `test/ui/screens/statistics_screen_test.dart`. This renders the screen's `_content` indirectly is hard (private). Instead, smoke-test that the sections render given a built `StatsResult` by extracting a small public render helper is overkill; **smoke-test the section widgets together** in a `MaterialApp` to catch layout/overflow:

```dart
import 'package:ccrlogger/analysis/stats/stats_result.dart';
import 'package:ccrlogger/ui/widgets/stats_mode_breakdown.dart';
import 'package:ccrlogger/ui/widgets/stats_period_list.dart';
import 'package:ccrlogger/ui/widgets/stats_year_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final years = [
    const PeriodStat(
        year: 2026, diveCount: 12, totalSeconds: 36000, maxDepthMm: 53000,
        minWaterTempC: 4.0, months: [
      PeriodStat(
          year: 2026, month: 5, diveCount: 12, totalSeconds: 36000,
          maxDepthMm: 53000, minWaterTempC: 4.0),
    ]),
    const PeriodStat(
        year: 2025, diveCount: 30, totalSeconds: 90000, maxDepthMm: 71000,
        minWaterTempC: 3.6, months: []),
  ];

  testWidgets('section widgets render without overflow', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 390,
          child: ListView(children: [
            StatsModeBreakdown(const [
              ModeTotal(label: 'Closed circuit', representativeModeValue: 0, count: 38, totalSeconds: 120000),
              ModeTotal(label: 'Open circuit', representativeModeValue: 1, count: 4, totalSeconds: 9000),
            ]),
            StatsYearChart(years),
            StatsPeriodList(years, byMonth: false),
          ]),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Closed circuit'), findsOneWidget);
    expect(find.text('2026'), findsWidgets);
  });
}
```

- [ ] **Step 3: Run the smoke test**

Run: `flutter test test/ui/screens/statistics_screen_test.dart`
Expected: PASS (1 test). If it fails on `surfaceContainerHighest` or a layout overflow, fix the widget (e.g. swap to `scheme.surface`, or constrain the chart bar) and re-run.

- [ ] **Step 4: Verify analyze**

Run: `flutter analyze lib/ui/screens/statistics_screen.dart`
Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add lib/ui/screens/statistics_screen.dart test/ui/screens/statistics_screen_test.dart
git commit -m "feat(stats): statistics screen" \
           -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: Wire into the app

**Files:**
- Modify: `lib/ui/app_shell.dart`

- [ ] **Step 1: Construct the cache DAO** in `_AppShellState.initState()`, next to the other DAO instantiations (after `_diveMergeDao = ...`):

```dart
    _diveDerivedStatsDao = DiveDerivedStatsDao(widget.db);
```

Add the field alongside the other `late final` DAO fields:

```dart
  late final DiveDerivedStatsDao _diveDerivedStatsDao;
```

Add the import near the other DAO imports:

```dart
import '../data/db/dive_derived_stats_dao.dart';
import 'screens/statistics_screen.dart';
```

- [ ] **Step 2: Add the app-bar button** — in the `actions:` list that's gated on `_currentIndex == 0` (where the Buddies / Sites-map buttons are), add:

```dart
          if (_currentIndex == 0)
            IconButton(
              tooltip: 'Statistics',
              icon: const Icon(Icons.bar_chart),
              onPressed: () {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => StatisticsScreen(
                    diveDao: _diveDao,
                    annotationsDao: _diveAnnotationsDao,
                    derivedStatsDao: _diveDerivedStatsDao,
                  ),
                ));
              },
            ),
```

- [ ] **Step 3: Verify analyze + full suite**

Run: `flutter analyze`
Expected: `No issues found!`
Run: `flutter test` (generous timeout)
Expected: PASS (all suites, including the new stats tests).

- [ ] **Step 4: Manual verification**

Run the app (`flutter run`), open the Dives tab, tap the new stats icon in the app bar. Confirm: records cards populate, by-mode bars, dives-per-year chart, and the By year/By month breakdown (year expands to months). Open it a second time and confirm it's instant (cache hit). On an empty logbook, confirm the empty-state text.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/app_shell.dart
git commit -m "feat(stats): add Statistics entry to the Dives app bar" \
           -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Done criteria

- `flutter analyze` clean, `flutter test` green (aggregator, cache DAO, notifier, and section smoke tests included).
- Statistics opens from the Dives app bar; records / by-mode / dives-per-year / year-month breakdown all render; second open is instant (cache hit); empty logbook shows the placeholder.
- Open a PR (`feat/statistics-tab` → main); CI runs analyze + test; squash-merge per repo workflow.

## Notes for the implementer

- **`surfaceContainerHighest`**: if the project's Flutter/Material version doesn't expose it on `ColorScheme`, substitute `Theme.of(context).colorScheme.surface` (slightly lighter panel) — confirm in Task 5 and keep all section widgets consistent.
- **`SegmentedButton`**: available in Material 3. If the app isn't M3 or it looks off, fall back to a two-`ChoiceChip` row. Confirm during Task 6.
- **Year chart layout**: the `FractionallySizedBox` bar must have a bounded parent height (the 96px container). The Task 6 smoke test asserts no overflow — if it trips, give each bar a fixed-height `Stack`/`Align` instead.
- The aggregator + models + DAO + notifier are all unit-tested and Drift/Flutter-light; the UI is gated by analyze + the smoke test + manual.
