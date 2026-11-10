import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/data/local_data_wiper.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../_helpers/powersync_test_helper.dart';

void main() {
  test('wipe() empties Drift and PowerSync tables and blocks fixtures',
      () async {
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
    // PowerSync `dives` and `gas_analyses`.
    await ps.execute(
      'INSERT INTO dives (id, owner_id, dc_serial) VALUES (?, ?, ?)',
      ['d1', 'u1', 1],
    );
    await ps.execute(
      'INSERT INTO gas_analyses (id, owner_id, o2_percent) VALUES (?, ?, ?)',
      ['g1', 'u1', 21.0],
    );

    Future<int> count(Future<dynamic> Function() q) async =>
        (await q() as List).length;
    expect(await count(() => db.customSelect('SELECT id FROM dives').get()),
        1);
    expect(await count(() => ps.getAll('SELECT id FROM dives')), 1);
    expect(await count(() => ps.getAll('SELECT id FROM gas_analyses')), 1);

    var blockedCalls = 0;
    await LocalDataWiper(
      db: db,
      powerSyncDb: ps,
      markFixturesBlocked: () async => blockedCalls++,
    ).wipe();

    expect(await count(() => db.customSelect('SELECT id FROM dives').get()),
        0);
    expect(await count(() => ps.getAll('SELECT id FROM dives')), 0);
    expect(await count(() => ps.getAll('SELECT id FROM gas_analyses')), 0);
    expect(blockedCalls, 1);
  });
}
