/// Stamps `owner_id` on rows that lack one after a user signs in for
/// the first time.
///
/// Phase 2.1: counts null-owner rows across every sync-eligible Drift
/// table and logs the total. Actual writing is wired up in Phase 2.2
/// once PowerSync is live — until then we just want observable numbers
/// to verify the backfill against.
library;

import 'package:flutter/foundation.dart';

import '../../data/db/database.dart';

/// Tables that carry an `owner_id` column today. Keep this list in sync
/// with `tables.dart`; missing entries silently skip the table.
const _syncEligibleTables = [
  'dive_annotations',
  'dive_computers',
  'oxygen_cells',
  'scrubber_sessions',
  'cylinders',
  'pressure_mappings',
  'dive_cylinders',
];

class OwnerIdBackfiller {
  final AppDatabase db;

  OwnerIdBackfiller(this.db);

  /// Returns the number of rows across all sync-eligible tables that
  /// would receive `owner_id = userId`. Logs a per-table breakdown via
  /// [debugPrint]. Phase 2.1 does not write — Phase 2.2 will.
  Future<int> backfillIfNeeded(String userId) async {
    var total = 0;
    for (final table in _syncEligibleTables) {
      final n = await _countNullOwners(table);
      if (n > 0) {
        debugPrint('OwnerIdBackfiller: $table has $n null-owner rows');
      }
      total += n;
    }
    debugPrint(
        'OwnerIdBackfiller: would stamp $total rows with owner_id=$userId');
    return total;
  }

  Future<int> _countNullOwners(String table) async {
    final row = await db
        .customSelect('SELECT COUNT(*) AS c FROM $table WHERE owner_id IS NULL')
        .getSingle();
    return row.read<int>('c');
  }
}
