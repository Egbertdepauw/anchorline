import 'dart:typed_data';

import 'package:ccrlogger/data/db/database.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

/// Seed the v1-era sync-eligible tables that the v8 migration ALTERs.
/// Called from legacy tests that don't already create these themselves.
void _seedV1SyncTables(
  Database raw, {
  Set<String> except = const {},
}) {
  if (!except.contains('dive_annotations')) {
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
  }
  if (!except.contains('oxygen_cells')) {
    raw.execute('''
      CREATE TABLE oxygen_cells (
        id TEXT NOT NULL PRIMARY KEY,
        slot INTEGER NOT NULL,
        label TEXT,
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
  }
  if (!except.contains('scrubber_sessions')) {
    raw.execute('''
      CREATE TABLE scrubber_sessions (
        id TEXT NOT NULL PRIMARY KEY,
        started_date INTEGER,
        total_minutes INTEGER,
        media_type TEXT,
        notes TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER,
        version INTEGER NOT NULL DEFAULT 1,
        sync_status INTEGER NOT NULL DEFAULT 0
      );
    ''');
  }
  if (!except.contains('dive_computers')) {
    raw.execute('''
      CREATE TABLE dive_computers (
        id TEXT NOT NULL PRIMARY KEY,
        serial INTEGER NOT NULL UNIQUE,
        model INTEGER NOT NULL,
        firmware_version INTEGER,
        nickname TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER,
        version INTEGER NOT NULL DEFAULT 1,
        sync_status INTEGER NOT NULL DEFAULT 0
      );
    ''');
  }
  if (!except.contains('cylinders')) {
    raw.execute('''
      CREATE TABLE cylinders (
        id TEXT NOT NULL PRIMARY KEY,
        label TEXT NOT NULL,
        role TEXT NOT NULL,
        bailout_order INTEGER,
        volume_liters REAL NOT NULL,
        working_pressure_bar INTEGER NOT NULL,
        gas_mix TEXT,
        notes TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER,
        version INTEGER NOT NULL DEFAULT 1,
        sync_status INTEGER NOT NULL DEFAULT 0
      );
    ''');
  }
  if (!except.contains('pressure_mappings')) {
    raw.execute('''
      CREATE TABLE pressure_mappings (
        dive_computer_id TEXT NOT NULL,
        channel_index INTEGER NOT NULL,
        cylinder_id TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER,
        version INTEGER NOT NULL DEFAULT 1,
        sync_status INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (dive_computer_id, channel_index)
      );
    ''');
  }
  if (!except.contains('dive_cylinders')) {
    raw.execute('''
      CREATE TABLE dive_cylinders (
        dive_id TEXT NOT NULL,
        gas_mix_index INTEGER NOT NULL,
        cylinder_id TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER,
        version INTEGER NOT NULL DEFAULT 1,
        sync_status INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (dive_id, gas_mix_index)
      );
    ''');
  }
}

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
    expect(db.schemaVersion, 13);

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
    // v1-era sibling tables (this test creates oxygen_cells itself; the
    // 1→2 migration creates cylinders + pressure_mappings; the 2→3
    // migration creates dive_cylinders).
    _seedV1SyncTables(raw, except: {
      'oxygen_cells',
      'cylinders',
      'pressure_mappings',
      'dive_cylinders',
    });

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
    expect(db.schemaVersion, 13);

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
    // v1-era sibling tables (this test creates dive_annotations itself;
    // the 2→3 migration creates dive_cylinders).
    _seedV1SyncTables(raw, except: {'dive_annotations', 'dive_cylinders'});

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
    expect(db.schemaVersion, 13);

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
    _seedV1SyncTables(raw);
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
    expect(db.schemaVersion, 13);

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
    _seedV1SyncTables(raw);
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
    expect(db.schemaVersion, 13);

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
    _seedV1SyncTables(raw);
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
    expect(db.schemaVersion, 13);

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
    _seedV1SyncTables(raw);
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
    expect(db.schemaVersion, 13);

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

  test('v7 → v8 onUpgrade adds owner_id to every sync-eligible table',
      () async {
    final raw = sqlite3.openInMemory();
    addTearDown(raw.close);

    // Seed v7: dives table with all v7 columns, plus the seven
    // sync-eligible tables in their pre-owner_id shape.
    _seedDivesV3(raw);
    raw.execute('ALTER TABLE dives ADD COLUMN configured_stack_seconds INTEGER');
    raw.execute(
        'ALTER TABLE dives ADD COLUMN stack_remaining_at_start_seconds INTEGER');
    raw.execute(
        'ALTER TABLE dives ADD COLUMN stack_remaining_at_end_seconds INTEGER');
    raw.execute('ALTER TABLE dives ADD COLUMN tanks_json TEXT');
    raw.execute('ALTER TABLE dive_samples ADD COLUMN tank_pressures_blob BLOB');
    raw.execute('ALTER TABLE dives ADD COLUMN subsurface_uploaded_at INTEGER');

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
    raw.execute('''
      CREATE TABLE cylinders (
        id TEXT NOT NULL PRIMARY KEY,
        label TEXT NOT NULL,
        role TEXT NOT NULL,
        bailout_order INTEGER,
        volume_liters REAL NOT NULL,
        working_pressure_bar INTEGER NOT NULL,
        gas_mix TEXT,
        notes TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER,
        version INTEGER NOT NULL DEFAULT 1,
        sync_status INTEGER NOT NULL DEFAULT 0
      );
    ''');
    raw.execute('''
      CREATE TABLE oxygen_cells (
        id TEXT NOT NULL PRIMARY KEY,
        slot INTEGER NOT NULL,
        label TEXT,
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
    raw.execute('''
      CREATE TABLE scrubber_sessions (
        id TEXT NOT NULL PRIMARY KEY,
        started_date INTEGER,
        total_minutes INTEGER,
        media_type TEXT,
        notes TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER,
        version INTEGER NOT NULL DEFAULT 1,
        sync_status INTEGER NOT NULL DEFAULT 0
      );
    ''');
    raw.execute('''
      CREATE TABLE pressure_mappings (
        dive_computer_id TEXT NOT NULL,
        channel_index INTEGER NOT NULL,
        cylinder_id TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER,
        version INTEGER NOT NULL DEFAULT 1,
        sync_status INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (dive_computer_id, channel_index)
      );
    ''');
    raw.execute('''
      CREATE TABLE dive_cylinders (
        dive_id TEXT NOT NULL,
        gas_mix_index INTEGER NOT NULL,
        cylinder_id TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER,
        version INTEGER NOT NULL DEFAULT 1,
        sync_status INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (dive_id, gas_mix_index)
      );
    ''');
    raw.execute('''
      CREATE TABLE dive_computers (
        id TEXT NOT NULL PRIMARY KEY,
        serial INTEGER NOT NULL UNIQUE,
        model INTEGER NOT NULL,
        firmware_version INTEGER,
        nickname TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER,
        version INTEGER NOT NULL DEFAULT 1,
        sync_status INTEGER NOT NULL DEFAULT 0
      );
    ''');
    raw.execute('PRAGMA user_version = 7;');

    final now = DateTime.now().millisecondsSinceEpoch;
    raw.execute(
      'INSERT INTO dive_annotations '
      '(dive_id, site_name, notes, created_at, updated_at, version, sync_status) '
      'VALUES (?, ?, ?, ?, ?, ?, ?)',
      ['dive_v7', 'Black Lagoon', 'pre-upgrade', now, now, 1, 0],
    );
    raw.execute(
      'INSERT INTO cylinders '
      '(id, label, role, volume_liters, working_pressure_bar, '
      'created_at, updated_at, version, sync_status) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
      ['cyl_v7', 'AL40', 'bailout', 5.7, 207, now, now, 1, 0],
    );
    raw.execute(
      'INSERT INTO oxygen_cells '
      '(id, slot, created_at, updated_at, version, sync_status) '
      'VALUES (?, ?, ?, ?, ?, ?)',
      ['cell_v7', 1, now, now, 1, 0],
    );
    raw.execute(
      'INSERT INTO scrubber_sessions '
      '(id, created_at, updated_at, version, sync_status) '
      'VALUES (?, ?, ?, ?, ?)',
      ['scrub_v7', now, now, 1, 0],
    );
    raw.execute(
      'INSERT INTO pressure_mappings '
      '(dive_computer_id, channel_index, created_at, updated_at, version, sync_status) '
      'VALUES (?, ?, ?, ?, ?, ?)',
      ['dc_v7', 0, now, now, 1, 0],
    );
    raw.execute(
      'INSERT INTO dive_cylinders '
      '(dive_id, gas_mix_index, created_at, updated_at, version, sync_status) '
      'VALUES (?, ?, ?, ?, ?, ?)',
      ['dive_v7', 0, now, now, 1, 0],
    );
    raw.execute(
      'INSERT INTO dive_computers '
      '(id, serial, model, created_at, updated_at, version, sync_status) '
      'VALUES (?, ?, ?, ?, ?, ?, ?)',
      ['dc_v7', 0xB89641E4, 0, now, now, 1, 0],
    );

    final db = AppDatabase(NativeDatabase.opened(raw));
    addTearDown(db.close);

    await db.customSelect('SELECT 1').get();
    expect(db.schemaVersion, 13);

    // Pre-existing rows survive the migration with owner_id null.
    expect((await db.select(db.diveAnnotations).get()).single.ownerId, isNull);
    expect((await db.select(db.cylinders).get()).single.ownerId, isNull);
    expect((await db.select(db.oxygenCells).get()).single.ownerId, isNull);
    expect((await db.select(db.scrubberSessions).get()).single.ownerId, isNull);
    expect((await db.select(db.pressureMappings).get()).single.ownerId, isNull);
    expect((await db.select(db.diveCylinders).get()).single.ownerId, isNull);
    expect((await db.select(db.diveComputers).get()).single.ownerId, isNull);

    // Inserting with owner_id populated reads back verbatim.
    const ownerUuid = '00000000-0000-0000-0000-000000000001';
    await db.into(db.cylinders).insert(CylindersCompanion.insert(
          id: 'cyl_v8',
          label: 'AL80',
          role: 'bailout',
          volumeLiters: 11.1,
          workingPressureBar: 207,
          createdAt: now,
          updatedAt: now,
          ownerId: const Value(ownerUuid),
        ));
    final fresh = await (db.select(db.cylinders)
          ..where((c) => c.id.equals('cyl_v8')))
        .getSingle();
    expect(fresh.ownerId, ownerUuid);
  });

  test('v8 → v9 onUpgrade adds deleted_at column to dives', () async {
    final raw = sqlite3.openInMemory();
    addTearDown(raw.close);

    // Seed a v8 dives table — all v8 columns including owner_id, but
    // without deleted_at.
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
        tanks_json TEXT,
        configured_stack_seconds INTEGER,
        stack_remaining_at_start_seconds INTEGER,
        stack_remaining_at_end_seconds INTEGER,
        raw_blob BLOB NOT NULL,
        parser_version INTEGER NOT NULL,
        imported_at INTEGER NOT NULL,
        subsurface_uploaded_at INTEGER
      );
    ''');
    // dive_annotations needs to exist because the v12 step ALTERs it.
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
        sync_status INTEGER NOT NULL DEFAULT 0,
        owner_id TEXT
      );
    ''');
    raw.execute('PRAGMA user_version = 8;');

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
        'dive_v8', 0xB89641E4, 900, now - 3600, now,
        3600, 30000, 0, 0, 1013, 1025, 17, 0, 10000, '[]', [0], 1, now,
      ],
    );

    final db = AppDatabase(NativeDatabase.opened(raw));
    addTearDown(db.close);

    await db.customSelect('SELECT 1').get();
    expect(db.schemaVersion, 13);

    // Pre-existing dive survives with deleted_at null (visible in queries).
    final migrated = await db.select(db.dives).get();
    expect(migrated, hasLength(1));
    expect(migrated.single.deletedAt, isNull);

    // Soft-delete via raw write reads back as a non-null bigint.
    final deletedAtMs = DateTime.now().millisecondsSinceEpoch;
    await (db.update(db.dives)..where((d) => d.id.equals('dive_v8')))
        .write(DivesCompanion(deletedAt: Value(deletedAtMs)));
    final fresh = await (db.select(db.dives)
          ..where((d) => d.id.equals('dive_v8')))
        .getSingle();
    expect(fresh.deletedAt, deletedAtMs);
  });

  test('v10 → v11 onUpgrade adds sensor_calibration_json column to dives',
      () async {
    final raw = sqlite3.openInMemory();
    addTearDown(raw.close);

    // Seed a v10 dives table — every column up to and including
    // deleted_at, but without sensor_calibration_json. v10 also added
    // dive_raw_blobs, but that table only matters when the migrator
    // copies live data over; it's not relevant to this column-add test.
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
        tanks_json TEXT,
        configured_stack_seconds INTEGER,
        stack_remaining_at_start_seconds INTEGER,
        stack_remaining_at_end_seconds INTEGER,
        raw_blob BLOB NOT NULL,
        parser_version INTEGER NOT NULL,
        imported_at INTEGER NOT NULL,
        subsurface_uploaded_at INTEGER,
        deleted_at INTEGER
      );
    ''');
    raw.execute('''
      CREATE TABLE dive_raw_blobs (
        dive_id TEXT NOT NULL PRIMARY KEY,
        raw_blob BLOB NOT NULL
      );
    ''');
    // v8 added owner_id to dive_annotations; the v12 step ALTERs that
    // table further, so it has to exist at the start of an upgrade
    // chain that runs both v11 and v12 steps.
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
        sync_status INTEGER NOT NULL DEFAULT 0,
        owner_id TEXT
      );
    ''');
    raw.execute('PRAGMA user_version = 10;');

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
        'dive_v10', 0xB89641E4, 1000, now - 3600, now,
        3600, 30000, 0, 0, 1013, 1025, 17, 0, 10000, '[]', [0], 1, now,
      ],
    );

    final db = AppDatabase(NativeDatabase.opened(raw));
    addTearDown(db.close);

    await db.customSelect('SELECT 1').get();
    expect(db.schemaVersion, 13);

    // Pre-existing v10 row survives with sensor_calibration_json null —
    // the mapper's fallback (Petrel default 0.021) is what handles legacy
    // data, so we don't backfill anything during migration.
    final migrated = await db.select(db.dives).get();
    expect(migrated, hasLength(1));
    expect(migrated.single.id, 'dive_v10');
    expect(migrated.single.sensorCalibrationJson, isNull);

    // A fresh insert populating the column reads back verbatim.
    const calJson = '[0.021,0.022,0.020]';
    await db.into(db.dives).insert(DivesCompanion.insert(
          id: 'dive_v11',
          dcSerial: 0xB89641E4,
          dcDiveNumber: 1001,
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
          sensorCalibrationJson: const Value(calJson),
          rawBlob: Uint8List(0),
          parserVersion: 1,
          importedAt: now,
        ));
    final fresh = await (db.select(db.dives)
          ..where((d) => d.id.equals('dive_v11')))
        .getSingle();
    expect(fresh.sensorCalibrationJson, calJson);
  });

  test('v11 → v12 onUpgrade adds Information-tab columns to dive_annotations',
      () async {
    final raw = sqlite3.openInMemory();
    addTearDown(raw.close);

    // Seed a v11 dive_annotations table — every column up to and
    // including owner_id (added at v8) but without the eight new
    // Information-tab columns (visibility/wavesize/current/surge/chill,
    // air_temp_c, water_temp_c, weights_json).
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
        sync_status INTEGER NOT NULL DEFAULT 0,
        owner_id TEXT
      );
    ''');
    // dives is a FK target of dive_annotations.dive_id, so create a
    // minimal stub. Same for the other v11-era sync-eligible tables.
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
        tanks_json TEXT,
        sensor_calibration_json TEXT,
        configured_stack_seconds INTEGER,
        stack_remaining_at_start_seconds INTEGER,
        stack_remaining_at_end_seconds INTEGER,
        raw_blob BLOB NOT NULL,
        parser_version INTEGER NOT NULL,
        imported_at INTEGER NOT NULL,
        subsurface_uploaded_at INTEGER,
        deleted_at INTEGER
      );
    ''');
    _seedV1SyncTables(raw, except: const {'dive_annotations'});
    raw.execute('PRAGMA user_version = 11;');

    final now = DateTime.now().millisecondsSinceEpoch;
    raw.execute(
      'INSERT INTO dive_annotations '
      '(dive_id, rating, created_at, updated_at) VALUES (?, ?, ?, ?)',
      ['dive_v11', 4, now, now],
    );

    final db = AppDatabase(NativeDatabase.opened(raw));
    addTearDown(db.close);

    await db.customSelect('SELECT 1').get();
    expect(db.schemaVersion, 13);

    // Pre-existing v11 row survives; new columns default to null/empty.
    final migrated = await db.select(db.diveAnnotations).get();
    expect(migrated, hasLength(1));
    expect(migrated.single.diveId, 'dive_v11');
    expect(migrated.single.rating, 4);
    expect(migrated.single.visibility, isNull);
    expect(migrated.single.wavesize, isNull);
    expect(migrated.single.current, isNull);
    expect(migrated.single.surge, isNull);
    expect(migrated.single.chill, isNull);
    expect(migrated.single.airTempC, isNull);
    expect(migrated.single.waterTempC, isNull);
    expect(migrated.single.weightsJson, isNull);

    // A fresh insert populating the new columns reads back verbatim.
    await db.into(db.diveAnnotations).insert(DiveAnnotationsCompanion.insert(
          diveId: 'dive_v12',
          createdAt: now,
          updatedAt: now,
          visibility: const Value(5),
          wavesize: const Value(3),
          current: const Value(4),
          surge: const Value(4),
          chill: const Value(5),
          airTempC: const Value(24.0),
          waterTempC: const Value(22.0),
          weightsJson: const Value(
              '[{"weight_kg":1.5,"description":"onder standaard"}]'),
        ));
    final fresh = await (db.select(db.diveAnnotations)
          ..where((a) => a.diveId.equals('dive_v12')))
        .getSingle();
    expect(fresh.visibility, 5);
    expect(fresh.wavesize, 3);
    expect(fresh.current, 4);
    expect(fresh.surge, 4);
    expect(fresh.chill, 5);
    expect(fresh.airTempC, 24.0);
    expect(fresh.waterTempC, 22.0);
    expect(fresh.weightsJson,
        '[{"weight_kg":1.5,"description":"onder standaard"}]');
  });
}
