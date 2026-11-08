import 'package:flutter/foundation.dart';
import 'package:powersync/powersync.dart';

import '../dev/fixture_seeder.dart' as fixtures;
import '../sync/cloud/powersync_schema.dart';
import 'db/database.dart';

/// Wipes this device's local databases (Drift + PowerSync) and blocks
/// fixture re-seeding. Shared by Settings → Reset local data and account
/// deletion. Cloud and R2 cleanup are NOT part of this; callers do those
/// first, when they want them.
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

  Future<void> wipe() async {
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
    // Stop fixture re-seeding from re-populating the empty DB on next
    // launch. Reinstalling the app clears this flag.
    await _markFixturesBlocked();
  }
}
