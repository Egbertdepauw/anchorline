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
