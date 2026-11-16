import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/data/local_data_wiper.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:powersync/powersync.dart';

import '../_helpers/powersync_test_helper.dart';

/// Rows in the Drift table [table].
Future<int> _driftRows(AppDatabase db, String table) async =>
    (await db.customSelect('SELECT 1 FROM $table').get()).length;

/// Rows in the PowerSync table [table].
Future<int> _psRows(PowerSyncDatabase ps, String table) async =>
    (await ps.getAll('SELECT 1 FROM $table')).length;

/// A dive with its raw blob in Drift, the device-local tables a download and
/// a sync fill, and a dive and a gas analysis in PowerSync.
Future<(AppDatabase, PowerSyncDatabase)> _seeded() async {
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  final ps = await openPowerSyncForTest();

  // Drift `dives` (NOT NULL columns only).
  await db.customStatement(
    'INSERT INTO dives (id, dc_serial, dc_dive_number, start_time, '
    'end_time, duration_seconds, max_depth_mm, dive_mode, deco_model, '
    'atmospheric_pressure_mbar, water_density, log_version, dc_model, '
    'sample_interval_ms, gas_mixes_json, raw_blob, parser_version, '
    'imported_at) VALUES (?, 1, 1, 1000, 2000, 1000, 10000, 0, 0, 1013, '
    "1020, 1, 0, 10000, '[]', x'00', 1, 1000)",
    ['d1'],
  );
  await db.customStatement(
      "INSERT INTO dive_raw_blobs (dive_id, raw_blob) VALUES ('d1', x'0102')");
  await db.customStatement(
      "INSERT INTO import_states (dc_serial) VALUES ('1234')");
  // Device-local re-parse bookkeeping.
  await db.customStatement(
    'INSERT INTO dive_import_marks (dive_id, raw_blob_missing, '
    "reparse_failed_version) VALUES ('d1', 1, 2)",
  );
  await db.customStatement('INSERT INTO dive_derived_stats '
      "(dive_id, parser_version) VALUES ('d1', 1)");
  await db.customStatement('INSERT INTO sync_quarantine (op_client_id, '
      'op_type, target_table, row_id, op_data, error, quarantined_at) '
      "VALUES (1, 'put', 'dives', 'd1', '{\"owner_id\":\"u1\"}', 'rejected', 1)");
  // PowerSync `dives` and `gas_analyses`.
  await ps.execute(
    'INSERT INTO dives (id, owner_id, dc_serial) VALUES (?, ?, ?)',
    ['d1', 'u1', 1],
  );
  await ps.execute(
    'INSERT INTO gas_analyses (id, owner_id, o2_percent) VALUES (?, ?, ?)',
    ['g1', 'u1', 21.0],
  );

  expect(await _driftRows(db, 'dives'), 1);
  expect(await _driftRows(db, 'dive_raw_blobs'), 1);
  expect(await _psRows(ps, 'dives'), 1);
  expect(await _psRows(ps, 'gas_analyses'), 1);
  return (db, ps);
}

void main() {
  test('wipe() empties Drift and PowerSync tables and blocks fixtures',
      () async {
    final (db, ps) = await _seeded();

    var blockedCalls = 0;
    await LocalDataWiper(
      db: db,
      powerSyncDb: ps,
      markFixturesBlocked: () async => blockedCalls++,
    ).wipe();

    expect(await _driftRows(db, 'dives'), 0);
    expect(await _driftRows(db, 'import_states'), 0);
    expect(await _psRows(ps, 'dives'), 0);
    expect(await _psRows(ps, 'gas_analyses'), 0);
    expect(blockedCalls, 1);
  });

  test('wipe() keeps the raw blobs: they exist only on this device',
      () async {
    final (db, ps) = await _seeded();

    await LocalDataWiper(
      db: db,
      powerSyncDb: ps,
      markFixturesBlocked: () async {},
    ).wipe();

    final blobs = await db.select(db.diveRawBlobs).get();
    expect(blobs.single.diveId, 'd1');
    expect(blobs.single.rawBlob, [1, 2]);
  });

  test('wipe() keeps the import marks but clears the re-parse failures',
      () async {
    final (db, ps) = await _seeded();

    await LocalDataWiper(
      db: db,
      powerSyncDb: ps,
      markFixturesBlocked: () async {},
    ).wipe();

    // The raw blobs stay, so a blob that failed to store is still missing;
    // a dive that failed to re-parse gets another try after the reset.
    final mark = await db
        .customSelect('SELECT raw_blob_missing, reparse_failed_version '
            'FROM dive_import_marks')
        .getSingle();
    expect(mark.read<bool>('raw_blob_missing'), isTrue);
    expect(mark.data['reparse_failed_version'], isNull);
  });

  test('wipeDeletedAccount() empties every Drift table, raw blobs included',
      () async {
    final (db, ps) = await _seeded();

    var blockedCalls = 0;
    await LocalDataWiper(
      db: db,
      powerSyncDb: ps,
      markFixturesBlocked: () async => blockedCalls++,
    ).wipeDeletedAccount();

    for (final table in db.allTables) {
      expect(await _driftRows(db, table.actualTableName), 0,
          reason: table.actualTableName);
    }
    expect(await _psRows(ps, 'dives'), 0);
    expect(await _psRows(ps, 'gas_analyses'), 0);
    expect(blockedCalls, 1);
  });
}
