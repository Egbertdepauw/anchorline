import 'package:flutter/foundation.dart';
import 'package:powersync/powersync.dart';

import '../dev/fixture_seeder.dart' as fixtures;
import '../sync/cloud/powersync_schema.dart';
import 'db/database.dart';

/// Wipes this device's local databases (Drift + PowerSync) and blocks
/// fixture re-seeding. Settings → Reset local data and Reset everything use
/// [wipe]; account deletion uses [wipeDeletedAccount]. Cloud and R2 cleanup
/// are NOT part of this; callers do those first, when they want them.
class LocalDataWiper {
  LocalDataWiper({
    required AppDatabase db,
    required PowerSyncDatabase powerSyncDb,
    Future<void> Function()? markFixturesBlocked,
  })  : _db = db,
        _psDb = powerSyncDb,
        _markFixturesBlocked =
            markFixturesBlocked ?? fixtures.markFixturesBlocked;

  final AppDatabase _db;
  final PowerSyncDatabase _psDb;
  final Future<void> Function() _markFixturesBlocked;

  /// The two Settings resets. They keep `dive_raw_blobs`: the raw dive
  /// computer bytes live only on the device that downloaded them, and a dive
  /// that comes back (by sync, a new download or a Subsurface import) has the
  /// same id, so its blob is there again for a re-parse.
  Future<void> wipe() => _wipe(everyDriftTable: false);

  /// Account deletion: as [wipe], but every Drift table is emptied, the raw
  /// blobs among them. Nothing of the account stays on the device.
  Future<void> wipeDeletedAccount() => _wipe(everyDriftTable: true);

  Future<void> _wipe({required bool everyDriftTable}) async {
    if (everyDriftTable) {
      await _clearEveryDriftTable();
    } else {
      await _clearDriftForReset();
    }
    await _clearPowerSync();
    // Stop fixture re-seeding from re-populating the empty DB on next
    // launch. Reinstalling the app clears this flag.
    await _markFixturesBlocked();
  }

  /// Every table the Drift database declares, so a table added later is
  /// covered too. Reversed, because the list declares parents before their
  /// children.
  Future<void> _clearEveryDriftTable() => _db.transaction(() async {
        for (final table in _db.allTables.toList().reversed) {
          await _db.delete(table).go();
        }
      });

  Future<void> _clearDriftForReset() async {
    // Drift: clear all imported-dive related rows. Equipment / annotation
    // tables in Drift are no longer used (PowerSync owns them), but
    // we still wipe them to keep the local file fully fresh.
    await _db.transaction(() async {
      await _db.customStatement('DELETE FROM dive_samples');
      await _db.customStatement('DELETE FROM dives');
      await _db.customStatement('DELETE FROM import_states');
      await _db.customStatement('DELETE FROM dive_annotations');
      await _db.customStatement('DELETE FROM dive_computers');
      await _db.customStatement('DELETE FROM oxygen_cells');
      await _db.customStatement('DELETE FROM scrubber_sessions');
      await _db.customStatement('DELETE FROM cylinders');
      await _db.customStatement('DELETE FROM pressure_mappings');
      await _db.customStatement('DELETE FROM dive_cylinders');
    });
  }

  Future<void> _clearPowerSync() async {
    // PowerSync: disconnect + clear local SQLite. Re-sync on next start.
    //
    // `disconnectAndClear()` is supposed to remove every `ps_data__*`
    // row but has been observed leaving rows behind (2026-05-10
    // incident: 13 dives survived a Reset Everything). We follow it
    // with an explicit DELETE of every PowerSync-managed local table
    // as a fallback, so a fresh bootstrap-import sees an empty DB and
    // re-parses everything with the current mapper instead of
    // dedup-skipping stale rows. Wrapping in try/catch because the
    // table list isn't part of any contract — if PowerSync renames
    // its local tables in a future SDK rev, the explicit DELETE
    // becomes a no-op rather than blocking the reset.
    await _psDb.disconnectAndClear();
    try {
      final psTables = [
        for (final t in appSchema.tables) 'ps_data__${t.name}',
        'ps_crud',
        'ps_oplog',
        'ps_buckets',
      ];
      for (final t in psTables) {
        await _psDb.execute('DELETE FROM $t');
      }
    } catch (e) {
      debugPrint('Belt-and-braces PowerSync wipe partial: $e');
    }
  }
}
