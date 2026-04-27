import 'package:ccrlogger/data/db/database.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('schema v2: has cylinders, pressure_mappings, oxygen_cells.label', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    expect(db.schemaVersion, 2);

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

    // Step 4: confirm we're at v2.
    expect(db.schemaVersion, 2);

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
}
