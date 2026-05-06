import 'dart:typed_data';

import 'package:ccrlogger/data/db/database.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

/// Seed a minimal pre-v4 dives + dive_samples pair so cumulative
/// ALTERs from any earlier version land on something.
void _seedDivesV3(Database raw) {
  raw.execute('''
    CREATE TABLE dives (
      id TEXT NOT NULL PRIMARY KEY,
      dc_serial INTEGER NOT NULL,
      dc_dive_number INTEGER NOT NULL,
      start_time INTEGER NOT NULL,
      end_time INTEGER NOT NULL,
      utc_offset_minutes INTEGER,
      duration_seconds INTEGER NOT NULL,
      max_depth_mm INTEGER NOT NULL,
      dive_mode INTEGER NOT NULL,
      deco_model INTEGER NOT NULL,
      gf_low INTEGER,
      gf_high INTEGER,
      atmospheric_pressure_mbar INTEGER NOT NULL,
      water_density INTEGER NOT NULL,
      log_version INTEGER NOT NULL,
      dc_model INTEGER NOT NULL,
      dc_firmware INTEGER,
      sample_interval_ms INTEGER NOT NULL,
      gas_mixes_json TEXT NOT NULL,
      raw_blob BLOB NOT NULL,
      parser_version INTEGER NOT NULL,
      imported_at INTEGER NOT NULL
    );
  ''');
  raw.execute('''
    CREATE TABLE dive_samples (
      dive_id TEXT NOT NULL PRIMARY KEY REFERENCES dives(id),
      sample_count INTEGER NOT NULL,
      depth_blob BLOB NOT NULL,
      temperature_blob BLOB NOT NULL,
      ppo2_blob BLOB NOT NULL,
      cell_mv0_blob BLOB NOT NULL,
      cell_mv1_blob BLOB NOT NULL,
      cell_mv2_blob BLOB NOT NULL,
      setpoint_blob BLOB NOT NULL,
      cns_blob BLOB NOT NULL,
      deco_depth_blob BLOB NOT NULL,
      deco_time_blob BLOB NOT NULL,
      tts_blob BLOB NOT NULL,
      gas_mix_idx_blob BLOB NOT NULL,
      status_blob BLOB NOT NULL
    );
  ''');
}

void main() {
  test('schema v2: has cylinders, pressure_mappings, oxygen_cells.label', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    expect(db.schemaVersion, 7);

    // Inserting a row exercises the full schema.
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.into(db.cylinders).insert(CylindersCompanion.insert(
          id: 'c1',
          label: 'O2',
          role: 'oxygen',
          volumeLiters: 2.0,
          workingPressureBar: 200,
          createdAt: now,
          updatedAt: now,
        ));
    await db.into(db.oxygenCells).insert(OxygenCellsCompanion.insert(
          id: 'cell1',
          slot: 1,
          createdAt: now,
          updatedAt: now,
          label: const Value('Analytical R-22D #1234'),
        ));
    await db.into(db.pressureMappings).insert(PressureMappingsCompanion.insert(
          diveComputerId: 'dc1',
          channelIndex: 0,
          createdAt: now,
          updatedAt: now,
        ));

    expect((await db.select(db.cylinders).get()).length, 1);
    expect((await db.select(db.oxygenCells).get()).single.label, 'Analytical R-22D #1234');
    expect((await db.select(db.pressureMappings).get()).length, 1);
  });

  test('v1 → v2 onUpgrade is additive and preserves existing oxygen_cells row',
      () async {
    // Step 1: open a raw sqlite3 in-memory database and seed it as v1.
    final raw = sqlite3.openInMemory();
    addTearDown(raw.close);

    _seedDivesV3(raw);

    // V1 oxygen_cells: no `label` column.
    raw.execute('''
      CREATE TABLE oxygen_cells (
        id TEXT NOT NULL PRIMARY KEY,
        slot INTEGER NOT NULL,
        installed_date INTEGER,
        retired_date INTEGER,
        notes TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER,
        version INTEGER NOT NULL DEFAULT 1,
        sync_status INTEGER NOT NULL DEFAULT 0
      );
    ''');
    raw.execute('PRAGMA user_version = 1;');

    // Insert a v1 row representing existing user data.
    final now = DateTime.now().millisecondsSinceEpoch;
    raw.execute(
      'INSERT INTO oxygen_cells '
      '(id, slot, installed_date, notes, created_at, updated_at, version, sync_status) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      ['cell_v1', 1, now - 86400000, 'pre-upgrade', now, now, 1, 0],
    );

    // Step 2: open AppDatabase against the seeded raw connection.
    // Drift sees user_version=1 and runs onUpgrade(m, 1, 2).
    final db = AppDatabase(NativeDatabase.opened(raw));
    addTearDown(db.close);

    // Step 3: force schema initialization by issuing a query.
    // Drift runs the migration here.
    await db.customSelect('SELECT 1').get();

    // Step 4: confirm we're at v3.
    expect(db.schemaVersion, 7);

    // Step 5: verify the seeded oxygen_cells row survived.
    final cells = await db.select(db.oxygenCells).get();
    expect(cells, hasLength(1));
    expect(cells.single.id, 'cell_v1');
    expect(cells.single.slot, 1);
    expect(cells.single.notes, 'pre-upgrade');
    // The new `label` column must exist and default to null.
    expect(cells.single.label, isNull);

    // Step 6: verify the new tables exist and are empty.
    expect(await db.select(db.cylinders).get(), isEmpty);
    expect(await db.select(db.pressureMappings).get(), isEmpty);

    // Step 7: confirm both new tables accept inserts (no schema corruption).
    await db.into(db.cylinders).insert(CylindersCompanion.insert(
          id: 'c_after_upgrade',
          label: 'O2',
          role: 'oxygen',
          volumeLiters: 2.0,
          workingPressureBar: 200,
          createdAt: now,
          updatedAt: now,
        ));
    expect((await db.select(db.cylinders).get()).single.id, 'c_after_upgrade');
  });

  test('v2 → v3 onUpgrade adds dive_cylinders and preserves dive_annotations',
      () async {
    // Step 1: open a raw sqlite3 db and seed it as v2 (with dive_annotations
    // but without dive_cylinders).
    final raw = sqlite3.openInMemory();
    addTearDown(raw.close);

    _seedDivesV3(raw);

    // V2 dive_annotations: same shape as v3.
    raw.execute('''
      CREATE TABLE dive_annotations (
        dive_id TEXT NOT NULL PRIMARY KEY,
        site_name TEXT,
        site_latitude_e5 INTEGER,
        site_longitude_e5 INTEGER,
        notes TEXT,
        buddies_json TEXT,
        tags_json TEXT,
        rating INTEGER,
        conditions TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER,
        version INTEGER NOT NULL DEFAULT 1,
        sync_status INTEGER NOT NULL DEFAULT 0
      );
    ''');
    raw.execute('PRAGMA user_version = 2;');

    final now = DateTime.now().millisecondsSinceEpoch;
    raw.execute(
      'INSERT INTO dive_annotations '
      '(dive_id, site_name, notes, created_at, updated_at, version, sync_status) '
      'VALUES (?, ?, ?, ?, ?, ?, ?)',
      ['dive_v2', 'Black Lagoon', 'pre-upgrade', now, now, 1, 0],
    );

    // Step 2: open AppDatabase against the seeded raw connection.
    final db = AppDatabase(NativeDatabase.opened(raw));
    addTearDown(db.close);

    // Step 3: trigger schema initialization.
    await db.customSelect('SELECT 1').get();

    // Step 4: confirm we're at v3.
    expect(db.schemaVersion, 7);

    // Step 5: verify the seeded annotation row survived.
    final annotations = await db.select(db.diveAnnotations).get();
    expect(annotations, hasLength(1));
    expect(annotations.single.siteName, 'Black Lagoon');

    // Step 6: verify dive_cylinders is queryable and accepts inserts.
    expect(await db.select(db.diveCylinders).get(), isEmpty);
    await db.into(db.diveCylinders).insert(DiveCylindersCompanion.insert(
          diveId: 'dive_v2',
          gasMixIndex: 0,
          createdAt: now,
          updatedAt: now,
        ));
    final rows = await db.select(db.diveCylinders).get();
    expect(rows, hasLength(1));
    expect(rows.single.cylinderId, isNull);
  });

  test('v3 → v4 onUpgrade adds scrubber stack columns to dives', () async {
    final raw = sqlite3.openInMemory();
    addTearDown(raw.close);

    _seedDivesV3(raw);
    raw.execute('PRAGMA user_version = 3;');

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    raw.execute(
      'INSERT INTO dives '
      '(id, dc_serial, dc_dive_number, start_time, end_time, '
      'duration_seconds, max_depth_mm, dive_mode, deco_model, '
      'atmospheric_pressure_mbar, water_density, log_version, '
      'dc_model, sample_interval_ms, gas_mixes_json, raw_blob, '
      'parser_version, imported_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        'dive_v3', 0xB89641E4, 700, now - 3600, now,
        3600, 30000, 0, 0, 1013, 1025, 17, 0, 10000, '[]', [0], 1, now,
      ],
    );

    final db = AppDatabase(NativeDatabase.opened(raw));
    addTearDown(db.close);

    await db.customSelect('SELECT 1').get();
    expect(db.schemaVersion, 7);

    final dives = await db.select(db.dives).get();
    expect(dives, hasLength(1));
    expect(dives.single.id, 'dive_v3');
    // The new columns must exist and default to null.
    expect(dives.single.configuredStackSeconds, isNull);
    expect(dives.single.stackRemainingAtStartSeconds, isNull);
    expect(dives.single.stackRemainingAtEndSeconds, isNull);
  });

  test('v4 → v5 onUpgrade adds tanks_json column to dives', () async {
    final raw = sqlite3.openInMemory();
    addTearDown(raw.close);

    // Seed v4 dives table: v3 columns + the three scrubber-stack columns.
    _seedDivesV3(raw);
    raw.execute('ALTER TABLE dives ADD COLUMN configured_stack_seconds INTEGER');
    raw.execute(
        'ALTER TABLE dives ADD COLUMN stack_remaining_at_start_seconds INTEGER');
    raw.execute(
        'ALTER TABLE dives ADD COLUMN stack_remaining_at_end_seconds INTEGER');
    raw.execute('PRAGMA user_version = 4;');

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    raw.execute(
      'INSERT INTO dives '
      '(id, dc_serial, dc_dive_number, start_time, end_time, '
      'duration_seconds, max_depth_mm, dive_mode, deco_model, '
      'atmospheric_pressure_mbar, water_density, log_version, '
      'dc_model, sample_interval_ms, gas_mixes_json, raw_blob, '
      'parser_version, imported_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        'dive_v4', 0xB89641E4, 700, now - 3600, now,
        3600, 30000, 0, 0, 1013, 1025, 17, 0, 10000, '[]', [0], 1, now,
      ],
    );

    final db = AppDatabase(NativeDatabase.opened(raw));
    addTearDown(db.close);

    await db.customSelect('SELECT 1').get();
    expect(db.schemaVersion, 7);

    // Migrated row: tanks_json is null on the existing v4 row.
    final migrated = await db.select(db.dives).get();
    expect(migrated, hasLength(1));
    expect(migrated.single.id, 'dive_v4');
    expect(migrated.single.tanksJson, isNull);

    // A fresh insert with tanks_json populated reads back verbatim.
    const tanksJson =
        '[{"slot":0,"usage":3,"name":"DI","serial":0,"beginBar":230.0,'
        '"endBar":185.0,"maxBar":300,"reserveBar":50}]';
    await db.into(db.dives).insert(DivesCompanion.insert(
          id: 'dive_v5',
          dcSerial: 0xB89641E4,
          dcDiveNumber: 800,
          startTime: now,
          endTime: now + 60,
          durationSeconds: 60,
          maxDepthMm: 5000,
          diveMode: 0,
          decoModel: 0,
          atmosphericPressureMbar: 1013,
          waterDensity: 1025,
          logVersion: 17,
          dcModel: 0,
          sampleIntervalMs: 10000,
          gasMixesJson: '[]',
          tanksJson: const Value(tanksJson),
          rawBlob: Uint8List(0),
          parserVersion: 1,
          importedAt: now,
        ));

    final fresh = await (db.select(db.dives)
          ..where((d) => d.id.equals('dive_v5')))
        .getSingle();
    expect(fresh.tanksJson, tanksJson);
  });

  test('v5 → v6 onUpgrade adds tank_pressures_blob column to dive_samples',
      () async {
    final raw = sqlite3.openInMemory();
    addTearDown(raw.close);

    // Seed v5 dives + dive_samples (without tank_pressures_blob).
    _seedDivesV3(raw);
    raw.execute('ALTER TABLE dives ADD COLUMN configured_stack_seconds INTEGER');
    raw.execute(
        'ALTER TABLE dives ADD COLUMN stack_remaining_at_start_seconds INTEGER');
    raw.execute(
        'ALTER TABLE dives ADD COLUMN stack_remaining_at_end_seconds INTEGER');
    raw.execute('ALTER TABLE dives ADD COLUMN tanks_json TEXT');
    raw.execute('PRAGMA user_version = 5;');

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    raw.execute(
      'INSERT INTO dives '
      '(id, dc_serial, dc_dive_number, start_time, end_time, '
      'duration_seconds, max_depth_mm, dive_mode, deco_model, '
      'atmospheric_pressure_mbar, water_density, log_version, '
      'dc_model, sample_interval_ms, gas_mixes_json, raw_blob, '
      'parser_version, imported_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        'dive_v5', 0xB89641E4, 700, now - 3600, now,
        3600, 30000, 0, 0, 1013, 1025, 17, 0, 10000, '[]', [0], 1, now,
      ],
    );
    raw.execute(
      'INSERT INTO dive_samples '
      '(dive_id, sample_count, depth_blob, temperature_blob, ppo2_blob, '
      'cell_mv0_blob, cell_mv1_blob, cell_mv2_blob, setpoint_blob, '
      'cns_blob, deco_depth_blob, deco_time_blob, tts_blob, '
      'gas_mix_idx_blob, status_blob) '
      'VALUES (?, 0, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        'dive_v5',
        ...List<List<int>>.filled(13, <int>[]),
      ],
    );

    final db = AppDatabase(NativeDatabase.opened(raw));
    addTearDown(db.close);

    await db.customSelect('SELECT 1').get();
    expect(db.schemaVersion, 7);

    // The migrated row's tank_pressures_blob is null.
    final migrated = await db.select(db.diveSamples).get();
    expect(migrated, hasLength(1));
    expect(migrated.single.diveId, 'dive_v5');
    expect(migrated.single.tankPressuresBlob, isNull);

    // A fresh insert with tank_pressures_blob populated reads back identically.
    final tankBlob = Uint8List.fromList([1, 2, 3, 4, 5]);
    await db.into(db.dives).insert(DivesCompanion.insert(
          id: 'dive_v6',
          dcSerial: 0xB89641E4,
          dcDiveNumber: 800,
          startTime: now,
          endTime: now + 60,
          durationSeconds: 60,
          maxDepthMm: 5000,
          diveMode: 0,
          decoModel: 0,
          atmosphericPressureMbar: 1013,
          waterDensity: 1025,
          logVersion: 17,
          dcModel: 0,
          sampleIntervalMs: 10000,
          gasMixesJson: '[]',
          rawBlob: Uint8List(0),
          parserVersion: 1,
          importedAt: now,
        ));
    await db.into(db.diveSamples).insert(DiveSamplesCompanion.insert(
          diveId: 'dive_v6',
          sampleCount: 0,
          depthBlob: Uint8List(0),
          temperatureBlob: Uint8List(0),
          ppo2Blob: Uint8List(0),
          cellMv0Blob: Uint8List(0),
          cellMv1Blob: Uint8List(0),
          cellMv2Blob: Uint8List(0),
          setpointBlob: Uint8List(0),
          cnsBlob: Uint8List(0),
          decoDepthBlob: Uint8List(0),
          decoTimeBlob: Uint8List(0),
          ttsBlob: Uint8List(0),
          gasMixIdxBlob: Uint8List(0),
          statusBlob: Uint8List(0),
          tankPressuresBlob: Value(tankBlob),
        ));
    final fresh = await (db.select(db.diveSamples)
          ..where((s) => s.diveId.equals('dive_v6')))
        .getSingle();
    expect(fresh.tankPressuresBlob, equals(tankBlob));
  });

  test('v6 → v7 onUpgrade adds subsurface_uploaded_at column to dives',
      () async {
    final raw = sqlite3.openInMemory();
    addTearDown(raw.close);

    // Seed v6 dives + dive_samples (with tank_pressures_blob, without
    // subsurface_uploaded_at).
    _seedDivesV3(raw);
    raw.execute('ALTER TABLE dives ADD COLUMN configured_stack_seconds INTEGER');
    raw.execute(
        'ALTER TABLE dives ADD COLUMN stack_remaining_at_start_seconds INTEGER');
    raw.execute(
        'ALTER TABLE dives ADD COLUMN stack_remaining_at_end_seconds INTEGER');
    raw.execute('ALTER TABLE dives ADD COLUMN tanks_json TEXT');
    raw.execute('ALTER TABLE dive_samples ADD COLUMN tank_pressures_blob BLOB');
    raw.execute('PRAGMA user_version = 6;');

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    raw.execute(
      'INSERT INTO dives '
      '(id, dc_serial, dc_dive_number, start_time, end_time, '
      'duration_seconds, max_depth_mm, dive_mode, deco_model, '
      'atmospheric_pressure_mbar, water_density, log_version, '
      'dc_model, sample_interval_ms, gas_mixes_json, raw_blob, '
      'parser_version, imported_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        'dive_v6', 0xB89641E4, 700, now - 3600, now,
        3600, 30000, 0, 0, 1013, 1025, 17, 0, 10000, '[]', [0], 1, now,
      ],
    );

    final db = AppDatabase(NativeDatabase.opened(raw));
    addTearDown(db.close);

    await db.customSelect('SELECT 1').get();
    expect(db.schemaVersion, 7);

    // The migrated row has a null subsurface_uploaded_at.
    final migrated = await db.select(db.dives).get();
    expect(migrated, hasLength(1));
    expect(migrated.single.id, 'dive_v6');
    expect(migrated.single.subsurfaceUploadedAt, isNull);

    // A fresh insert populating the column reads back verbatim.
    await db.into(db.dives).insert(DivesCompanion.insert(
          id: 'dive_v7',
          dcSerial: 0xB89641E4,
          dcDiveNumber: 800,
          startTime: now,
          endTime: now + 60,
          durationSeconds: 60,
          maxDepthMm: 5000,
          diveMode: 0,
          decoModel: 0,
          atmosphericPressureMbar: 1013,
          waterDensity: 1025,
          logVersion: 17,
          dcModel: 0,
          sampleIntervalMs: 10000,
          gasMixesJson: '[]',
          rawBlob: Uint8List(0),
          parserVersion: 1,
          importedAt: now,
          subsurfaceUploadedAt: const Value(123456789),
        ));
    final fresh = await (db.select(db.dives)
          ..where((d) => d.id.equals('dive_v7')))
        .getSingle();
    expect(fresh.subsurfaceUploadedAt, 123456789);
  });
}
