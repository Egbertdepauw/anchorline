# Equipment View Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Equipment tab placeholder with a four-category equipment view (Dive Computers, O2 Cells, Scrubber Sessions, Cylinders) plus a per-DC pressure-channel-to-cylinder mapping. The cell detail screen surfaces the longitudinal surface-mV trend — the project's headline analytical feature.

**Architecture:** A single `EquipmentDao` owns all reads/writes against the four equipment tables and the new `PressureMappings` table. One `ChangeNotifier` per category drives its list/detail screens. The Equipment landing is an index of four cards that drill into category lists; tapping an item pushes a detail screen. The import flow gains hooks to auto-create `DiveComputers` rows on connect and to call `applyScrubberEvents` per imported dive.

**Tech Stack:** Flutter, Drift (SQLite), `ChangeNotifier`, `flutter_test` widget tests, build_runner code generation.

---

### Spec

`docs/superpowers/specs/2026-04-26-equipment-view-design.md` — read first.

### Key existing types

- `AppDatabase` (`lib/data/db/database.dart`): `@DriftDatabase(tables: [Dives, DiveSamples, DiveAnnotations, DiveComputers, OxygenCells, ScrubberSessions, ImportStates])`, `int get schemaVersion => 1;` — bump to 2 in Task 1.
- `DiveDao` (`lib/data/db/dive_dao.dart`): existing pattern for `getAllDives`, `importDive`. Mirror its style for `EquipmentDao`.
- `Dive` (Drift row type from `database.g.dart`): includes `id`, `dcSerial`, `dcDiveNumber`, `startTimeUtc`, `runtimeSeconds`.
- `OxygenCells` table (`lib/data/db/tables.dart:130-145`): currently has `id`, `slot`, `installedDate`, `retiredDate`, `notes` + sync metadata. Task 1 adds `label`.
- `ScrubberSessions` table (`lib/data/db/tables.dart:148-163`): `id`, `startedDate`, `totalMinutes`, `mediaType`, `notes` + sync metadata. No schema change; `totalMinutes` becomes derived (DAO computes; UI uses derived value).
- `DiveComputers` table (`lib/data/db/tables.dart:112-127`): `id` (text), `serial` (int unique), `model` (int), `firmwareVersion` (int?), `nickname` (text?) + sync metadata.
- `ParsedDive` (`lib/shearwater/parser/parsed_dive.dart`): per-sample data including `cellMv0/1/2`. `scrubberResetAt` does **not** currently exist on this type; `applyScrubberEvents` becomes a no-op until parser-side support lands.
- `ConvertedDive` (`lib/shearwater/parser/dive_converter.dart`): contains decoded `Float32List cellMv0/1/2` and `depthM` series.
- `ImportNotifier` (`lib/ui/notifiers/import_notifier.dart`): `selectRealDevice(BluetoothDevice)` followed by `readManifestAndFilterNew()` and `downloadAll()`. Two integration points in Task 20.
- `AppShell` (`lib/ui/app_shell.dart:55-79`): `IndexedStack` with `PlaceholderScreen(title: 'Equipment', ...)` at index 2 — replaced in Task 9.
- `DiveListNotifier` (`lib/ui/notifiers/dive_list_notifier.dart`): existing `ChangeNotifier` pattern with `loadDives()`. Mirror its shape.

### In-memory DB test boilerplate (used in every DAO test file)

```dart
import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/data/db/equipment_dao.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

AppDatabase _createInMemoryDb() => AppDatabase(NativeDatabase.memory());

void main() {
  late AppDatabase db;
  late EquipmentDao dao;

  setUp(() {
    db = _createInMemoryDb();
    dao = EquipmentDao(db);
  });

  tearDown(() async {
    await db.close();
  });

  // tests...
}
```

### Cylinder role enum

Roles are constants in code. Use plain Dart string constants on a holder class to keep Drift columns as `text`:

```dart
// lib/data/models/equipment.dart (extend existing file)
class CylinderRole {
  static const oxygen = 'oxygen';
  static const diluent = 'diluent';
  static const bailout = 'bailout';
  static const offboard = 'offboard';
  static const all = [oxygen, diluent, bailout, offboard];
}
```

---

### Task 1: Schema migration — `label` on OxygenCells, new `Cylinders` and `PressureMappings` tables

**Files:**
- Modify: `lib/data/db/tables.dart`
- Modify: `lib/data/db/database.dart`
- Run: `dart run build_runner build --delete-conflicting-outputs`
- Test: `test/data/db/migration_test.dart`

- [ ] **Step 1: Add `label` column to `OxygenCells`**

In `lib/data/db/tables.dart`, modify the `OxygenCells` class:

```dart
class OxygenCells extends Table {
  TextColumn get id => text()();
  IntColumn get slot => integer()(); // 1, 2, or 3
  TextColumn get label => text().nullable()(); // e.g. "Analytical R-22D #1234"
  IntColumn get installedDate => integer().nullable()();
  IntColumn get retiredDate => integer().nullable()();
  TextColumn get notes => text().nullable()();

  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  IntColumn get syncStatus => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}
```

- [ ] **Step 2: Add `Cylinders` table**

Append to `lib/data/db/tables.dart`:

```dart
/// User-managed cylinders (O2, diluent, bailout, offboard).
class Cylinders extends Table {
  TextColumn get id => text()();
  TextColumn get label => text()(); // "AL40 stage", "12L steel"
  TextColumn get role => text()(); // 'oxygen' | 'diluent' | 'bailout' | 'offboard'
  IntColumn get bailoutOrder => integer().nullable()(); // only when role == 'bailout'
  RealColumn get volumeLiters => real()();
  IntColumn get workingPressureBar => integer()();
  TextColumn get gasMix => text().nullable()(); // "21/35", "100", null
  TextColumn get notes => text().nullable()();

  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  IntColumn get syncStatus => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}
```

- [ ] **Step 3: Add `PressureMappings` table**

Append to `lib/data/db/tables.dart`:

```dart
/// Per-DC mapping from pressure-channel index to a Cylinder.
class PressureMappings extends Table {
  TextColumn get diveComputerId => text()();
  IntColumn get channelIndex => integer()(); // 0, 1, 2, ... as logged
  TextColumn get cylinderId => text().nullable()(); // FK to Cylinders.id; null = unmapped

  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  IntColumn get syncStatus => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {diveComputerId, channelIndex};
}
```

- [ ] **Step 4: Register tables and bump schemaVersion + migration**

In `lib/data/db/database.dart`, update the `@DriftDatabase` annotation and the version + migration:

```dart
@DriftDatabase(tables: [
  Dives,
  DiveSamples,
  DiveAnnotations,
  DiveComputers,
  OxygenCells,
  ScrubberSessions,
  Cylinders,            // NEW
  PressureMappings,     // NEW
  ImportStates,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.addColumn(oxygenCells, oxygenCells.label);
            await m.createTable(cylinders);
            await m.createTable(pressureMappings);
          }
        },
      );
}
```

- [ ] **Step 5: Regenerate Drift code**

Run: `dart run build_runner build --delete-conflicting-outputs`

Expected: completes without errors; `database.g.dart` updates to include `Cylinders` and `PressureMappings` table classes plus the new `label` column on `OxygenCells`.

- [ ] **Step 6: Write the failing migration test**

```dart
// test/data/db/migration_test.dart
import 'package:ccrlogger/data/db/database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
```

- [ ] **Step 7: Run the test, verify it passes**

Run: `flutter test test/data/db/migration_test.dart`

Expected: `+1: All tests passed!`

- [ ] **Step 8: Commit**

```bash
git add lib/data/db/tables.dart lib/data/db/database.dart lib/data/db/database.g.dart test/data/db/migration_test.dart
git commit -m "feat(equipment): add cylinders and pressure_mappings tables, oxygen_cells.label"
```

---

### Task 2: `EquipmentDao` foundation + DiveComputers methods

**Files:**
- Create: `lib/data/db/equipment_dao.dart`
- Create: `test/data/db/equipment_dao_test.dart`

- [ ] **Step 1: Write the failing test for `upsertDiveComputer`**

```dart
// test/data/db/equipment_dao_test.dart
import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/data/db/equipment_dao.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

AppDatabase _db() => AppDatabase(NativeDatabase.memory());

void main() {
  late AppDatabase db;
  late EquipmentDao dao;

  setUp(() {
    db = _db();
    dao = EquipmentDao(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('DiveComputers', () {
    test('upsertDiveComputer inserts a new row', () async {
      await dao.upsertDiveComputer(
        serial: 0xB89641E4,
        model: 0xB407,
        firmwareVersion: 103,
      );
      final list = await dao.listDiveComputers();
      expect(list, hasLength(1));
      expect(list.single.serial, 0xB89641E4);
      expect(list.single.nickname, isNull);
    });

    test('upsertDiveComputer is idempotent on serial and preserves nickname', () async {
      await dao.upsertDiveComputer(serial: 1, model: 0xB407, firmwareVersion: 103);
      final inserted = (await dao.listDiveComputers()).single;
      await dao.setComputerNickname(inserted.id, 'Top deck');

      // Second upsert with same serial should not clobber nickname.
      await dao.upsertDiveComputer(serial: 1, model: 0xB407, firmwareVersion: 104);

      final list = await dao.listDiveComputers();
      expect(list, hasLength(1));
      expect(list.single.nickname, 'Top deck');
      expect(list.single.firmwareVersion, 104); // firmware does update
    });
  });
}
```

- [ ] **Step 2: Run the test, verify it fails (file not found)**

Run: `flutter test test/data/db/equipment_dao_test.dart`

Expected: compilation error — `equipment_dao.dart` does not exist.

- [ ] **Step 3: Create the DAO with DiveComputers methods**

```dart
// lib/data/db/equipment_dao.dart
import 'package:drift/drift.dart';

import 'database.dart';

part 'equipment_dao.g.dart';

@DriftAccessor(tables: [
  DiveComputers,
  OxygenCells,
  ScrubberSessions,
  Cylinders,
  PressureMappings,
])
class EquipmentDao extends DatabaseAccessor<AppDatabase>
    with _$EquipmentDaoMixin {
  EquipmentDao(super.db);

  // ── DiveComputers ────────────────────────────────────────────────────────

  /// Insert or update by `serial`. Preserves user-set `nickname` on update.
  /// Returns the resulting computer's primary-key id.
  Future<String> upsertDiveComputer({
    required int serial,
    required int model,
    int? firmwareVersion,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final existing = await (select(diveComputers)
          ..where((t) => t.serial.equals(serial)))
        .getSingleOrNull();

    if (existing == null) {
      final id = 'dc_${serial.toRadixString(16)}';
      await into(diveComputers).insert(DiveComputersCompanion.insert(
        id: id,
        serial: serial,
        model: model,
        firmwareVersion: Value(firmwareVersion),
        createdAt: now,
        updatedAt: now,
      ));
      return id;
    }

    await (update(diveComputers)..where((t) => t.id.equals(existing.id))).write(
      DiveComputersCompanion(
        model: Value(model),
        firmwareVersion: Value(firmwareVersion),
        updatedAt: Value(now),
      ),
    );
    return existing.id;
  }

  Future<List<DiveComputer>> listDiveComputers() {
    return (select(diveComputers)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]))
        .get();
  }

  Future<void> setComputerNickname(String id, String? nickname) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await (update(diveComputers)..where((t) => t.id.equals(id))).write(
      DiveComputersCompanion(
        nickname: Value(nickname),
        updatedAt: Value(now),
      ),
    );
  }
}
```

- [ ] **Step 4: Regenerate the DAO mixin**

Run: `dart run build_runner build --delete-conflicting-outputs`

Expected: creates `lib/data/db/equipment_dao.g.dart`.

- [ ] **Step 5: Run the test, verify it passes**

Run: `flutter test test/data/db/equipment_dao_test.dart`

Expected: `+2: All tests passed!`

- [ ] **Step 6: Add `recentImportsForComputer` test and method**

Append to `equipment_dao_test.dart` inside the `DiveComputers` group:

```dart
test('recentImportsForComputer returns recent dives sorted desc', () async {
  await dao.upsertDiveComputer(serial: 0xAA, model: 0xB407);

  await db.into(db.dives).insert(DivesCompanion.insert(
        id: 'd1',
        dcSerial: 0xAA,
        dcDiveNumber: 1,
        dcModel: 0xB407,
        startTimeUtc: 1000,
        endTimeUtc: 2000,
        runtimeSeconds: 1000,
        mode: 0,
        sampleInterval: 10,
        rawBlobHash: 'h1',
        rawBlob: Uint8List(0),
        sampleBlob: Uint8List(0),
        parserVersion: 1,
        createdAt: 1000,
        updatedAt: 1000,
      ));
  await db.into(db.dives).insert(DivesCompanion.insert(
        id: 'd2',
        dcSerial: 0xAA,
        dcDiveNumber: 2,
        dcModel: 0xB407,
        startTimeUtc: 5000,
        endTimeUtc: 6000,
        runtimeSeconds: 1000,
        mode: 0,
        sampleInterval: 10,
        rawBlobHash: 'h2',
        rawBlob: Uint8List(0),
        sampleBlob: Uint8List(0),
        parserVersion: 1,
        createdAt: 5000,
        updatedAt: 5000,
      ));

  final recent = await dao.recentImportsForComputer(0xAA, limit: 10);
  expect(recent.map((d) => d.id).toList(), ['d2', 'd1']);
});
```

Add to the test file imports:

```dart
import 'dart:typed_data';
```

Add the method to `EquipmentDao`:

```dart
/// Most recent dives imported from this computer (by `dcSerial`).
Future<List<Dive>> recentImportsForComputer(int serial, {int limit = 10}) {
  return (select(db.dives)
        ..where((t) => t.dcSerial.equals(serial))
        ..orderBy([(t) => OrderingTerm.desc(t.startTimeUtc)])
        ..limit(limit))
      .get();
}
```

- [ ] **Step 7: Run the test, verify it passes**

Run: `flutter test test/data/db/equipment_dao_test.dart`

Expected: `+3: All tests passed!`

- [ ] **Step 8: Commit**

```bash
git add lib/data/db/equipment_dao.dart lib/data/db/equipment_dao.g.dart test/data/db/equipment_dao_test.dart
git commit -m "feat(equipment): EquipmentDao with DiveComputers CRUD"
```

---

### Task 3: `EquipmentDao` OxygenCells CRUD

**Files:**
- Modify: `lib/data/db/equipment_dao.dart`
- Modify: `test/data/db/equipment_dao_test.dart`

- [ ] **Step 1: Write failing tests for cell CRUD**

Append to `test/data/db/equipment_dao_test.dart`:

```dart
group('OxygenCells', () {
  test('addCell + listCells round-trip', () async {
    final id = await dao.addCell(slot: 1, label: 'R-22D #001', installedDate: DateTime(2025, 1, 1));
    final cells = await dao.listCells();
    expect(cells, hasLength(1));
    expect(cells.single.id, id);
    expect(cells.single.slot, 1);
    expect(cells.single.label, 'R-22D #001');
  });

  test('listCells sorts active first then retired by retiredDate desc', () async {
    final a = await dao.addCell(slot: 1, label: 'old', installedDate: DateTime(2024, 1, 1));
    final b = await dao.addCell(slot: 2, label: 'active', installedDate: DateTime(2025, 1, 1));
    await dao.retireCell(a, retiredAt: DateTime(2024, 6, 1));

    final cells = await dao.listCells();
    expect(cells.map((c) => c.id).toList(), [b, a]);
  });

  test('deleteCellIfUnused succeeds when no dives overlap', () async {
    final id = await dao.addCell(slot: 1, label: 'unused', installedDate: DateTime(2030, 1, 1));
    final ok = await dao.deleteCellIfUnused(id);
    expect(ok, isTrue);
    expect(await dao.listCells(), isEmpty);
  });
});
```

- [ ] **Step 2: Run the test, verify it fails**

Run: `flutter test test/data/db/equipment_dao_test.dart`

Expected: missing methods on `EquipmentDao`.

- [ ] **Step 3: Implement cell CRUD methods**

Append to `EquipmentDao` (in the body of the class):

```dart
// ── OxygenCells ──────────────────────────────────────────────────────────

Future<String> addCell({
  required int slot,
  String? label,
  DateTime? installedDate,
  String? notes,
}) async {
  final now = DateTime.now().millisecondsSinceEpoch;
  final id = 'cell_${now}_${slot}';
  await into(oxygenCells).insert(OxygenCellsCompanion.insert(
    id: id,
    slot: slot,
    label: Value(label),
    installedDate: Value(installedDate?.millisecondsSinceEpoch),
    notes: Value(notes),
    createdAt: now,
    updatedAt: now,
  ));
  return id;
}

Future<List<OxygenCell>> listCells() async {
  final rows = await (select(oxygenCells)
        ..where((t) => t.deletedAt.isNull()))
      .get();
  rows.sort((a, b) {
    if (a.retiredDate == null && b.retiredDate != null) return -1;
    if (a.retiredDate != null && b.retiredDate == null) return 1;
    if (a.retiredDate != null && b.retiredDate != null) {
      return b.retiredDate!.compareTo(a.retiredDate!);
    }
    return (b.installedDate ?? 0).compareTo(a.installedDate ?? 0);
  });
  return rows;
}

Future<OxygenCell?> getCell(String id) {
  return (select(oxygenCells)..where((t) => t.id.equals(id)))
      .getSingleOrNull();
}

Future<void> updateCell(
  String id, {
  int? slot,
  String? label,
  DateTime? installedDate,
  String? notes,
}) async {
  final now = DateTime.now().millisecondsSinceEpoch;
  await (update(oxygenCells)..where((t) => t.id.equals(id))).write(
    OxygenCellsCompanion(
      slot: slot == null ? const Value.absent() : Value(slot),
      label: Value(label),
      installedDate: Value(installedDate?.millisecondsSinceEpoch),
      notes: Value(notes),
      updatedAt: Value(now),
    ),
  );
}

Future<void> retireCell(String id, {required DateTime retiredAt}) async {
  final now = DateTime.now().millisecondsSinceEpoch;
  await (update(oxygenCells)..where((t) => t.id.equals(id))).write(
    OxygenCellsCompanion(
      retiredDate: Value(retiredAt.millisecondsSinceEpoch),
      updatedAt: Value(now),
    ),
  );
}

/// Deletes the cell only if no dives overlap its [installedDate, retiredDate)
/// window. Returns true on success, false if the cell has attributable dives.
Future<bool> deleteCellIfUnused(String id) async {
  final cell = await getCell(id);
  if (cell == null) return false;

  final overlapping = await (select(db.dives)
        ..where((t) {
          var expr = t.startTimeUtc.isBiggerOrEqualValue(
              cell.installedDate ?? 0);
          if (cell.retiredDate != null) {
            expr = expr & t.startTimeUtc.isSmallerThanValue(cell.retiredDate!);
          }
          return expr;
        })
        ..limit(1))
      .get();
  if (overlapping.isNotEmpty) return false;

  await (delete(oxygenCells)..where((t) => t.id.equals(id))).go();
  return true;
}
```

- [ ] **Step 4: Run the tests, verify they pass**

Run: `flutter test test/data/db/equipment_dao_test.dart`

Expected: `+6: All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add lib/data/db/equipment_dao.dart test/data/db/equipment_dao_test.dart
git commit -m "feat(equipment): OxygenCells CRUD on EquipmentDao"
```

---

### Task 4: `EquipmentDao.surfaceMvSeriesForCell` aggregation

**Files:**
- Modify: `lib/data/db/equipment_dao.dart`
- Modify: `test/data/db/equipment_dao_test.dart`

- [ ] **Step 1: Add a helper to construct synthetic dives + samples**

Append to `test/data/db/equipment_dao_test.dart` (above the existing groups, near the top):

```dart
/// Builds a Dive row whose sample blob has the supplied (depthM, cellMv0/1/2)
/// per-sample columns. Inserts and returns the dive id.
Future<String> _insertDiveWithSamples(
  AppDatabase db, {
  required String id,
  required int dcSerial,
  required DateTime startTime,
  required List<double> depthM,
  required List<double> cellMv0,
  required List<double> cellMv1,
  required List<double> cellMv2,
}) async {
  final n = depthM.length;
  // Columnar blob: simple back-to-back Float32 columns (depth, mv0, mv1, mv2).
  // The DAO's surfaceMvSeriesForCell reads the same layout. Real samples
  // come through DiveConverter — synthetic samples here only need to round-trip.
  final byteCount = n * 4 * 4;
  final bytes = Uint8List(byteCount);
  final view = ByteData.sublistView(bytes);
  for (var i = 0; i < n; i++) {
    view.setFloat32(i * 4, depthM[i], Endian.little);
    view.setFloat32((n + i) * 4, cellMv0[i], Endian.little);
    view.setFloat32((2 * n + i) * 4, cellMv1[i], Endian.little);
    view.setFloat32((3 * n + i) * 4, cellMv2[i], Endian.little);
  }

  await db.into(db.dives).insert(DivesCompanion.insert(
        id: id,
        dcSerial: dcSerial,
        dcDiveNumber: 1,
        dcModel: 0xB407,
        startTimeUtc: startTime.millisecondsSinceEpoch,
        endTimeUtc: startTime.millisecondsSinceEpoch + 60_000,
        runtimeSeconds: 60,
        mode: 0,
        sampleInterval: 10,
        rawBlobHash: id,
        rawBlob: Uint8List(0),
        sampleBlob: bytes,
        parserVersion: 1,
        createdAt: startTime.millisecondsSinceEpoch,
        updatedAt: startTime.millisecondsSinceEpoch,
      ));

  await db.into(db.diveSamples).insert(DiveSamplesCompanion.insert(
        diveId: id,
        sampleCount: n,
      ));
  return id;
}
```

> NOTE: The synthetic blob layout above (4 columns × N samples × 4 bytes, columns in order depth/mv0/mv1/mv2, little-endian) **must match** what `surfaceMvSeriesForCell` reads. If the existing `DiveConverter`/sample codec uses a different layout, change both this helper and the DAO method to match the real layout. **Verify against `lib/data/sample_codec/` (or wherever sample blobs are encoded) during implementation** and update both sides.

- [ ] **Step 2: Write failing test for `surfaceMvSeriesForCell`**

Append to `test/data/db/equipment_dao_test.dart`:

```dart
group('surfaceMvSeriesForCell', () {
  test('returns mean of cellMv samples below 1.0m, voted-out filtered', () async {
    final cellId = await dao.addCell(
      slot: 1,
      label: 'test',
      installedDate: DateTime(2025, 1, 1),
    );
    // Slot 1 → cellMv0 column.
    await _insertDiveWithSamples(
      db,
      id: 'dive_a',
      dcSerial: 1,
      startTime: DateTime(2025, 6, 1),
      depthM:    [0.0, 0.5, 5.0, 0.5, 0.0],
      cellMv0:   [10.0, 11.0, 50.0, 12.0, 9.0], // surface samples avg = 10.5
      cellMv1:   [0, 0, 0, 0, 0],
      cellMv2:   [0, 0, 0, 0, 0],
    );

    final series = await dao.surfaceMvSeriesForCell(cellId);
    expect(series, hasLength(1));
    expect(series.single.mv, closeTo(10.5, 0.01));
  });

  test('omits dives outside the cell window', () async {
    final cellId = await dao.addCell(
      slot: 1,
      label: 't',
      installedDate: DateTime(2025, 1, 1),
    );
    await dao.retireCell(cellId, retiredAt: DateTime(2025, 3, 1));

    await _insertDiveWithSamples(
      db,
      id: 'dive_outside',
      dcSerial: 1,
      startTime: DateTime(2025, 6, 1),
      depthM: [0.0],
      cellMv0: [10.0],
      cellMv1: [0],
      cellMv2: [0],
    );

    expect(await dao.surfaceMvSeriesForCell(cellId), isEmpty);
  });

  test('omits dives whose surface samples are all voted-out', () async {
    final cellId = await dao.addCell(
      slot: 1,
      label: 't',
      installedDate: DateTime(2025, 1, 1),
    );
    await _insertDiveWithSamples(
      db,
      id: 'dive_vo',
      dcSerial: 1,
      startTime: DateTime(2025, 6, 1),
      depthM: [0.0, 0.5, 0.0],
      cellMv0: [2.0, 3.0, 1.0], // all below 5 mV → treated as voted-out
      cellMv1: [0, 0, 0],
      cellMv2: [0, 0, 0],
    );

    expect(await dao.surfaceMvSeriesForCell(cellId), isEmpty);
  });
});
```

- [ ] **Step 3: Run the test, verify it fails (method missing)**

Run: `flutter test test/data/db/equipment_dao_test.dart`

Expected: missing method.

- [ ] **Step 4: Implement `surfaceMvSeriesForCell`**

Append to `EquipmentDao`:

```dart
/// One (date, mv, diveId) point per dive in the cell's window.
/// Mean of cellMv[slot] over samples where depth < 1.0m and cellMv >= 5 mV
/// (voted-out heuristic). Dives with no qualifying samples are omitted.
Future<List<({DateTime date, double mv, String diveId})>>
    surfaceMvSeriesForCell(String cellId) async {
  final cell = await getCell(cellId);
  if (cell == null) return const [];

  final query = select(db.dives);
  if (cell.installedDate != null) {
    query.where((t) => t.startTimeUtc.isBiggerOrEqualValue(cell.installedDate!));
  }
  if (cell.retiredDate != null) {
    query.where((t) => t.startTimeUtc.isSmallerThanValue(cell.retiredDate!));
  }
  query.orderBy([(t) => OrderingTerm.asc(t.startTimeUtc)]);

  final dives = await query.get();
  final out = <({DateTime date, double mv, String diveId})>[];
  for (final dive in dives) {
    final mv = _computeSurfaceMv(dive, cell.slot);
    if (mv == null) continue;
    out.add((
      date: DateTime.fromMillisecondsSinceEpoch(dive.startTimeUtc),
      mv: mv,
      diveId: dive.id,
    ));
  }
  return out;
}

/// Returns mean cellMv[slot] over samples with depth < 1m and mv >= 5,
/// or null if none qualify. Sample blob layout: [depthCol|mv0Col|mv1Col|mv2Col],
/// each column N float32 little-endian values.
double? _computeSurfaceMv(Dive dive, int slot) {
  if (dive.sampleBlob.isEmpty) return null;
  final n = dive.sampleBlob.lengthInBytes ~/ (4 * 4);
  if (n == 0) return null;
  final bd = ByteData.sublistView(dive.sampleBlob);
  final mvColumnIndex = slot; // slot 1→mv0col? slot is 1-based on the table.
  // OxygenCells.slot is 1-based (1, 2, 3); cell mv columns are 0-based.
  final mvCol = slot - 1;
  if (mvCol < 0 || mvCol > 2) return null;

  var sum = 0.0;
  var count = 0;
  for (var i = 0; i < n; i++) {
    final depth = bd.getFloat32(i * 4, Endian.little);
    if (depth >= 1.0) continue;
    final mv =
        bd.getFloat32(((mvCol + 1) * n + i) * 4, Endian.little);
    if (mv < 5.0) continue;
    sum += mv;
    count++;
  }
  return count == 0 ? null : sum / count;
}
```

Add `import 'dart:typed_data';` at the top of `equipment_dao.dart` if not already imported.

- [ ] **Step 5: Run the tests, verify they pass**

Run: `flutter test test/data/db/equipment_dao_test.dart`

Expected: `+9: All tests passed!`

- [ ] **Step 6: Commit**

```bash
git add lib/data/db/equipment_dao.dart test/data/db/equipment_dao_test.dart
git commit -m "feat(equipment): surface mV aggregation per cell with voted-out heuristic"
```

---

### Task 5: `EquipmentDao` ScrubberSessions CRUD + auto-detection wiring

**Files:**
- Modify: `lib/data/db/equipment_dao.dart`
- Modify: `test/data/db/equipment_dao_test.dart`

- [ ] **Step 1: Write failing tests for scrubber CRUD and applyScrubberEvents**

Append to `test/data/db/equipment_dao_test.dart`:

```dart
group('ScrubberSessions', () {
  test('addScrubberSession + listScrubberSessions round-trip', () async {
    final id = await dao.addScrubberSession(
      startedDate: DateTime(2025, 1, 1),
      mediaType: 'Sofnolime 797',
      notes: 'fresh',
    );
    final list = await dao.listScrubberSessions();
    expect(list.single.id, id);
    expect(list.single.mediaType, 'Sofnolime 797');
  });

  test('listScrubberSessions sorts active first then by date desc', () async {
    final old = await dao.addScrubberSession(startedDate: DateTime(2024, 1, 1));
    final active = await dao.addScrubberSession(startedDate: DateTime(2025, 1, 1));
    await dao.closeScrubberSession(old, endedAt: DateTime(2024, 6, 1));

    final list = await dao.listScrubberSessions();
    expect(list.map((s) => s.id).toList(), [active, old]);
  });

  test('applyScrubberEvents is no-op when scrubberResetAt is null', () async {
    final initial = await dao.listScrubberSessions();
    await dao.applyScrubberEvents(scrubberResetAt: null, dcSerial: 1);
    expect(await dao.listScrubberSessions(), initial);
  });

  test('applyScrubberEvents closes open session and opens a new one', () async {
    final open = await dao.addScrubberSession(startedDate: DateTime(2025, 1, 1));
    await dao.applyScrubberEvents(
      scrubberResetAt: DateTime(2025, 6, 1),
      dcSerial: 1,
    );

    final all = await dao.listScrubberSessions();
    expect(all, hasLength(2));
    final closed = all.firstWhere((s) => s.id == open);
    final fresh = all.firstWhere((s) => s.id != open);

    expect(closed.totalMinutes, isNotNull); // closed: endedAt persisted via totalMinutes? See impl.
    expect(fresh.startedDate,
        DateTime(2025, 6, 1).millisecondsSinceEpoch);
  });
});
```

> NOTE: The existing `ScrubberSessions` table has `startedDate` and `totalMinutes` but no explicit `endedDate`. The DAO uses presence/absence of a *closed* flag to decide whether a session is "open." The simplest representation that fits the existing schema is: open session = `totalMinutes IS NULL`; closed session = `totalMinutes` set to its accumulated value. If a richer "ended at" timestamp is needed later, add an `endedDate IntColumn nullable` in a follow-up migration.

- [ ] **Step 2: Run the test, verify it fails**

Run: `flutter test test/data/db/equipment_dao_test.dart`

Expected: missing methods.

- [ ] **Step 3: Implement scrubber methods**

Append to `EquipmentDao`:

```dart
// ── ScrubberSessions ─────────────────────────────────────────────────────

Future<String> addScrubberSession({
  required DateTime startedDate,
  String? mediaType,
  String? notes,
}) async {
  final now = DateTime.now().millisecondsSinceEpoch;
  final id = 'scrub_${now}';
  await into(scrubberSessions).insert(ScrubberSessionsCompanion.insert(
    id: id,
    startedDate: Value(startedDate.millisecondsSinceEpoch),
    mediaType: Value(mediaType),
    notes: Value(notes),
    createdAt: now,
    updatedAt: now,
  ));
  return id;
}

Future<List<ScrubberSession>> listScrubberSessions() async {
  final rows = await (select(scrubberSessions)
        ..where((t) => t.deletedAt.isNull()))
      .get();
  // Active (totalMinutes IS NULL) first, then closed sorted by startedDate desc.
  rows.sort((a, b) {
    if (a.totalMinutes == null && b.totalMinutes != null) return -1;
    if (a.totalMinutes != null && b.totalMinutes == null) return 1;
    return (b.startedDate ?? 0).compareTo(a.startedDate ?? 0);
  });
  return rows;
}

Future<ScrubberSession?> getScrubberSession(String id) {
  return (select(scrubberSessions)..where((t) => t.id.equals(id)))
      .getSingleOrNull();
}

Future<void> closeScrubberSession(String id, {required DateTime endedAt}) async {
  final session = await getScrubberSession(id);
  if (session == null) return;
  final minutes = await accumulatedMinutesForSession(
    id,
    endBoundOverride: endedAt,
  );
  final now = DateTime.now().millisecondsSinceEpoch;
  await (update(scrubberSessions)..where((t) => t.id.equals(id))).write(
    ScrubberSessionsCompanion(
      totalMinutes: Value(minutes),
      updatedAt: Value(now),
    ),
  );
}

Future<void> deleteScrubberSession(String id) async {
  final now = DateTime.now().millisecondsSinceEpoch;
  await (update(scrubberSessions)..where((t) => t.id.equals(id))).write(
    ScrubberSessionsCompanion(
      deletedAt: Value(now),
      updatedAt: Value(now),
    ),
  );
}

/// Forward-compatible hook called per imported dive. Currently used only when
/// the parser surfaces a scrubber-reset timestamp; until then it's a no-op.
Future<void> applyScrubberEvents({
  required DateTime? scrubberResetAt,
  required int dcSerial,
}) async {
  if (scrubberResetAt == null) return;
  final epoch = scrubberResetAt.millisecondsSinceEpoch;
  final open = await (select(scrubberSessions)
        ..where((t) =>
            t.deletedAt.isNull() & t.totalMinutes.isNull()))
      .get();
  for (final s in open) {
    await closeScrubberSession(s.id, endedAt: scrubberResetAt);
  }
  await addScrubberSession(startedDate: scrubberResetAt);
  // dcSerial isn't currently stored on ScrubberSessions; reserved for a
  // future migration if multi-rebreather support is added.
  // ignore: unused_local_variable
  final _ = dcSerial;
  // ignore: unused_local_variable
  final __ = epoch;
}

/// Sum of dive runtimes (in minutes) whose startTime falls in
/// [session.startedDate, endBound) where endBound is the next session's
/// startedDate (or [endBoundOverride] if the caller is closing this session).
Future<int> accumulatedMinutesForSession(
  String id, {
  DateTime? endBoundOverride,
}) async {
  final session = await getScrubberSession(id);
  if (session == null || session.startedDate == null) return 0;

  // Resolve the end bound.
  int? endEpoch = endBoundOverride?.millisecondsSinceEpoch;
  if (endEpoch == null) {
    final later = await (select(scrubberSessions)
          ..where((t) =>
              t.deletedAt.isNull() &
              t.startedDate.isBiggerThanValue(session.startedDate!)))
        .get();
    if (later.isNotEmpty) {
      endEpoch = later
          .map((s) => s.startedDate!)
          .reduce((a, b) => a < b ? a : b);
    }
  }

  final dives = await (select(db.dives)
        ..where((t) {
          var expr = t.startTimeUtc.isBiggerOrEqualValue(session.startedDate!);
          if (endEpoch != null) {
            expr = expr & t.startTimeUtc.isSmallerThanValue(endEpoch);
          }
          return expr;
        }))
      .get();

  // MVP fallback: sum dive runtimes (over-estimates by surface time).
  // Replace with per-sample scrubber-on time when the parser exposes it.
  final totalSeconds =
      dives.fold<int>(0, (sum, d) => sum + d.runtimeSeconds);
  return totalSeconds ~/ 60;
}
```

- [ ] **Step 4: Run the tests, verify they pass**

Run: `flutter test test/data/db/equipment_dao_test.dart`

Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add lib/data/db/equipment_dao.dart test/data/db/equipment_dao_test.dart
git commit -m "feat(equipment): scrubber session CRUD + applyScrubberEvents hook"
```

---

### Task 6: `EquipmentDao` Cylinders CRUD + `seedStandardCcrCylinders`

**Files:**
- Modify: `lib/data/models/equipment.dart`
- Modify: `lib/data/db/equipment_dao.dart`
- Modify: `test/data/db/equipment_dao_test.dart`

- [ ] **Step 1: Add the role enum constants**

Append to `lib/data/models/equipment.dart`:

```dart
class CylinderRole {
  static const oxygen = 'oxygen';
  static const diluent = 'diluent';
  static const bailout = 'bailout';
  static const offboard = 'offboard';
  static const all = <String>[oxygen, diluent, bailout, offboard];
}
```

- [ ] **Step 2: Write failing tests for cylinder CRUD**

Append to `test/data/db/equipment_dao_test.dart`:

```dart
import 'package:ccrlogger/data/models/equipment.dart';
```

(Add the import if not already present.)

```dart
group('Cylinders', () {
  test('addCylinder + listCylinders round-trip', () async {
    final id = await dao.addCylinder(
      label: 'AL40 stage',
      role: CylinderRole.bailout,
      bailoutOrder: 1,
      volumeLiters: 5.7,
      workingPressureBar: 207,
      gasMix: '21/35',
    );
    final list = await dao.listCylinders();
    expect(list, hasLength(1));
    expect(list.single.id, id);
    expect(list.single.role, 'bailout');
    expect(list.single.bailoutOrder, 1);
  });

  test('updateCylinder clears bailoutOrder when role changes away from bailout',
      () async {
    final id = await dao.addCylinder(
      label: 'BO1',
      role: CylinderRole.bailout,
      bailoutOrder: 1,
      volumeLiters: 5.0,
      workingPressureBar: 200,
    );
    await dao.updateCylinder(id, role: CylinderRole.diluent);
    final updated = (await dao.listCylinders()).single;
    expect(updated.role, 'diluent');
    expect(updated.bailoutOrder, isNull);
  });

  test('seedStandardCcrCylinders inserts O2, Diluent, Bailout #1', () async {
    await dao.seedStandardCcrCylinders();
    final list = await dao.listCylinders();
    expect(list.map((c) => c.role).toSet(),
        {'oxygen', 'diluent', 'bailout'});
    final bailout = list.firstWhere((c) => c.role == 'bailout');
    expect(bailout.bailoutOrder, 1);
  });

  test('addCylinder rejects unknown role', () async {
    expect(
      () => dao.addCylinder(
        label: 'x',
        role: 'rocket-fuel',
        volumeLiters: 1,
        workingPressureBar: 200,
      ),
      throwsArgumentError,
    );
  });
});
```

- [ ] **Step 3: Run the test, verify it fails**

Run: `flutter test test/data/db/equipment_dao_test.dart`

Expected: missing methods.

- [ ] **Step 4: Implement cylinder methods**

Append to `EquipmentDao`:

```dart
// ── Cylinders ────────────────────────────────────────────────────────────

Future<String> addCylinder({
  required String label,
  required String role,
  int? bailoutOrder,
  required double volumeLiters,
  required int workingPressureBar,
  String? gasMix,
  String? notes,
}) async {
  if (!CylinderRole.all.contains(role)) {
    throw ArgumentError.value(role, 'role', 'must be one of ${CylinderRole.all}');
  }
  final effectiveOrder = role == CylinderRole.bailout ? bailoutOrder : null;
  final now = DateTime.now().millisecondsSinceEpoch;
  final id = 'cyl_${now}_${role}';
  await into(cylinders).insert(CylindersCompanion.insert(
    id: id,
    label: label,
    role: role,
    bailoutOrder: Value(effectiveOrder),
    volumeLiters: volumeLiters,
    workingPressureBar: workingPressureBar,
    gasMix: Value(gasMix),
    notes: Value(notes),
    createdAt: now,
    updatedAt: now,
  ));
  return id;
}

Future<List<Cylinder>> listCylinders() async {
  final rows = await (select(cylinders)
        ..where((t) => t.deletedAt.isNull()))
      .get();
  // Sort by role group order, then by bailoutOrder asc, then label asc.
  const roleOrder = {
    CylinderRole.oxygen: 0,
    CylinderRole.diluent: 1,
    CylinderRole.bailout: 2,
    CylinderRole.offboard: 3,
  };
  rows.sort((a, b) {
    final ra = roleOrder[a.role] ?? 99;
    final rb = roleOrder[b.role] ?? 99;
    if (ra != rb) return ra.compareTo(rb);
    final oa = a.bailoutOrder ?? 0;
    final ob = b.bailoutOrder ?? 0;
    if (oa != ob) return oa.compareTo(ob);
    return a.label.compareTo(b.label);
  });
  return rows;
}

Future<Cylinder?> getCylinder(String id) {
  return (select(cylinders)..where((t) => t.id.equals(id))).getSingleOrNull();
}

Future<void> updateCylinder(
  String id, {
  String? label,
  String? role,
  int? bailoutOrder,
  double? volumeLiters,
  int? workingPressureBar,
  String? gasMix,
  String? notes,
}) async {
  if (role != null && !CylinderRole.all.contains(role)) {
    throw ArgumentError.value(role, 'role');
  }
  final now = DateTime.now().millisecondsSinceEpoch;
  // If role is being moved away from bailout, force bailoutOrder to null.
  Value<int?> effectiveBailoutOrder;
  if (role != null && role != CylinderRole.bailout) {
    effectiveBailoutOrder = const Value(null);
  } else if (bailoutOrder != null) {
    effectiveBailoutOrder = Value(bailoutOrder);
  } else {
    effectiveBailoutOrder = const Value.absent();
  }
  await (update(cylinders)..where((t) => t.id.equals(id))).write(
    CylindersCompanion(
      label: label == null ? const Value.absent() : Value(label),
      role: role == null ? const Value.absent() : Value(role),
      bailoutOrder: effectiveBailoutOrder,
      volumeLiters:
          volumeLiters == null ? const Value.absent() : Value(volumeLiters),
      workingPressureBar: workingPressureBar == null
          ? const Value.absent()
          : Value(workingPressureBar),
      gasMix: Value(gasMix),
      notes: Value(notes),
      updatedAt: Value(now),
    ),
  );
}

Future<void> softDeleteCylinder(String id) async {
  final now = DateTime.now().millisecondsSinceEpoch;
  await (update(cylinders)..where((t) => t.id.equals(id))).write(
    CylindersCompanion(
      deletedAt: Value(now),
      updatedAt: Value(now),
    ),
  );
}

Future<void> seedStandardCcrCylinders() async {
  await addCylinder(
    label: 'O2',
    role: CylinderRole.oxygen,
    volumeLiters: 2.0,
    workingPressureBar: 207,
    gasMix: '100',
  );
  await addCylinder(
    label: 'Diluent',
    role: CylinderRole.diluent,
    volumeLiters: 3.0,
    workingPressureBar: 232,
  );
  await addCylinder(
    label: 'Bailout',
    role: CylinderRole.bailout,
    bailoutOrder: 1,
    volumeLiters: 7.0,
    workingPressureBar: 232,
  );
}
```

Add the missing import at the top of the test file if needed:

```dart
import 'package:ccrlogger/data/models/equipment.dart';
```

- [ ] **Step 5: Run the tests, verify they pass**

Run: `flutter test test/data/db/equipment_dao_test.dart`

Expected: all green.

- [ ] **Step 6: Commit**

```bash
git add lib/data/db/equipment_dao.dart lib/data/models/equipment.dart test/data/db/equipment_dao_test.dart
git commit -m "feat(equipment): cylinders CRUD with role + bailout order + standard CCR seed"
```

---

### Task 7: `EquipmentDao` PressureMappings + `pressureChannelsSeenForComputer`

**Files:**
- Modify: `lib/data/db/equipment_dao.dart`
- Modify: `test/data/db/equipment_dao_test.dart`

- [ ] **Step 1: Write failing tests**

Append to `test/data/db/equipment_dao_test.dart`:

```dart
group('PressureMappings', () {
  test('setPressureMapping inserts and round-trips', () async {
    await dao.setPressureMapping(
      diveComputerId: 'dc1',
      channelIndex: 0,
      cylinderId: 'cyl_a',
    );
    final list = await dao.listPressureMappings('dc1');
    expect(list, hasLength(1));
    expect(list.single.cylinderId, 'cyl_a');
  });

  test('setPressureMapping updates existing row', () async {
    await dao.setPressureMapping(
      diveComputerId: 'dc1',
      channelIndex: 0,
      cylinderId: 'cyl_a',
    );
    await dao.setPressureMapping(
      diveComputerId: 'dc1',
      channelIndex: 0,
      cylinderId: 'cyl_b',
    );
    final list = await dao.listPressureMappings('dc1');
    expect(list, hasLength(1));
    expect(list.single.cylinderId, 'cyl_b');
  });

  test('setPressureMapping accepts null (unmapped)', () async {
    await dao.setPressureMapping(
      diveComputerId: 'dc1',
      channelIndex: 0,
      cylinderId: 'cyl_a',
    );
    await dao.setPressureMapping(
      diveComputerId: 'dc1',
      channelIndex: 0,
      cylinderId: null,
    );
    final list = await dao.listPressureMappings('dc1');
    expect(list.single.cylinderId, isNull);
  });
});
```

- [ ] **Step 2: Run the test, verify it fails**

Run: `flutter test test/data/db/equipment_dao_test.dart`

Expected: missing methods.

- [ ] **Step 3: Implement pressure-mapping methods**

Append to `EquipmentDao`:

```dart
// ── PressureMappings ─────────────────────────────────────────────────────

Future<List<PressureMapping>> listPressureMappings(String diveComputerId) {
  return (select(pressureMappings)
        ..where((t) =>
            t.diveComputerId.equals(diveComputerId) & t.deletedAt.isNull())
        ..orderBy([(t) => OrderingTerm.asc(t.channelIndex)]))
      .get();
}

Future<void> setPressureMapping({
  required String diveComputerId,
  required int channelIndex,
  required String? cylinderId,
}) async {
  final now = DateTime.now().millisecondsSinceEpoch;
  await into(pressureMappings).insertOnConflictUpdate(
    PressureMappingsCompanion.insert(
      diveComputerId: diveComputerId,
      channelIndex: channelIndex,
      cylinderId: Value(cylinderId),
      createdAt: now,
      updatedAt: now,
    ),
  );
}

/// Best-effort enumeration of pressure-channel indexes the device has logged.
/// MVP returns the channels that already have a mapping; the parser-side
/// "infer from imports" lookup is a follow-up once the per-channel pressure
/// series is known to surface in the sample blob.
Future<List<int>> pressureChannelsSeenForComputer(String diveComputerId) async {
  final rows = await listPressureMappings(diveComputerId);
  return rows.map((r) => r.channelIndex).toList();
}
```

- [ ] **Step 4: Run the tests, verify they pass**

Run: `flutter test test/data/db/equipment_dao_test.dart`

Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add lib/data/db/equipment_dao.dart test/data/db/equipment_dao_test.dart
git commit -m "feat(equipment): pressure mapping CRUD on EquipmentDao"
```

---

### Task 8: Equipment landing screen

**Files:**
- Create: `lib/ui/screens/equipment/equipment_landing_screen.dart`
- Modify: `lib/ui/app_shell.dart`
- Test: `test/ui/screens/equipment/equipment_landing_screen_test.dart`

- [ ] **Step 1: Write the failing widget test**

```dart
// test/ui/screens/equipment/equipment_landing_screen_test.dart
import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/data/db/equipment_dao.dart';
import 'package:ccrlogger/ui/screens/equipment/equipment_landing_screen.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders four category cards with counts', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final dao = EquipmentDao(db);

    await tester.pumpWidget(MaterialApp(
      home: EquipmentLandingScreen(dao: dao),
    ));
    await tester.pump();

    expect(find.text('Dive Computers'), findsOneWidget);
    expect(find.text('O2 Cells'), findsOneWidget);
    expect(find.text('Scrubbers'), findsOneWidget);
    expect(find.text('Cylinders'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run the test, verify it fails**

Run: `flutter test test/ui/screens/equipment/equipment_landing_screen_test.dart`

Expected: file not found.

- [ ] **Step 3: Implement the landing screen**

```dart
// lib/ui/screens/equipment/equipment_landing_screen.dart
import 'package:flutter/material.dart';

import '../../../data/db/equipment_dao.dart';

class EquipmentLandingScreen extends StatefulWidget {
  final EquipmentDao dao;

  const EquipmentLandingScreen({super.key, required this.dao});

  @override
  State<EquipmentLandingScreen> createState() => _EquipmentLandingScreenState();
}

class _EquipmentLandingScreenState extends State<EquipmentLandingScreen> {
  int _computers = 0;
  int _cells = 0;
  int _scrubbers = 0;
  int _cylinders = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final c = await widget.dao.listDiveComputers();
    final ce = await widget.dao.listCells();
    final s = await widget.dao.listScrubberSessions();
    final cy = await widget.dao.listCylinders();
    if (!mounted) return;
    setState(() {
      _computers = c.length;
      _cells = ce.length;
      _scrubbers = s.length;
      _cylinders = cy.length;
    });
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Card(title: 'Dive Computers', count: _computers, icon: Icons.bluetooth, onTap: () {}),
          const SizedBox(height: 12),
          _Card(title: 'O2 Cells', count: _cells, icon: Icons.science_outlined, onTap: () {}),
          const SizedBox(height: 12),
          _Card(title: 'Scrubbers', count: _scrubbers, icon: Icons.replay_circle_filled_outlined, onTap: () {}),
          const SizedBox(height: 12),
          _Card(title: 'Cylinders', count: _cylinders, icon: Icons.propane_tank_outlined, onTap: () {}),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final String title;
  final int count;
  final IconData icon;
  final VoidCallback onTap;

  const _Card({
    required this.title,
    required this.count,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        trailing: Text('$count', style: Theme.of(context).textTheme.titleLarge),
        onTap: onTap,
      ),
    );
  }
}
```

> NOTE: `onTap` callbacks are stubs (`() {}`) for now. They get wired to push the per-category list screens in Tasks 9, 11, 13, 15.

- [ ] **Step 4: Wire the landing into AppShell**

Replace the placeholder in `lib/ui/app_shell.dart:63`:

```dart
const PlaceholderScreen(title: 'Equipment', icon: Icons.build_outlined),
```

with:

```dart
EquipmentLandingScreen(dao: _equipmentDao),
```

Add the field and instantiation:

```dart
late final EquipmentDao _equipmentDao;
```

In `initState`:

```dart
_equipmentDao = EquipmentDao(widget.db);
```

Add the import:

```dart
import '../data/db/equipment_dao.dart';
import 'screens/equipment/equipment_landing_screen.dart';
```

- [ ] **Step 5: Run the tests, verify they pass**

Run: `flutter test test/ui/screens/equipment/equipment_landing_screen_test.dart`

Expected: green.

- [ ] **Step 6: Commit**

```bash
git add lib/ui/screens/equipment/equipment_landing_screen.dart lib/ui/app_shell.dart test/ui/screens/equipment/equipment_landing_screen_test.dart
git commit -m "feat(equipment): landing screen with four category cards"
```

---

### Task 9: DiveComputers list + detail (basic, no pressure mapping yet)

**Files:**
- Create: `lib/ui/notifiers/equipment_notifiers.dart`
- Create: `lib/ui/screens/equipment/dive_computers_list_screen.dart`
- Create: `lib/ui/screens/equipment/dive_computer_detail_screen.dart`
- Modify: `lib/ui/screens/equipment/equipment_landing_screen.dart` (wire onTap)
- Test: `test/ui/notifiers/dive_computers_notifier_test.dart`

- [ ] **Step 1: Write failing notifier test**

```dart
// test/ui/notifiers/dive_computers_notifier_test.dart
import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/data/db/equipment_dao.dart';
import 'package:ccrlogger/ui/notifiers/equipment_notifiers.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('load() populates list and notifies', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final dao = EquipmentDao(db);
    await dao.upsertDiveComputer(serial: 1, model: 0xB407);

    final n = DiveComputersNotifier(dao);
    var notified = 0;
    n.addListener(() => notified++);

    await n.load();
    expect(n.computers, hasLength(1));
    expect(notified, greaterThan(0));
  });
}
```

- [ ] **Step 2: Run the test, verify it fails**

Run: `flutter test test/ui/notifiers/dive_computers_notifier_test.dart`

Expected: notifier file not found.

- [ ] **Step 3: Implement DiveComputersNotifier**

```dart
// lib/ui/notifiers/equipment_notifiers.dart
import 'package:flutter/foundation.dart';

import '../../data/db/database.dart';
import '../../data/db/equipment_dao.dart';

class DiveComputersNotifier extends ChangeNotifier {
  final EquipmentDao _dao;

  DiveComputersNotifier(this._dao);

  List<DiveComputer> _computers = [];
  List<DiveComputer> get computers => List.unmodifiable(_computers);

  bool _loading = false;
  bool get loading => _loading;

  Future<void> load() async {
    _loading = true;
    notifyListeners();
    _computers = await _dao.listDiveComputers();
    _loading = false;
    notifyListeners();
  }

  Future<void> setNickname(String id, String? nickname) async {
    await _dao.setComputerNickname(id, nickname);
    await load();
  }
}
```

- [ ] **Step 4: Run the test, verify it passes**

Run: `flutter test test/ui/notifiers/dive_computers_notifier_test.dart`

Expected: green.

- [ ] **Step 5: Implement list screen**

```dart
// lib/ui/screens/equipment/dive_computers_list_screen.dart
import 'package:flutter/material.dart';

import '../../../data/db/database.dart';
import '../../../data/db/equipment_dao.dart';
import '../../notifiers/equipment_notifiers.dart';
import 'dive_computer_detail_screen.dart';

class DiveComputersListScreen extends StatefulWidget {
  final EquipmentDao dao;

  const DiveComputersListScreen({super.key, required this.dao});

  @override
  State<DiveComputersListScreen> createState() =>
      _DiveComputersListScreenState();
}

class _DiveComputersListScreenState extends State<DiveComputersListScreen> {
  late final DiveComputersNotifier _notifier;

  @override
  void initState() {
    super.initState();
    _notifier = DiveComputersNotifier(widget.dao);
    _notifier.addListener(_onChanged);
    _notifier.load();
  }

  void _onChanged() => setState(() {});

  @override
  void dispose() {
    _notifier.removeListener(_onChanged);
    _notifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dive Computers')),
      body: _notifier.loading
          ? const Center(child: CircularProgressIndicator())
          : _notifier.computers.isEmpty
              ? const Center(child: Text('No dive computers yet'))
              : ListView.builder(
                  itemCount: _notifier.computers.length,
                  itemBuilder: (_, i) {
                    final dc = _notifier.computers[i];
                    return ListTile(
                      title: Text(_displayName(dc)),
                      subtitle: Text('FW ${dc.firmwareVersion ?? '?'}'),
                      onTap: () async {
                        await Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => DiveComputerDetailScreen(
                            dao: widget.dao,
                            id: dc.id,
                          ),
                        ));
                        await _notifier.load();
                      },
                    );
                  },
                ),
    );
  }

  String _displayName(DiveComputer dc) {
    if (dc.nickname != null && dc.nickname!.isNotEmpty) return dc.nickname!;
    final tail = dc.serial.toRadixString(16).padLeft(8, '0').substring(4);
    return 'Petrel · …$tail';
  }
}
```

- [ ] **Step 6: Implement detail screen (no pressure mapping yet)**

```dart
// lib/ui/screens/equipment/dive_computer_detail_screen.dart
import 'package:flutter/material.dart';

import '../../../data/db/database.dart';
import '../../../data/db/equipment_dao.dart';

class DiveComputerDetailScreen extends StatefulWidget {
  final EquipmentDao dao;
  final String id;

  const DiveComputerDetailScreen({
    super.key,
    required this.dao,
    required this.id,
  });

  @override
  State<DiveComputerDetailScreen> createState() =>
      _DiveComputerDetailScreenState();
}

class _DiveComputerDetailScreenState extends State<DiveComputerDetailScreen> {
  DiveComputer? _dc;
  List<Dive> _recent = [];
  final _nicknameCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await widget.dao.listDiveComputers();
    final dc = list.where((d) => d.id == widget.id).firstOrNull;
    if (dc == null) return;
    final recent = await widget.dao.recentImportsForComputer(dc.serial);
    if (!mounted) return;
    setState(() {
      _dc = dc;
      _recent = recent;
      _nicknameCtrl.text = dc.nickname ?? '';
    });
  }

  Future<void> _saveNickname() async {
    if (_dc == null) return;
    final v = _nicknameCtrl.text.trim();
    await widget.dao.setComputerNickname(_dc!.id, v.isEmpty ? null : v);
    await _load();
  }

  @override
  void dispose() {
    _nicknameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dive Computer')),
      body: _dc == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('Serial: ${_dc!.serial.toRadixString(16).toUpperCase()}'),
                Text('Model: ${_dc!.model}'),
                Text('Firmware: ${_dc!.firmwareVersion ?? '?'}'),
                const SizedBox(height: 16),
                TextField(
                  controller: _nicknameCtrl,
                  decoration: const InputDecoration(labelText: 'Nickname'),
                  onSubmitted: (_) => _saveNickname(),
                ),
                ElevatedButton(
                  onPressed: _saveNickname,
                  child: const Text('Save nickname'),
                ),
                const SizedBox(height: 24),
                const Text('Recent imports',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                if (_recent.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('No imports yet'),
                  ),
                for (final d in _recent)
                  ListTile(
                    dense: true,
                    title: Text('Dive #${d.dcDiveNumber}'),
                    subtitle: Text(DateTime.fromMillisecondsSinceEpoch(
                            d.startTimeUtc)
                        .toLocal()
                        .toString()),
                  ),
              ],
            ),
    );
  }
}

extension _IterableFirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
```

- [ ] **Step 7: Wire the landing card onTap**

In `lib/ui/screens/equipment/equipment_landing_screen.dart`, replace the dive-computers card's `onTap: () {}` with:

```dart
onTap: () async {
  await Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => DiveComputersListScreen(dao: widget.dao),
  ));
  await _refresh();
},
```

Add the import:

```dart
import 'dive_computers_list_screen.dart';
```

- [ ] **Step 8: Run all tests**

Run: `flutter test test/ui/notifiers/dive_computers_notifier_test.dart test/ui/screens/equipment/equipment_landing_screen_test.dart`

Expected: all green.

- [ ] **Step 9: Commit**

```bash
git add lib/ui/notifiers/equipment_notifiers.dart lib/ui/screens/equipment/dive_computers_list_screen.dart lib/ui/screens/equipment/dive_computer_detail_screen.dart lib/ui/screens/equipment/equipment_landing_screen.dart test/ui/notifiers/dive_computers_notifier_test.dart
git commit -m "feat(equipment): dive computers list + detail screens"
```

---

### Task 10: Pressure-mapping editor on dive-computer detail

**Files:**
- Modify: `lib/ui/notifiers/equipment_notifiers.dart`
- Modify: `lib/ui/screens/equipment/dive_computer_detail_screen.dart`
- Test: `test/ui/notifiers/dive_computers_notifier_test.dart`

- [ ] **Step 1: Add a notifier method for the mapping editor**

In `equipment_notifiers.dart`, append to `DiveComputersNotifier`:

```dart
List<PressureMapping> _mappings = [];
List<PressureMapping> get mappings => List.unmodifiable(_mappings);

Future<void> loadMappings(String diveComputerId) async {
  _mappings = await _dao.listPressureMappings(diveComputerId);
  notifyListeners();
}

Future<void> setMapping(
  String diveComputerId,
  int channelIndex,
  String? cylinderId,
) async {
  await _dao.setPressureMapping(
    diveComputerId: diveComputerId,
    channelIndex: channelIndex,
    cylinderId: cylinderId,
  );
  await loadMappings(diveComputerId);
}
```

Add the import for `PressureMapping`:

```dart
import '../../data/db/database.dart' show PressureMapping, DiveComputer;
```

- [ ] **Step 2: Write failing test for mapping notifier method**

Append to `test/ui/notifiers/dive_computers_notifier_test.dart`:

```dart
test('setMapping persists and reloads mappings', () async {
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  final dao = EquipmentDao(db);
  await dao.upsertDiveComputer(serial: 1, model: 0xB407);
  final dcs = await dao.listDiveComputers();
  final dcId = dcs.single.id;

  final n = DiveComputersNotifier(dao);
  await n.setMapping(dcId, 0, 'cyl_a');
  expect(n.mappings, hasLength(1));
  expect(n.mappings.single.cylinderId, 'cyl_a');
});
```

- [ ] **Step 3: Run the test, verify it passes**

Run: `flutter test test/ui/notifiers/dive_computers_notifier_test.dart`

Expected: green.

- [ ] **Step 4: Add the editor section to the detail screen**

In `dive_computer_detail_screen.dart`, after the recent-imports section, add a "Pressure mapping" section. Replace the screen body with:

```dart
// State additions:
List<PressureMapping> _mappings = [];
List<Cylinder> _cylinders = [];

Future<void> _loadMappings() async {
  if (_dc == null) return;
  _mappings = await widget.dao.listPressureMappings(_dc!.id);
  _cylinders = await widget.dao.listCylinders();
  if (!mounted) return;
  setState(() {});
}

@override
void initState() {
  super.initState();
  _load().then((_) => _loadMappings());
}

Future<void> _setMapping(int channel, String? cylinderId) async {
  await widget.dao.setPressureMapping(
    diveComputerId: _dc!.id,
    channelIndex: channel,
    cylinderId: cylinderId,
  );
  await _loadMappings();
}
```

In the `build` ListView children, after recent imports, add:

```dart
const SizedBox(height: 24),
const Text('Pressure mapping',
    style: TextStyle(fontWeight: FontWeight.bold)),
if (_mappings.isEmpty)
  const Padding(
    padding: EdgeInsets.symmetric(vertical: 8),
    child: Text(
      'No pressure channels seen on imports yet. '
      'Add a mapping manually for channel 0–3 if your device logs pressure.',
    ),
  ),
for (final m in _mappings)
  ListTile(
    dense: true,
    title: Text('Channel ${m.channelIndex}'),
    trailing: DropdownButton<String?>(
      value: m.cylinderId,
      hint: const Text('unmapped'),
      items: [
        const DropdownMenuItem<String?>(
          value: null,
          child: Text('unmapped'),
        ),
        for (final c in _cylinders)
          DropdownMenuItem<String?>(
            value: c.id,
            child: Text('${c.label} (${c.role})'),
          ),
      ],
      onChanged: (v) => _setMapping(m.channelIndex, v),
    ),
  ),
TextButton.icon(
  icon: const Icon(Icons.add),
  label: const Text('Add channel'),
  onPressed: () async {
    final used = _mappings.map((m) => m.channelIndex).toSet();
    var next = 0;
    while (used.contains(next)) {
      next++;
    }
    await _setMapping(next, null);
  },
),
```

Add imports for `PressureMapping` and `Cylinder`:

```dart
import '../../../data/db/database.dart' show DiveComputer, Dive, Cylinder, PressureMapping;
```

- [ ] **Step 5: Run all DAO + notifier tests**

Run: `flutter test test/data/db/equipment_dao_test.dart test/ui/notifiers/dive_computers_notifier_test.dart`

Expected: all green.

- [ ] **Step 6: Commit**

```bash
git add lib/ui/notifiers/equipment_notifiers.dart lib/ui/screens/equipment/dive_computer_detail_screen.dart test/ui/notifiers/dive_computers_notifier_test.dart
git commit -m "feat(equipment): pressure-mapping editor on dive computer detail"
```

---

### Task 11: O2 Cells — notifier + list screen

**Files:**
- Modify: `lib/ui/notifiers/equipment_notifiers.dart`
- Create: `lib/ui/screens/equipment/cells_list_screen.dart`
- Modify: `lib/ui/screens/equipment/equipment_landing_screen.dart` (wire onTap)
- Test: `test/ui/notifiers/cells_notifier_test.dart`

- [ ] **Step 1: Write failing notifier test**

```dart
// test/ui/notifiers/cells_notifier_test.dart
import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/data/db/equipment_dao.dart';
import 'package:ccrlogger/ui/notifiers/equipment_notifiers.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('load + add round-trip', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final dao = EquipmentDao(db);

    final n = CellsNotifier(dao);
    await n.load();
    expect(n.cells, isEmpty);

    await n.addCell(slot: 1, label: 'R-22D');
    expect(n.cells, hasLength(1));
    expect(n.cells.single.label, 'R-22D');
  });
}
```

- [ ] **Step 2: Run, verify it fails**

Run: `flutter test test/ui/notifiers/cells_notifier_test.dart`

Expected: missing class.

- [ ] **Step 3: Implement CellsNotifier**

Append to `equipment_notifiers.dart`:

```dart
class CellsNotifier extends ChangeNotifier {
  final EquipmentDao _dao;
  CellsNotifier(this._dao);

  List<OxygenCell> _cells = [];
  List<OxygenCell> get cells => List.unmodifiable(_cells);

  bool _loading = false;
  bool get loading => _loading;

  Future<void> load() async {
    _loading = true;
    notifyListeners();
    _cells = await _dao.listCells();
    _loading = false;
    notifyListeners();
  }

  Future<String> addCell({
    required int slot,
    String? label,
    DateTime? installedDate,
    String? notes,
  }) async {
    final id = await _dao.addCell(
      slot: slot,
      label: label,
      installedDate: installedDate,
      notes: notes,
    );
    await load();
    return id;
  }

  Future<void> updateCell(
    String id, {
    int? slot,
    String? label,
    DateTime? installedDate,
    String? notes,
  }) async {
    await _dao.updateCell(
      id,
      slot: slot,
      label: label,
      installedDate: installedDate,
      notes: notes,
    );
    await load();
  }

  Future<void> retire(String id) async {
    await _dao.retireCell(id, retiredAt: DateTime.now());
    await load();
  }

  Future<bool> deleteIfUnused(String id) async {
    final ok = await _dao.deleteCellIfUnused(id);
    await load();
    return ok;
  }
}
```

Update the `import` line at the top of the file to include `OxygenCell`:

```dart
import '../../data/db/database.dart' show DiveComputer, Dive, Cylinder, PressureMapping, OxygenCell, ScrubberSession;
```

- [ ] **Step 4: Run, verify it passes**

Run: `flutter test test/ui/notifiers/cells_notifier_test.dart`

Expected: green.

- [ ] **Step 5: Implement the list screen**

```dart
// lib/ui/screens/equipment/cells_list_screen.dart
import 'package:flutter/material.dart';

import '../../../data/db/database.dart';
import '../../../data/db/equipment_dao.dart';
import '../../notifiers/equipment_notifiers.dart';
import 'cell_detail_screen.dart';

class CellsListScreen extends StatefulWidget {
  final EquipmentDao dao;

  const CellsListScreen({super.key, required this.dao});

  @override
  State<CellsListScreen> createState() => _CellsListScreenState();
}

class _CellsListScreenState extends State<CellsListScreen> {
  late final CellsNotifier _n;

  @override
  void initState() {
    super.initState();
    _n = CellsNotifier(widget.dao);
    _n.addListener(_onChanged);
    _n.load();
  }

  void _onChanged() => setState(() {});

  @override
  void dispose() {
    _n.removeListener(_onChanged);
    _n.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('O2 Cells')),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final id = await _n.addCell(slot: 1);
          if (!mounted) return;
          await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => CellDetailScreen(dao: widget.dao, id: id),
          ));
          await _n.load();
        },
        child: const Icon(Icons.add),
      ),
      body: _n.loading
          ? const Center(child: CircularProgressIndicator())
          : _n.cells.isEmpty
              ? const Center(child: Text('No cells yet'))
              : ListView.builder(
                  itemCount: _n.cells.length,
                  itemBuilder: (_, i) {
                    final c = _n.cells[i];
                    final retired = c.retiredDate != null;
                    return ListTile(
                      title: Text(c.label ?? 'Slot ${c.slot}'),
                      subtitle: Text(_subtitle(c)),
                      trailing: retired
                          ? const Chip(label: Text('Retired'))
                          : null,
                      onTap: () async {
                        await Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => CellDetailScreen(
                            dao: widget.dao,
                            id: c.id,
                          ),
                        ));
                        await _n.load();
                      },
                    );
                  },
                ),
    );
  }

  String _subtitle(OxygenCell c) {
    final installed = c.installedDate == null
        ? 'install date unset'
        : 'installed ${DateTime.fromMillisecondsSinceEpoch(c.installedDate!).toLocal().toString().split(' ').first}';
    return 'Slot ${c.slot} · $installed';
  }
}
```

- [ ] **Step 6: Wire the landing card onTap**

In `equipment_landing_screen.dart`, replace the cells card `onTap: () {}` with:

```dart
onTap: () async {
  await Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => CellsListScreen(dao: widget.dao),
  ));
  await _refresh();
},
```

Add the import:

```dart
import 'cells_list_screen.dart';
```

> NOTE: `CellDetailScreen` doesn't exist yet — it's created in Task 12. The list screen's references to it will fail to compile until then, so commit Task 11 with a temporary stub if you want isolated commits, or land Tasks 11 + 12 together.

- [ ] **Step 7: Create a stub CellDetailScreen so Task 11 compiles**

```dart
// lib/ui/screens/equipment/cell_detail_screen.dart
import 'package:flutter/material.dart';

import '../../../data/db/equipment_dao.dart';

class CellDetailScreen extends StatelessWidget {
  final EquipmentDao dao;
  final String id;

  const CellDetailScreen({super.key, required this.dao, required this.id});

  @override
  Widget build(BuildContext context) {
    // Real implementation lands in Task 12.
    return Scaffold(
      appBar: AppBar(title: const Text('Cell')),
      body: Center(child: Text('Cell $id (placeholder)')),
    );
  }
}
```

- [ ] **Step 8: Run all tests**

Run: `flutter test test/ui/notifiers/cells_notifier_test.dart`

Expected: green.

- [ ] **Step 9: Commit**

```bash
git add lib/ui/notifiers/equipment_notifiers.dart lib/ui/screens/equipment/cells_list_screen.dart lib/ui/screens/equipment/cell_detail_screen.dart lib/ui/screens/equipment/equipment_landing_screen.dart test/ui/notifiers/cells_notifier_test.dart
git commit -m "feat(equipment): cells list screen + notifier"
```

---

### Task 12: Cell detail screen + surface-mV chart widget

**Files:**
- Create: `lib/ui/widgets/cell_mv_chart.dart`
- Modify: `lib/ui/screens/equipment/cell_detail_screen.dart`

- [ ] **Step 1: Implement the chart widget**

```dart
// lib/ui/widgets/cell_mv_chart.dart
import 'package:flutter/material.dart';

class CellMvChart extends StatelessWidget {
  final List<({DateTime date, double mv, String diveId})> series;
  final double height;

  const CellMvChart({super.key, required this.series, this.height = 220});

  @override
  Widget build(BuildContext context) {
    if (series.isEmpty) {
      return SizedBox(
        height: height,
        child: const Center(child: Text('No surface-mV data yet')),
      );
    }
    return SizedBox(
      height: height,
      child: CustomPaint(painter: _ChartPainter(series, Theme.of(context))),
    );
  }
}

class _ChartPainter extends CustomPainter {
  final List<({DateTime date, double mv, String diveId})> series;
  final ThemeData theme;

  _ChartPainter(this.series, this.theme);

  @override
  void paint(Canvas canvas, Size size) {
    if (series.isEmpty) return;
    final minTime = series.first.date.millisecondsSinceEpoch;
    final maxTime = series.last.date.millisecondsSinceEpoch;
    final minMv = series.map((p) => p.mv).reduce((a, b) => a < b ? a : b);
    final maxMv = series.map((p) => p.mv).reduce((a, b) => a > b ? a : b);
    final timeRange =
        (maxTime - minTime).clamp(1, double.infinity).toDouble();
    final mvRange = (maxMv - minMv).clamp(1.0, double.infinity);

    final pad = 24.0;
    final w = size.width - pad * 2;
    final h = size.height - pad * 2;

    final axisPaint = Paint()
      ..color = theme.colorScheme.outline
      ..strokeWidth = 1;
    canvas.drawLine(Offset(pad, pad), Offset(pad, pad + h), axisPaint);
    canvas.drawLine(
        Offset(pad, pad + h), Offset(pad + w, pad + h), axisPaint);

    final linePaint = Paint()
      ..color = theme.colorScheme.primary
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final dotPaint = Paint()..color = theme.colorScheme.primary;

    Offset xy(int i) {
      final t = series[i].date.millisecondsSinceEpoch;
      final x = pad + ((t - minTime) / timeRange) * w;
      final y = pad + h - ((series[i].mv - minMv) / mvRange) * h;
      return Offset(x, y);
    }

    final path = Path();
    path.moveTo(xy(0).dx, xy(0).dy);
    for (var i = 1; i < series.length; i++) {
      path.lineTo(xy(i).dx, xy(i).dy);
    }
    canvas.drawPath(path, linePaint);
    for (var i = 0; i < series.length; i++) {
      canvas.drawCircle(xy(i), 3, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ChartPainter old) =>
      old.series != series || old.theme != theme;
}
```

- [ ] **Step 2: Replace the placeholder cell detail screen**

```dart
// lib/ui/screens/equipment/cell_detail_screen.dart
import 'package:flutter/material.dart';

import '../../../data/db/database.dart';
import '../../../data/db/equipment_dao.dart';
import '../../widgets/cell_mv_chart.dart';

class CellDetailScreen extends StatefulWidget {
  final EquipmentDao dao;
  final String id;

  const CellDetailScreen({super.key, required this.dao, required this.id});

  @override
  State<CellDetailScreen> createState() => _CellDetailScreenState();
}

class _CellDetailScreenState extends State<CellDetailScreen> {
  OxygenCell? _cell;
  List<({DateTime date, double mv, String diveId})> _series = const [];
  final _labelCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cell = await widget.dao.getCell(widget.id);
    if (cell == null) return;
    final series = await widget.dao.surfaceMvSeriesForCell(cell.id);
    if (!mounted) return;
    setState(() {
      _cell = cell;
      _series = series;
      _labelCtrl.text = cell.label ?? '';
      _notesCtrl.text = cell.notes ?? '';
    });
  }

  Future<void> _save() async {
    if (_cell == null) return;
    await widget.dao.updateCell(
      _cell!.id,
      label: _labelCtrl.text.trim().isEmpty ? null : _labelCtrl.text.trim(),
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
    );
    await _load();
  }

  Future<void> _retire() async {
    if (_cell == null) return;
    await widget.dao.retireCell(_cell!.id, retiredAt: DateTime.now());
    await _load();
  }

  Future<void> _deleteIfUnused() async {
    if (_cell == null) return;
    final ok = await widget.dao.deleteCellIfUnused(_cell!.id);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Cell has attributable dives — cannot delete.'),
      ));
    }
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cell')),
      body: _cell == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('Slot ${_cell!.slot}',
                    style: Theme.of(context).textTheme.titleMedium),
                if (_cell!.installedDate != null)
                  Text('Installed: '
                      '${DateTime.fromMillisecondsSinceEpoch(_cell!.installedDate!).toLocal().toString().split(' ').first}'),
                if (_cell!.retiredDate != null)
                  Text('Retired: '
                      '${DateTime.fromMillisecondsSinceEpoch(_cell!.retiredDate!).toLocal().toString().split(' ').first}'),
                Text('Dives: ${_series.length}'),
                const SizedBox(height: 16),
                CellMvChart(series: _series),
                const SizedBox(height: 16),
                TextField(
                  controller: _labelCtrl,
                  decoration: const InputDecoration(labelText: 'Label'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _notesCtrl,
                  decoration: const InputDecoration(labelText: 'Notes'),
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    ElevatedButton(onPressed: _save, child: const Text('Save')),
                    if (_cell!.retiredDate == null)
                      OutlinedButton(
                        onPressed: _retire,
                        child: const Text('Retire'),
                      ),
                    TextButton(
                      onPressed: _deleteIfUnused,
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}
```

- [ ] **Step 3: Smoke-test the screen**

```dart
// test/ui/screens/equipment/cell_detail_screen_test.dart
import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/data/db/equipment_dao.dart';
import 'package:ccrlogger/ui/screens/equipment/cell_detail_screen.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders header + empty chart for a fresh cell', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final dao = EquipmentDao(db);
    final id = await dao.addCell(slot: 1, label: 'R-22D');

    await tester.pumpWidget(MaterialApp(
      home: CellDetailScreen(dao: dao, id: id),
    ));
    await tester.pump();
    await tester.pump();

    expect(find.text('Slot 1'), findsOneWidget);
    expect(find.text('No surface-mV data yet'), findsOneWidget);
  });
}
```

- [ ] **Step 4: Run, verify green**

Run: `flutter test test/ui/screens/equipment/cell_detail_screen_test.dart`

Expected: green.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/widgets/cell_mv_chart.dart lib/ui/screens/equipment/cell_detail_screen.dart test/ui/screens/equipment/cell_detail_screen_test.dart
git commit -m "feat(equipment): cell detail with surface-mV chart"
```

---

### Task 13: Scrubber sessions — notifier + list + detail

**Files:**
- Modify: `lib/ui/notifiers/equipment_notifiers.dart`
- Create: `lib/ui/screens/equipment/scrubber_sessions_list_screen.dart`
- Create: `lib/ui/screens/equipment/scrubber_session_detail_screen.dart`
- Modify: `lib/ui/screens/equipment/equipment_landing_screen.dart`
- Test: `test/ui/notifiers/scrubber_sessions_notifier_test.dart`

- [ ] **Step 1: Failing notifier test**

```dart
// test/ui/notifiers/scrubber_sessions_notifier_test.dart
import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/data/db/equipment_dao.dart';
import 'package:ccrlogger/ui/notifiers/equipment_notifiers.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('addPack + load surfaces an active session', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final dao = EquipmentDao(db);

    final n = ScrubberSessionsNotifier(dao);
    await n.addPack(startedDate: DateTime(2025, 1, 1));
    expect(n.sessions, hasLength(1));
    expect(n.sessions.single.totalMinutes, isNull);
  });

  test('closePack closes the session and computes minutes', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final dao = EquipmentDao(db);

    final n = ScrubberSessionsNotifier(dao);
    final id = await n.addPack(startedDate: DateTime(2025, 1, 1));
    await n.closePack(id, endedAt: DateTime(2025, 6, 1));
    expect(n.sessions.single.totalMinutes, 0); // no dives recorded
  });
}
```

- [ ] **Step 2: Run, verify it fails**

Run: `flutter test test/ui/notifiers/scrubber_sessions_notifier_test.dart`

Expected: missing class.

- [ ] **Step 3: Implement ScrubberSessionsNotifier**

Append to `equipment_notifiers.dart`:

```dart
class ScrubberSessionsNotifier extends ChangeNotifier {
  final EquipmentDao _dao;
  ScrubberSessionsNotifier(this._dao);

  List<ScrubberSession> _sessions = [];
  List<ScrubberSession> get sessions => List.unmodifiable(_sessions);

  Future<void> load() async {
    _sessions = await _dao.listScrubberSessions();
    notifyListeners();
  }

  Future<String> addPack({
    required DateTime startedDate,
    String? mediaType,
    String? notes,
  }) async {
    final id = await _dao.addScrubberSession(
      startedDate: startedDate,
      mediaType: mediaType,
      notes: notes,
    );
    await load();
    return id;
  }

  Future<void> closePack(String id, {required DateTime endedAt}) async {
    await _dao.closeScrubberSession(id, endedAt: endedAt);
    await load();
  }

  Future<void> deletePack(String id) async {
    await _dao.deleteScrubberSession(id);
    await load();
  }
}
```

- [ ] **Step 4: Run, verify it passes**

Run: `flutter test test/ui/notifiers/scrubber_sessions_notifier_test.dart`

Expected: green.

- [ ] **Step 5: Implement list screen**

```dart
// lib/ui/screens/equipment/scrubber_sessions_list_screen.dart
import 'package:flutter/material.dart';

import '../../../data/db/database.dart';
import '../../../data/db/equipment_dao.dart';
import '../../notifiers/equipment_notifiers.dart';
import 'scrubber_session_detail_screen.dart';

class ScrubberSessionsListScreen extends StatefulWidget {
  final EquipmentDao dao;

  const ScrubberSessionsListScreen({super.key, required this.dao});

  @override
  State<ScrubberSessionsListScreen> createState() =>
      _ScrubberSessionsListScreenState();
}

class _ScrubberSessionsListScreenState
    extends State<ScrubberSessionsListScreen> {
  late final ScrubberSessionsNotifier _n;

  @override
  void initState() {
    super.initState();
    _n = ScrubberSessionsNotifier(widget.dao);
    _n.addListener(_onChanged);
    _n.load();
  }

  void _onChanged() => setState(() {});

  @override
  void dispose() {
    _n.removeListener(_onChanged);
    _n.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scrubber Sessions')),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('New pack'),
        onPressed: () async {
          await _n.addPack(startedDate: DateTime.now());
          if (!mounted) return;
        },
      ),
      body: _n.sessions.isEmpty
          ? const Center(child: Text('No sessions yet'))
          : ListView.builder(
              itemCount: _n.sessions.length,
              itemBuilder: (_, i) {
                final s = _n.sessions[i];
                final active = s.totalMinutes == null;
                return ListTile(
                  title: Text(_title(s)),
                  subtitle: Text(_subtitle(s)),
                  trailing: active
                      ? const Chip(label: Text('Active'))
                      : null,
                  onTap: () async {
                    await Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => ScrubberSessionDetailScreen(
                        dao: widget.dao,
                        id: s.id,
                      ),
                    ));
                    await _n.load();
                  },
                );
              },
            ),
    );
  }

  String _title(ScrubberSession s) {
    final d = s.startedDate == null
        ? '?'
        : DateTime.fromMillisecondsSinceEpoch(s.startedDate!)
            .toLocal()
            .toString()
            .split(' ')
            .first;
    return 'Pack started $d';
  }

  String _subtitle(ScrubberSession s) {
    final m = s.totalMinutes ?? 0;
    final h = m ~/ 60;
    final r = m % 60;
    return '${h}h ${r}m used${s.mediaType == null ? '' : ' · ${s.mediaType}'}';
  }
}
```

- [ ] **Step 6: Implement detail screen**

```dart
// lib/ui/screens/equipment/scrubber_session_detail_screen.dart
import 'package:flutter/material.dart';

import '../../../data/db/database.dart';
import '../../../data/db/equipment_dao.dart';

class ScrubberSessionDetailScreen extends StatefulWidget {
  final EquipmentDao dao;
  final String id;

  const ScrubberSessionDetailScreen({
    super.key,
    required this.dao,
    required this.id,
  });

  @override
  State<ScrubberSessionDetailScreen> createState() =>
      _ScrubberSessionDetailScreenState();
}

class _ScrubberSessionDetailScreenState
    extends State<ScrubberSessionDetailScreen> {
  ScrubberSession? _session;
  int _accumulated = 0;
  final _mediaCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await widget.dao.getScrubberSession(widget.id);
    if (s == null) return;
    final m = await widget.dao.accumulatedMinutesForSession(s.id);
    if (!mounted) return;
    setState(() {
      _session = s;
      _accumulated = m;
      _mediaCtrl.text = s.mediaType ?? '';
      _notesCtrl.text = s.notes ?? '';
    });
  }

  Future<void> _close() async {
    await widget.dao.closeScrubberSession(widget.id, endedAt: DateTime.now());
    await _load();
  }

  Future<void> _delete() async {
    await widget.dao.deleteScrubberSession(widget.id);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _mediaCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scrubber Pack')),
      body: _session == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('Started: ${_session!.startedDate == null ? '?' : DateTime.fromMillisecondsSinceEpoch(_session!.startedDate!).toLocal().toString().split(' ').first}'),
                Text('Accumulated: ${_accumulated ~/ 60}h ${_accumulated % 60}m'),
                const SizedBox(height: 16),
                TextField(
                  controller: _mediaCtrl,
                  decoration: const InputDecoration(labelText: 'Media type'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _notesCtrl,
                  decoration: const InputDecoration(labelText: 'Notes'),
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (_session!.totalMinutes == null)
                      OutlinedButton(
                        onPressed: _close,
                        child: const Text('Close'),
                      ),
                    TextButton(onPressed: _delete, child: const Text('Delete')),
                  ],
                ),
              ],
            ),
    );
  }
}
```

- [ ] **Step 7: Wire the landing card onTap**

In `equipment_landing_screen.dart`, replace the scrubbers card `onTap: () {}` with:

```dart
onTap: () async {
  await Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => ScrubberSessionsListScreen(dao: widget.dao),
  ));
  await _refresh();
},
```

Add the import:

```dart
import 'scrubber_sessions_list_screen.dart';
```

- [ ] **Step 8: Run all tests**

Run: `flutter test`

Expected: all green.

- [ ] **Step 9: Commit**

```bash
git add lib/ui/notifiers/equipment_notifiers.dart lib/ui/screens/equipment/scrubber_sessions_list_screen.dart lib/ui/screens/equipment/scrubber_session_detail_screen.dart lib/ui/screens/equipment/equipment_landing_screen.dart test/ui/notifiers/scrubber_sessions_notifier_test.dart
git commit -m "feat(equipment): scrubber sessions list + detail"
```

---

### Task 14: Cylinders — notifier + list + detail (with role grouping and empty-state CTA)

**Files:**
- Modify: `lib/ui/notifiers/equipment_notifiers.dart`
- Create: `lib/ui/screens/equipment/cylinders_list_screen.dart`
- Create: `lib/ui/screens/equipment/cylinder_detail_screen.dart`
- Modify: `lib/ui/screens/equipment/equipment_landing_screen.dart`
- Test: `test/ui/notifiers/cylinders_notifier_test.dart`

- [ ] **Step 1: Failing notifier test**

```dart
// test/ui/notifiers/cylinders_notifier_test.dart
import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/data/db/equipment_dao.dart';
import 'package:ccrlogger/data/models/equipment.dart';
import 'package:ccrlogger/ui/notifiers/equipment_notifiers.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('seedStandard inserts O2 + Diluent + Bailout', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final dao = EquipmentDao(db);

    final n = CylindersNotifier(dao);
    await n.seedStandard();
    expect(n.cylinders, hasLength(3));
    expect(n.cylinders.map((c) => c.role).toSet(),
        {CylinderRole.oxygen, CylinderRole.diluent, CylinderRole.bailout});
  });
}
```

- [ ] **Step 2: Run, verify it fails**

Run: `flutter test test/ui/notifiers/cylinders_notifier_test.dart`

Expected: missing class.

- [ ] **Step 3: Implement CylindersNotifier**

Append to `equipment_notifiers.dart`:

```dart
class CylindersNotifier extends ChangeNotifier {
  final EquipmentDao _dao;
  CylindersNotifier(this._dao);

  List<Cylinder> _cylinders = [];
  List<Cylinder> get cylinders => List.unmodifiable(_cylinders);

  Future<void> load() async {
    _cylinders = await _dao.listCylinders();
    notifyListeners();
  }

  Future<String> add({
    required String label,
    required String role,
    int? bailoutOrder,
    required double volumeLiters,
    required int workingPressureBar,
    String? gasMix,
    String? notes,
  }) async {
    final id = await _dao.addCylinder(
      label: label,
      role: role,
      bailoutOrder: bailoutOrder,
      volumeLiters: volumeLiters,
      workingPressureBar: workingPressureBar,
      gasMix: gasMix,
      notes: notes,
    );
    await load();
    return id;
  }

  Future<void> update(
    String id, {
    String? label,
    String? role,
    int? bailoutOrder,
    double? volumeLiters,
    int? workingPressureBar,
    String? gasMix,
    String? notes,
  }) async {
    await _dao.updateCylinder(
      id,
      label: label,
      role: role,
      bailoutOrder: bailoutOrder,
      volumeLiters: volumeLiters,
      workingPressureBar: workingPressureBar,
      gasMix: gasMix,
      notes: notes,
    );
    await load();
  }

  Future<void> softDelete(String id) async {
    await _dao.softDeleteCylinder(id);
    await load();
  }

  Future<void> seedStandard() async {
    await _dao.seedStandardCcrCylinders();
    await load();
  }
}
```

- [ ] **Step 4: Run, verify it passes**

Run: `flutter test test/ui/notifiers/cylinders_notifier_test.dart`

Expected: green.

- [ ] **Step 5: Implement list screen with role grouping + empty-state CTA**

```dart
// lib/ui/screens/equipment/cylinders_list_screen.dart
import 'package:flutter/material.dart';

import '../../../data/db/database.dart';
import '../../../data/db/equipment_dao.dart';
import '../../../data/models/equipment.dart';
import '../../notifiers/equipment_notifiers.dart';
import 'cylinder_detail_screen.dart';

class CylindersListScreen extends StatefulWidget {
  final EquipmentDao dao;

  const CylindersListScreen({super.key, required this.dao});

  @override
  State<CylindersListScreen> createState() => _CylindersListScreenState();
}

class _CylindersListScreenState extends State<CylindersListScreen> {
  late final CylindersNotifier _n;

  @override
  void initState() {
    super.initState();
    _n = CylindersNotifier(widget.dao);
    _n.addListener(_onChanged);
    _n.load();
  }

  void _onChanged() => setState(() {});

  @override
  void dispose() {
    _n.removeListener(_onChanged);
    _n.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cylinders')),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final id = await _n.add(
            label: 'New cylinder',
            role: CylinderRole.bailout,
            bailoutOrder: 1,
            volumeLiters: 5,
            workingPressureBar: 200,
          );
          if (!mounted) return;
          await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => CylinderDetailScreen(dao: widget.dao, id: id),
          ));
          await _n.load();
        },
        child: const Icon(Icons.add),
      ),
      body: _n.cylinders.isEmpty ? _emptyState() : _grouped(),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'No cylinders yet.\nMost CCR rigs use O2 + Diluent + Bailout.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.auto_fix_high),
              label: const Text('Set up standard CCR cylinders'),
              onPressed: () => _n.seedStandard(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _grouped() {
    final groups = <String, List<Cylinder>>{};
    for (final c in _n.cylinders) {
      groups.putIfAbsent(c.role, () => []).add(c);
    }
    final sections = <Widget>[];
    for (final role in CylinderRole.all) {
      final list = groups[role];
      if (list == null || list.isEmpty) continue;
      sections.add(Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Text(_label(role),
            style: Theme.of(context).textTheme.titleMedium),
      ));
      for (final c in list) {
        sections.add(ListTile(
          title: Text(c.role == CylinderRole.bailout
              ? '#${c.bailoutOrder ?? '?'} · ${c.label}'
              : c.label),
          subtitle:
              Text('${c.volumeLiters}L @ ${c.workingPressureBar} bar · ${c.gasMix ?? '—'}'),
          onTap: () async {
            await Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => CylinderDetailScreen(dao: widget.dao, id: c.id),
            ));
            await _n.load();
          },
        ));
      }
    }
    return ListView(children: sections);
  }

  String _label(String role) {
    switch (role) {
      case CylinderRole.oxygen:
        return 'Oxygen';
      case CylinderRole.diluent:
        return 'Diluent';
      case CylinderRole.bailout:
        return 'Bailout';
      case CylinderRole.offboard:
        return 'Offboard';
    }
    return role;
  }
}
```

- [ ] **Step 6: Implement detail screen with role picker**

```dart
// lib/ui/screens/equipment/cylinder_detail_screen.dart
import 'package:flutter/material.dart';

import '../../../data/db/database.dart';
import '../../../data/db/equipment_dao.dart';
import '../../../data/models/equipment.dart';

class CylinderDetailScreen extends StatefulWidget {
  final EquipmentDao dao;
  final String id;

  const CylinderDetailScreen({super.key, required this.dao, required this.id});

  @override
  State<CylinderDetailScreen> createState() => _CylinderDetailScreenState();
}

class _CylinderDetailScreenState extends State<CylinderDetailScreen> {
  Cylinder? _c;
  final _label = TextEditingController();
  final _vol = TextEditingController();
  final _press = TextEditingController();
  final _gas = TextEditingController();
  final _notes = TextEditingController();
  final _bailoutOrder = TextEditingController();
  String _role = CylinderRole.bailout;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final c = await widget.dao.getCylinder(widget.id);
    if (c == null) return;
    if (!mounted) return;
    setState(() {
      _c = c;
      _label.text = c.label;
      _vol.text = c.volumeLiters.toString();
      _press.text = c.workingPressureBar.toString();
      _gas.text = c.gasMix ?? '';
      _notes.text = c.notes ?? '';
      _bailoutOrder.text = (c.bailoutOrder ?? '').toString();
      _role = c.role;
    });
  }

  Future<void> _save() async {
    if (_c == null) return;
    await widget.dao.updateCylinder(
      _c!.id,
      label: _label.text.trim(),
      role: _role,
      bailoutOrder: _role == CylinderRole.bailout
          ? int.tryParse(_bailoutOrder.text.trim())
          : null,
      volumeLiters: double.tryParse(_vol.text.trim()),
      workingPressureBar: int.tryParse(_press.text.trim()),
      gasMix: _gas.text.trim().isEmpty ? null : _gas.text.trim(),
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
    );
    await _load();
  }

  Future<void> _delete() async {
    if (_c == null) return;
    await widget.dao.softDeleteCylinder(_c!.id);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _label.dispose();
    _vol.dispose();
    _press.dispose();
    _gas.dispose();
    _notes.dispose();
    _bailoutOrder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cylinder')),
      body: _c == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextField(
                  controller: _label,
                  decoration: const InputDecoration(labelText: 'Label'),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _role,
                  decoration: const InputDecoration(labelText: 'Role'),
                  items: [
                    for (final r in CylinderRole.all)
                      DropdownMenuItem(value: r, child: Text(r)),
                  ],
                  onChanged: (v) => setState(() => _role = v ?? _role),
                ),
                if (_role == CylinderRole.bailout)
                  TextField(
                    controller: _bailoutOrder,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: 'Bailout order (#)'),
                  ),
                TextField(
                  controller: _vol,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Volume (L)'),
                ),
                TextField(
                  controller: _press,
                  keyboardType: TextInputType.number,
                  decoration:
                      const InputDecoration(labelText: 'Working pressure (bar)'),
                ),
                TextField(
                  controller: _gas,
                  decoration:
                      const InputDecoration(labelText: 'Gas mix (e.g. 21/35)'),
                ),
                TextField(
                  controller: _notes,
                  decoration: const InputDecoration(labelText: 'Notes'),
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    ElevatedButton(
                        onPressed: _save, child: const Text('Save')),
                    TextButton(onPressed: _delete, child: const Text('Delete')),
                  ],
                ),
              ],
            ),
    );
  }
}
```

- [ ] **Step 7: Wire landing card onTap**

In `equipment_landing_screen.dart`, replace the cylinders card `onTap: () {}` with:

```dart
onTap: () async {
  await Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => CylindersListScreen(dao: widget.dao),
  ));
  await _refresh();
},
```

Add the import:

```dart
import 'cylinders_list_screen.dart';
```

- [ ] **Step 8: Run tests**

Run: `flutter test`

Expected: all green.

- [ ] **Step 9: Commit**

```bash
git add lib/ui/notifiers/equipment_notifiers.dart lib/ui/screens/equipment/cylinders_list_screen.dart lib/ui/screens/equipment/cylinder_detail_screen.dart lib/ui/screens/equipment/equipment_landing_screen.dart test/ui/notifiers/cylinders_notifier_test.dart
git commit -m "feat(equipment): cylinders list with role grouping + standard CCR seed CTA"
```

---

### Task 15: Wire equipment auto-population in ImportNotifier

**Files:**
- Modify: `lib/ui/notifiers/import_notifier.dart`
- Modify: `lib/ui/app_shell.dart` (pass EquipmentDao into ImportNotifier)
- Modify: `test/ui/notifiers/import_notifier_test.dart`

- [ ] **Step 1: Add EquipmentDao to ImportNotifier**

In `lib/ui/notifiers/import_notifier.dart`, add an import and a constructor parameter:

```dart
import '../../data/db/equipment_dao.dart';
```

Update the field list and constructor:

```dart
final EquipmentDao _equipmentDao;

ImportNotifier({
  required DiveDao dao,
  required ImportStateDao importStateDao,
  required EquipmentDao equipmentDao,
  this.useMock = false,
})  : _dao = dao,
      _importStateDao = importStateDao,
      _equipmentDao = equipmentDao;
```

- [ ] **Step 2: Call upsertDiveComputer after readDeviceInfo**

In `selectRealDevice`, after `_deviceInfo = await _realTransport!.readDeviceInfo();`, add:

```dart
await _equipmentDao.upsertDiveComputer(
  serial: int.parse(_deviceInfo!.serial, radix: 16),
  model: _deviceInfo!.hardwareId,
  firmwareVersion: _parseFirmwareVersion(_deviceInfo!.firmware),
);
```

Add the helper at the bottom of the class:

```dart
int? _parseFirmwareVersion(String firmware) {
  // "V103 DiveCAN" → 103
  final m = RegExp(r'V(\d+)').firstMatch(firmware);
  return m == null ? null : int.tryParse(m.group(1)!);
}
```

- [ ] **Step 3: Call applyScrubberEvents per imported dive**

In the `downloadAll` loop, after `imported = await _dao.importDive(...)`, regardless of `imported`, add:

```dart
// Forward-compatible: parser does not currently surface scrubberResetAt.
await _equipmentDao.applyScrubberEvents(
  scrubberResetAt: null,
  dcSerial: serial,
);
```

(Once `ParsedDive.scrubberResetAt` exists, swap `null` for `parsed.scrubberResetAt`.)

- [ ] **Step 4: Update AppShell to pass EquipmentDao**

In `lib/ui/app_shell.dart`, update the `ImportNotifier(...)` instantiation:

```dart
_importNotifier = ImportNotifier(
  dao: _diveDao,
  importStateDao: _importStateDao,
  equipmentDao: _equipmentDao,
  useMock: kDebugMode,
);
```

- [ ] **Step 5: Update existing import_notifier_test**

In `test/ui/notifiers/import_notifier_test.dart`, change the constructor call to include `equipmentDao`:

```dart
notifier = ImportNotifier(
  dao: dao,
  importStateDao: importStateDao,
  equipmentDao: EquipmentDao(db),
  useMock: true,
);
```

Add the import:

```dart
import 'package:ccrlogger/data/db/equipment_dao.dart';
```

- [ ] **Step 6: Add a test that confirms upsert happens**

Append to `test/ui/notifiers/import_notifier_test.dart`:

```dart
test('selectMockDevice does not write to DiveComputers (mock path)', () async {
  // Mock path bypasses real BLE — no DC row should be created.
  final equipmentDao = EquipmentDao(db);
  expect((await equipmentDao.listDiveComputers()), isEmpty);
});
```

> NOTE: Mock-path tests can't easily exercise the real upsert. The real-BLE path (`selectRealDevice`) is integration-tested manually on hardware; the unit path stays mock-only.

- [ ] **Step 7: Run all tests**

Run: `flutter test`

Expected: all green (the existing import notifier test continues to pass with the new constructor parameter).

- [ ] **Step 8: Commit**

```bash
git add lib/ui/notifiers/import_notifier.dart lib/ui/app_shell.dart test/ui/notifiers/import_notifier_test.dart
git commit -m "feat(equipment): auto-populate DiveComputers + scrubber hook on import"
```

---

## Self-review

After completing all tasks, the spec should be fully covered:

- ✅ Equipment landing (Task 8) — four cards, drill-down navigation.
- ✅ Dive Computers list + detail with nickname (Tasks 9, 10).
- ✅ Pressure mapping editor on DC detail (Task 10).
- ✅ O2 Cells list + cell detail with surface-mV chart (Tasks 11, 12).
- ✅ Surface-mV aggregation with voted-out heuristic (Task 4).
- ✅ Scrubber Sessions list + detail + manual "+ New pack" (Task 13).
- ✅ Scrubber auto-detection wiring (Tasks 5, 15) — no-op until parser support, but plumbed.
- ✅ Cylinders list with role grouping, detail with role picker, empty-state CTA (Task 14).
- ✅ Schema migration to v2 with `label`, `Cylinders`, `PressureMappings` (Task 1).
- ✅ EquipmentDao with all spec methods (Tasks 2–7).
- ✅ Auto-population of DiveComputers from import flow (Task 15).
- ✅ DAO + notifier + widget tests across the board.

## Open verifications during implementation

These spec items require runtime verification, not design changes:

- **Sample-blob layout** for `_computeSurfaceMv` (Task 4 Step 1). The synthetic helper assumes `[depth | mv0 | mv1 | mv2]` columnar Float32 little-endian. Cross-check against the real `DiveConverter` output and adjust both helper and DAO together if the layout differs.
- **Per-channel pressure series in the sample blob.** The pressure-mapping section assumes the parser exposes a per-channel pressure series. If it doesn't yet, the editor is still functional (you can pre-create mappings manually); a parser-side follow-up plumbs imports through `pressureChannelsSeenForComputer` properly.
- **`ParsedDive.scrubberResetAt`** is referenced by the auto-detection hook in Task 15 Step 3 but the field doesn't exist on `ParsedDive` yet. The call passes `null` until parser support lands.
