# Dive Annotations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land an inline annotation editor on the dive detail screen — site (with GPS + map picker), notes, buddies, tags, rating, conditions — plus per-dive cylinder linkage that ties physical cylinders to the dive's gas mixes.

**Architecture:** A new `DiveAnnotationsDao` owns the existing `DiveAnnotations` table and a new `DiveCylinders` table (schema v3). A `DiveAnnotationsNotifier` drives a `DiveAnnotationsSection` widget embedded in `DiveDetailScreen`. Two new reusable widgets (`ChipInput`, `StarRating`) and a `MapPickerScreen` (using `flutter_map` + `geolocator`) round out the UI. Active-time-per-mix is a derived calculation reading `DiveSamples.gasMixIdxBlob`.

**Tech Stack:** Flutter, Drift (SQLite), `ChangeNotifier`, `flutter_map` (OpenStreetMap tiles), `geolocator` (GPS), `latlong2`.

---

### Spec

`docs/superpowers/specs/2026-04-27-dive-annotations-design.md` — read first.

### Key existing types

- `AppDatabase` (`lib/data/db/database.dart`): currently at `schemaVersion = 2`. Bumps to 3 in Task 1.
- `DiveAnnotations` table (`lib/data/db/tables.dart:88`): `diveId`, `siteName`, `siteLatitudeE5`, `siteLongitudeE5`, `notes`, `buddiesJson`, `tagsJson`, `rating`, `conditions` + sync metadata. PK = `{diveId}`. **Unchanged in this plan.**
- `DiveAnnotation` domain class (`lib/data/models/annotation.dart`): all the same fields with `siteLatitude`/`siteLongitude` as `double?` and `buddies`/`tags` as `List<String>`. The DAO maps Drift row ↔ domain class.
- `Dives.gasMixesJson` (text column): `jsonEncode(dive.gasMixes.map((g) => g.toJson()).toList())`. Element shape: `{'o2': int, 'he': int, 'dil': bool}`. Reified via `DiveGasMix.fromJson(...)` from `lib/data/models/dive.dart:117`.
- `Dives.startTime` is **Unix seconds** (NOT ms). Documented at `tables.dart:19`.
- `DiveSamples.gasMixIdxBlob` (gzipped Uint8 column): per-sample gas-mix index. Decode with `ColumnPacker.unpackUint8(blob, sampleCount)` from `lib/data/sample_codec/column_packer.dart`.
- `DiveDetailScreen` (`lib/ui/screens/dive_detail_screen.dart`): currently constructed as `DiveDetailScreen({required Dive dive, required DiveDao dao})`. Owns a `DiveDetailNotifier` and renders header + profile chart. Annotation section is embedded below the profile.
- `DiveDetailNotifier` (`lib/ui/notifiers/dive_detail_notifier.dart`): `loadSamples()` populates a `samples` field of type `SampleSet?`. The annotation section reuses this — derives `activeSecondsPerMix` from `samples.gasMixIndex` after the notifier finishes loading.
- `EquipmentDao.listCylinders()` (existing, from Task 6 of equipment view) — annotations UI needs the cylinder list for the gas-mix dropdowns.
- `AppShell` (`lib/ui/app_shell.dart`): instantiates `_diveDao`, `_importStateDao`, `_equipmentDao`. Adds `_diveAnnotationsDao` in Task 11.
- `DiveListScreen` (`lib/ui/screens/dive_list_screen.dart`): pushes `DiveDetailScreen` with `dao: diveDao`. Forwards `_diveAnnotationsDao` in Task 11.

### In-memory DB test boilerplate (used in every DAO test file)

```dart
import 'package:ccrlogger/data/db/database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

AppDatabase _createInMemoryDb() => AppDatabase(NativeDatabase.memory());

void main() {
  late AppDatabase db;

  setUp(() {
    db = _createInMemoryDb();
  });

  tearDown(() async {
    await db.close();
  });

  // tests...
}
```

---

### Task 1: Schema v2 → v3 — `DiveCylinders` table + migration test

**Files:**
- Modify: `lib/data/db/tables.dart`
- Modify: `lib/data/db/database.dart`
- Run: `dart run build_runner build --delete-conflicting-outputs`
- Modify: `test/data/db/migration_test.dart`

- [ ] **Step 1: Add `DiveCylinders` table**

Append to `lib/data/db/tables.dart`:

```dart
/// Per-dive linkage of gas mixes to physical cylinders.
///
/// One row per (diveId, gasMixIndex). `gasMixIndex` indexes into
/// `Dives.gasMixesJson`. `cylinderId` is nullable — null means the user
/// hasn't yet decided which cylinder held that mix.
class DiveCylinders extends Table {
  TextColumn get diveId => text().references(Dives, #id)();
  IntColumn get gasMixIndex => integer()();
  TextColumn get cylinderId => text().nullable()();

  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  IntColumn get syncStatus => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {diveId, gasMixIndex};
}
```

- [ ] **Step 2: Register the table and bump schemaVersion + migration**

In `lib/data/db/database.dart`:

```dart
@DriftDatabase(tables: [
  Dives,
  DiveSamples,
  DiveAnnotations,
  DiveComputers,
  OxygenCells,
  ScrubberSessions,
  Cylinders,
  PressureMappings,
  DiveCylinders,        // NEW
  ImportStates,
], daos: [EquipmentDao])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 3;

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
          if (from < 3) {
            await m.createTable(diveCylinders);
          }
        },
      );
}
```

- [ ] **Step 3: Regenerate Drift code**

Run: `dart run build_runner build --delete-conflicting-outputs`

Expected: `database.g.dart` updates to include the `DiveCylinders` table class.

- [ ] **Step 4: Write the failing migration test**

Append to `test/data/db/migration_test.dart` (inside `void main`, after the existing v1→v2 test):

```dart
test('v2 → v3 onUpgrade adds dive_cylinders and preserves dive_annotations',
    () async {
  // Step 1: open a raw sqlite3 db and seed it as v2 (with dive_annotations
  // but without dive_cylinders).
  final raw = sqlite3.openInMemory();
  addTearDown(raw.dispose);

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
  expect(db.schemaVersion, 3);

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
```

- [ ] **Step 5: Run the tests**

Run: `flutter test test/data/db/migration_test.dart`

Expected: 3/3 passing (existing fresh-create test + existing v1→v2 test + new v2→v3 test).

- [ ] **Step 6: Run analyzer**

Run: `flutter analyze lib/ test/`

Expected: `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add lib/data/db/tables.dart lib/data/db/database.dart lib/data/db/database.g.dart test/data/db/migration_test.dart
git commit -m "feat(annotations): add dive_cylinders table (schema v3)"
```

---

### Task 2: `DiveAnnotationsDao` foundation + annotation CRUD

**Files:**
- Create: `lib/data/db/dive_annotations_dao.dart`
- Create: `test/data/db/dive_annotations_dao_test.dart`

- [ ] **Step 1: Write failing tests**

Create `test/data/db/dive_annotations_dao_test.dart`:

```dart
import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/data/db/dive_annotations_dao.dart';
import 'package:ccrlogger/data/models/annotation.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

AppDatabase _db() => AppDatabase(NativeDatabase.memory());

DiveAnnotation _blank(String diveId) {
  final now = DateTime.now();
  return DiveAnnotation(
    diveId: diveId,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  late AppDatabase db;
  late DiveAnnotationsDao dao;

  setUp(() {
    db = _db();
    dao = DiveAnnotationsDao(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('annotation CRUD', () {
    test('get returns null for an unannotated dive', () async {
      expect(await dao.get('dive_x'), isNull);
    });

    test('upsert + get round-trips all fields', () async {
      final now = DateTime.now();
      final a = DiveAnnotation(
        diveId: 'dive_a',
        siteName: 'Black Lagoon',
        siteLatitude: 51.92345,
        siteLongitude: 4.47812,
        notes: 'good viz',
        buddies: ['Alex', 'Sam'],
        tags: ['drysuit', 'training'],
        rating: 4,
        conditions: '8m viz, no current',
        createdAt: now,
        updatedAt: now,
      );
      await dao.upsert(a);
      final got = (await dao.get('dive_a'))!;
      expect(got.siteName, 'Black Lagoon');
      expect(got.siteLatitude, closeTo(51.92345, 1e-5));
      expect(got.siteLongitude, closeTo(4.47812, 1e-5));
      expect(got.notes, 'good viz');
      expect(got.buddies, ['Alex', 'Sam']);
      expect(got.tags, ['drysuit', 'training']);
      expect(got.rating, 4);
      expect(got.conditions, '8m viz, no current');
    });

    test('upsert is idempotent on diveId', () async {
      await dao.upsert(_blank('dive_b').copyWith(siteName: 'first'));
      await dao.upsert(_blank('dive_b').copyWith(siteName: 'second'));
      final got = (await dao.get('dive_b'))!;
      expect(got.siteName, 'second');
    });
  });

  group('distinct lookups', () {
    test('distinctSiteNames / distinctBuddies / distinctTags', () async {
      final now = DateTime.now();
      await dao.upsert(DiveAnnotation(
        diveId: 'd1',
        siteName: 'Site A',
        buddies: ['Alex'],
        tags: ['drysuit'],
        createdAt: now,
        updatedAt: now,
      ));
      await dao.upsert(DiveAnnotation(
        diveId: 'd2',
        siteName: 'Site B',
        buddies: ['Alex', 'Sam'],
        tags: ['training', 'drysuit'],
        createdAt: now,
        updatedAt: now,
      ));

      expect((await dao.distinctSiteNames())..sort(), ['Site A', 'Site B']);
      expect((await dao.distinctBuddies())..sort(), ['Alex', 'Sam']);
      expect((await dao.distinctTags())..sort(), ['drysuit', 'training']);
    });
  });
}
```

The `_blank()` helper above relies on a `copyWith` method on `DiveAnnotation`. Add it in the next step.

- [ ] **Step 2: Add `copyWith` to `DiveAnnotation`**

Modify `lib/data/models/annotation.dart` — append a `copyWith` to the class:

```dart
DiveAnnotation copyWith({
  String? diveId,
  String? siteName,
  double? siteLatitude,
  double? siteLongitude,
  String? notes,
  List<String>? buddies,
  List<String>? tags,
  int? rating,
  String? conditions,
  DateTime? createdAt,
  DateTime? updatedAt,
  DateTime? deletedAt,
  int? version,
  SyncStatus? syncStatus,
}) =>
    DiveAnnotation(
      diveId: diveId ?? this.diveId,
      siteName: siteName ?? this.siteName,
      siteLatitude: siteLatitude ?? this.siteLatitude,
      siteLongitude: siteLongitude ?? this.siteLongitude,
      notes: notes ?? this.notes,
      buddies: buddies ?? this.buddies,
      tags: tags ?? this.tags,
      rating: rating ?? this.rating,
      conditions: conditions ?? this.conditions,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      version: version ?? this.version,
      syncStatus: syncStatus ?? this.syncStatus,
    );
```

> Note: this `copyWith` uses `??` everywhere, so passing `null` to clear a nullable field doesn't work — that's accepted scope; clearing happens at the DAO write layer.

- [ ] **Step 3: Run the test, verify it fails**

Run: `flutter test test/data/db/dive_annotations_dao_test.dart`

Expected: compile errors — `dive_annotations_dao.dart` does not exist.

- [ ] **Step 4: Implement the DAO**

Create `lib/data/db/dive_annotations_dao.dart`:

```dart
import 'dart:convert';

import 'package:drift/drift.dart';

import '../models/annotation.dart';
import 'database.dart';
import 'tables.dart';

part 'dive_annotations_dao.g.dart';

@DriftAccessor(tables: [DiveAnnotations, DiveCylinders])
class DiveAnnotationsDao extends DatabaseAccessor<AppDatabase>
    with _$DiveAnnotationsDaoMixin {
  DiveAnnotationsDao(super.db);

  // ── DiveAnnotations ─────────────────────────────────────────────────────

  Future<DiveAnnotation?> get(String diveId) async {
    final row = await (select(diveAnnotations)
          ..where((t) => t.diveId.equals(diveId) & t.deletedAt.isNull()))
        .getSingleOrNull();
    if (row == null) return null;
    return _toModel(row);
  }

  Future<void> upsert(DiveAnnotation a) async {
    await into(diveAnnotations).insertOnConflictUpdate(_toCompanion(a));
  }

  Future<List<String>> distinctSiteNames() async {
    final rows = await (selectOnly(diveAnnotations, distinct: true)
          ..addColumns([diveAnnotations.siteName])
          ..where(diveAnnotations.siteName.isNotNull() &
              diveAnnotations.deletedAt.isNull()))
        .get();
    return rows
        .map((r) => r.read(diveAnnotations.siteName))
        .whereType<String>()
        .toList();
  }

  Future<List<String>> distinctBuddies() async {
    final rows = await (select(diveAnnotations)
          ..where((t) => t.deletedAt.isNull() & t.buddiesJson.isNotNull()))
        .get();
    final all = <String>{};
    for (final r in rows) {
      if (r.buddiesJson == null) continue;
      final list = (jsonDecode(r.buddiesJson!) as List).cast<String>();
      all.addAll(list);
    }
    return all.toList();
  }

  Future<List<String>> distinctTags() async {
    final rows = await (select(diveAnnotations)
          ..where((t) => t.deletedAt.isNull() & t.tagsJson.isNotNull()))
        .get();
    final all = <String>{};
    for (final r in rows) {
      if (r.tagsJson == null) continue;
      final list = (jsonDecode(r.tagsJson!) as List).cast<String>();
      all.addAll(list);
    }
    return all.toList();
  }

  // ── Mapping helpers ─────────────────────────────────────────────────────

  DiveAnnotation _toModel(DiveAnnotation_Drift_Row row) {
    // Drift's row class for `DiveAnnotations` is conventionally named
    // `DiveAnnotation` — it shadows our domain class. Avoid the collision
    // by using the row's column accessors directly.
    return DiveAnnotation(
      diveId: row.diveId,
      siteName: row.siteName,
      siteLatitude:
          row.siteLatitudeE5 == null ? null : row.siteLatitudeE5! / 1e5,
      siteLongitude:
          row.siteLongitudeE5 == null ? null : row.siteLongitudeE5! / 1e5,
      notes: row.notes,
      buddies: row.buddiesJson == null
          ? const []
          : (jsonDecode(row.buddiesJson!) as List).cast<String>(),
      tags: row.tagsJson == null
          ? const []
          : (jsonDecode(row.tagsJson!) as List).cast<String>(),
      rating: row.rating,
      conditions: row.conditions,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row.createdAt),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row.updatedAt),
      deletedAt: row.deletedAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(row.deletedAt!),
      version: row.version,
      syncStatus: SyncStatus.values[row.syncStatus],
    );
  }

  DiveAnnotationsCompanion _toCompanion(DiveAnnotation a) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return DiveAnnotationsCompanion.insert(
      diveId: a.diveId,
      siteName: Value(a.siteName),
      siteLatitudeE5: Value(
          a.siteLatitude == null ? null : (a.siteLatitude! * 1e5).round()),
      siteLongitudeE5: Value(
          a.siteLongitude == null ? null : (a.siteLongitude! * 1e5).round()),
      notes: Value(a.notes),
      buddiesJson:
          Value(a.buddies.isEmpty ? null : jsonEncode(a.buddies)),
      tagsJson: Value(a.tags.isEmpty ? null : jsonEncode(a.tags)),
      rating: Value(a.rating),
      conditions: Value(a.conditions),
      createdAt: a.createdAt.millisecondsSinceEpoch,
      updatedAt: now,
    );
  }
}
```

> **Important type note:** Drift names the row class for the `DiveAnnotations` table as `DiveAnnotation` (singular of the table name). That **shadows our domain class of the same name**. The implementer should resolve via two clean options: (1) import the domain class with a prefix (`import '../models/annotation.dart' as dom; ... dom.DiveAnnotation`), or (2) rename the domain class to `Annotation` or `DiveAnnotationModel`. **Option 1 is preferred** — leaves the domain name intact for callers; only the DAO file deals with the prefix. If using option 1, change the import line above to `import '../models/annotation.dart' as dom;` and use `dom.DiveAnnotation` everywhere this file references the domain class. Update the test file similarly (or keep the test using the domain class without prefix, since the test doesn't import `database.dart`'s row class by name).

- [ ] **Step 5: Regenerate Drift code**

Run: `dart run build_runner build --delete-conflicting-outputs`

Expected: creates `lib/data/db/dive_annotations_dao.g.dart`.

- [ ] **Step 6: Run tests**

Run: `flutter test test/data/db/dive_annotations_dao_test.dart`

Expected: 4/4 passing.

- [ ] **Step 7: Commit**

```bash
git add lib/data/db/dive_annotations_dao.dart lib/data/db/dive_annotations_dao.g.dart lib/data/models/annotation.dart test/data/db/dive_annotations_dao_test.dart
git commit -m "feat(annotations): DiveAnnotationsDao with CRUD and distinct lookups"
```

---

### Task 3: `DiveAnnotationsDao` cylinder-mapping methods + transactional `saveAll`

**Files:**
- Modify: `lib/data/db/dive_annotations_dao.dart`
- Modify: `test/data/db/dive_annotations_dao_test.dart`

- [ ] **Step 1: Write failing tests**

Append to `test/data/db/dive_annotations_dao_test.dart`:

```dart
group('cylinder linkage', () {
  test('listCylindersForDive returns rows for the dive', () async {
    await dao.setDiveCylinder('d1', 0, 'cyl_o2');
    await dao.setDiveCylinder('d1', 1, 'cyl_dil');
    final rows = await dao.listCylindersForDive('d1');
    expect(rows.map((r) => r.gasMixIndex).toList()..sort(), [0, 1]);
  });

  test('setDiveCylinder upserts on (diveId, gasMixIndex)', () async {
    await dao.setDiveCylinder('d1', 0, 'cyl_o2');
    await dao.setDiveCylinder('d1', 0, 'cyl_o2_v2');
    final rows = await dao.listCylindersForDive('d1');
    expect(rows, hasLength(1));
    expect(rows.single.cylinderId, 'cyl_o2_v2');
  });

  test('setDiveCylinder accepts null (unmapped)', () async {
    await dao.setDiveCylinder('d1', 0, 'cyl_o2');
    await dao.setDiveCylinder('d1', 0, null);
    final rows = await dao.listCylindersForDive('d1');
    expect(rows.single.cylinderId, isNull);
  });

  test('saveAll writes annotation + cylinders in one transaction', () async {
    final now = DateTime.now();
    final a = DiveAnnotation(
      diveId: 'dx',
      siteName: 'Test Site',
      createdAt: now,
      updatedAt: now,
    );
    await dao.saveAll(a, [
      (gasMixIndex: 0, cylinderId: 'cyl_o2'),
      (gasMixIndex: 1, cylinderId: 'cyl_dil'),
    ]);

    expect((await dao.get('dx'))!.siteName, 'Test Site');
    final rows = await dao.listCylindersForDive('dx');
    expect(rows, hasLength(2));
  });
});
```

- [ ] **Step 2: Run, verify it fails**

Run: `flutter test test/data/db/dive_annotations_dao_test.dart`

Expected: missing methods on `DiveAnnotationsDao`.

- [ ] **Step 3: Implement cylinder methods**

Append to `DiveAnnotationsDao`:

```dart
// ── DiveCylinders ───────────────────────────────────────────────────────

Future<List<DiveCylinder>> listCylindersForDive(String diveId) {
  return (select(diveCylinders)
        ..where((t) =>
            t.diveId.equals(diveId) & t.deletedAt.isNull())
        ..orderBy([(t) => OrderingTerm.asc(t.gasMixIndex)]))
      .get();
}

Future<void> setDiveCylinder(
    String diveId, int gasMixIndex, String? cylinderId) async {
  final now = DateTime.now().millisecondsSinceEpoch;
  await into(diveCylinders).insertOnConflictUpdate(
    DiveCylindersCompanion.insert(
      diveId: diveId,
      gasMixIndex: gasMixIndex,
      cylinderId: Value(cylinderId),
      createdAt: now,
      updatedAt: now,
    ),
  );
}

/// Writes the annotation row and all dive-cylinder rows atomically.
Future<void> saveAll(
  DiveAnnotation annotation,
  List<({int gasMixIndex, String? cylinderId})> mappings,
) async {
  await db.transaction(() async {
    await upsert(annotation);
    for (final m in mappings) {
      await setDiveCylinder(annotation.diveId, m.gasMixIndex, m.cylinderId);
    }
  });
}
```

- [ ] **Step 4: Run, verify all tests pass**

Run: `flutter test test/data/db/dive_annotations_dao_test.dart`

Expected: 8/8 passing (4 existing + 4 new).

- [ ] **Step 5: Run analyzer**

Run: `flutter analyze lib/ test/`

Expected: clean.

- [ ] **Step 6: Commit**

```bash
git add lib/data/db/dive_annotations_dao.dart test/data/db/dive_annotations_dao_test.dart
git commit -m "feat(annotations): cylinder linkage methods + transactional saveAll"
```

---

### Task 4: `activeSecondsPerMix` codec helper

**Files:**
- Create: `lib/data/sample_codec/active_per_mix.dart`
- Create: `test/data/sample_codec/active_per_mix_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/data/sample_codec/active_per_mix_test.dart`:

```dart
import 'dart:typed_data';

import 'package:ccrlogger/data/sample_codec/active_per_mix.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('counts samples per mix index and converts to seconds', () {
    // Indexes: [0, 0, 0, 1, 1, 2] = 6 samples, sampleIntervalMs=10000 (10s).
    // Expect: {0: 30, 1: 20, 2: 10}.
    final raw = Uint8List.fromList([0, 0, 0, 1, 1, 2]);
    final out = activeSecondsPerMix(
      gasMixIndexes: raw,
      sampleCount: 6,
      sampleIntervalMs: 10000,
    );
    expect(out, {0: 30, 1: 20, 2: 10});
  });

  test('handles a single-mix dive', () {
    final raw = Uint8List.fromList(List.filled(120, 0));
    final out = activeSecondsPerMix(
      gasMixIndexes: raw,
      sampleCount: 120,
      sampleIntervalMs: 5000,
    );
    expect(out, {0: 600});
  });

  test('returns empty map for zero samples', () {
    final out = activeSecondsPerMix(
      gasMixIndexes: Uint8List(0),
      sampleCount: 0,
      sampleIntervalMs: 10000,
    );
    expect(out, isEmpty);
  });
}
```

- [ ] **Step 2: Run, verify it fails**

Run: `flutter test test/data/sample_codec/active_per_mix_test.dart`

Expected: file not found.

- [ ] **Step 3: Implement**

Create `lib/data/sample_codec/active_per_mix.dart`:

```dart
import 'dart:typed_data';

/// Computes seconds-active per gas-mix index for a dive.
///
/// Counts how many samples in [gasMixIndexes] reference each mix index,
/// then multiplies by [sampleIntervalMs] / 1000.
///
/// [gasMixIndexes] is the **already-unpacked** per-sample mix index byte
/// array — pass `ColumnPacker.unpackUint8(blob, sampleCount)` to convert
/// from the gzipped on-disk representation.
Map<int, int> activeSecondsPerMix({
  required Uint8List gasMixIndexes,
  required int sampleCount,
  required int sampleIntervalMs,
}) {
  if (sampleCount == 0) return const {};
  final counts = <int, int>{};
  final n = sampleCount < gasMixIndexes.length
      ? sampleCount
      : gasMixIndexes.length;
  for (var i = 0; i < n; i++) {
    final idx = gasMixIndexes[i];
    counts[idx] = (counts[idx] ?? 0) + 1;
  }
  final secondsPerSample = sampleIntervalMs ~/ 1000;
  return {for (final e in counts.entries) e.key: e.value * secondsPerSample};
}
```

- [ ] **Step 4: Run, verify it passes**

Run: `flutter test test/data/sample_codec/active_per_mix_test.dart`

Expected: 3/3 passing.

- [ ] **Step 5: Commit**

```bash
git add lib/data/sample_codec/active_per_mix.dart test/data/sample_codec/active_per_mix_test.dart
git commit -m "feat(annotations): activeSecondsPerMix codec helper"
```

---

### Task 5: pubspec deps + platform permissions

**Files:**
- Modify: `pubspec.yaml`
- Modify: `ios/Runner/Info.plist`
- Modify: `macos/Runner/Info.plist`
- Modify: `macos/Runner/DebugProfile.entitlements`
- Modify: `macos/Runner/Release.entitlements`
- Modify: `android/app/src/main/AndroidManifest.xml`

This task has no failing test; it's a config-only change validated by `flutter pub get` succeeding and `flutter analyze` staying clean. No commit-then-test cycle.

- [ ] **Step 1: Add dependencies**

In `pubspec.yaml`, under `dependencies:`, append:

```yaml
  geolocator: ^14.0.0
  flutter_map: ^7.0.0
  latlong2: ^0.9.0
```

Run: `flutter pub get`

Expected: all three packages resolve. If `flutter_map: ^7.0.0` fails on the project's Dart constraint (`^3.11.5`), try `^6.1.0` and note it in the report. The exact version matters less than picking the latest major that resolves.

- [ ] **Step 2: iOS Info.plist**

In `ios/Runner/Info.plist`, append a permission key inside the existing `<dict>`:

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>This app uses your location to record where each dive happened.</string>
```

- [ ] **Step 3: macOS Info.plist**

In `macos/Runner/Info.plist`, append:

```xml
<key>NSLocationUsageDescription</key>
<string>This app uses your location to record where each dive happened.</string>
```

- [ ] **Step 4: macOS entitlements (both files)**

In `macos/Runner/DebugProfile.entitlements` and `macos/Runner/Release.entitlements`, append inside `<dict>`:

```xml
<key>com.apple.security.personal-information.location</key>
<true/>
```

- [ ] **Step 5: Android manifest**

In `android/app/src/main/AndroidManifest.xml`, append inside `<manifest>` (above `<application>`):

```xml
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
```

- [ ] **Step 6: Sanity-check**

Run:
- `flutter pub get` — expect no errors.
- `flutter analyze lib/ test/` — expect `No issues found!`.
- `flutter test` — expect all tests passing (no behavior change).

- [ ] **Step 7: Commit**

```bash
git add pubspec.yaml pubspec.lock ios/Runner/Info.plist macos/Runner/Info.plist macos/Runner/DebugProfile.entitlements macos/Runner/Release.entitlements android/app/src/main/AndroidManifest.xml
git commit -m "feat(annotations): add geolocator + flutter_map deps and platform permissions"
```

---

### Task 6: `StarRating` widget

**Files:**
- Create: `lib/ui/widgets/star_rating.dart`
- Create: `test/ui/widgets/star_rating_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/ui/widgets/star_rating_test.dart`:

```dart
import 'package:ccrlogger/ui/widgets/star_rating.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders 5 star icons', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StarRating(value: null, onChanged: (_) {}),
      ),
    ));
    expect(find.byIcon(Icons.star_outline), findsNWidgets(5));
  });

  testWidgets('value=3 fills first 3 stars', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StarRating(value: 3, onChanged: (_) {}),
      ),
    ));
    expect(find.byIcon(Icons.star), findsNWidgets(3));
    expect(find.byIcon(Icons.star_outline), findsNWidgets(2));
  });

  testWidgets('tap star N → onChanged(N)', (tester) async {
    int? captured;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StarRating(value: null, onChanged: (v) => captured = v),
      ),
    ));
    await tester.tap(find.byIcon(Icons.star_outline).at(2));
    expect(captured, 3);
  });

  testWidgets('tap currently-active star → onChanged(null)', (tester) async {
    int? captured = -1;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StarRating(value: 3, onChanged: (v) => captured = v),
      ),
    ));
    await tester.tap(find.byIcon(Icons.star).at(2));
    expect(captured, isNull);
  });
}
```

- [ ] **Step 2: Run, verify it fails**

Run: `flutter test test/ui/widgets/star_rating_test.dart`

Expected: file not found.

- [ ] **Step 3: Implement**

Create `lib/ui/widgets/star_rating.dart`:

```dart
import 'package:flutter/material.dart';

class StarRating extends StatelessWidget {
  final int? value; // 1-5 or null
  final void Function(int? value) onChanged;

  const StarRating({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(
              i <= (value ?? 0) ? Icons.star : Icons.star_outline,
              color: Theme.of(context).colorScheme.primary,
            ),
            onPressed: () {
              if (value == i) {
                onChanged(null);
              } else {
                onChanged(i);
              }
            },
          ),
      ],
    );
  }
}
```

- [ ] **Step 4: Run, verify all 4 tests pass**

Run: `flutter test test/ui/widgets/star_rating_test.dart`

Expected: 4/4 passing.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/widgets/star_rating.dart test/ui/widgets/star_rating_test.dart
git commit -m "feat(annotations): StarRating widget"
```

---

### Task 7: `ChipInput` widget

**Files:**
- Create: `lib/ui/widgets/chip_input.dart`
- Create: `test/ui/widgets/chip_input_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/ui/widgets/chip_input_test.dart`:

```dart
import 'package:ccrlogger/ui/widgets/chip_input.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders initial chips', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ChipInput(
          initialValues: const ['Alex', 'Sam'],
          autocompleteOptions: const [],
          onChanged: (_) {},
        ),
      ),
    ));
    expect(find.text('Alex'), findsOneWidget);
    expect(find.text('Sam'), findsOneWidget);
  });

  testWidgets('typing + Enter promotes text to a chip', (tester) async {
    final captured = <List<String>>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ChipInput(
          initialValues: const [],
          autocompleteOptions: const [],
          onChanged: captured.add,
        ),
      ),
    ));

    await tester.enterText(find.byType(TextField), 'Robin');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(find.widgetWithText(Chip, 'Robin'), findsOneWidget);
    expect(captured.last, ['Robin']);
  });

  testWidgets('tap chip × removes it', (tester) async {
    final captured = <List<String>>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ChipInput(
          initialValues: const ['Alex', 'Sam'],
          autocompleteOptions: const [],
          onChanged: captured.add,
        ),
      ),
    ));

    final closeIcons = find.byIcon(Icons.close);
    expect(closeIcons, findsNWidgets(2));
    await tester.tap(closeIcons.first);
    await tester.pump();

    expect(captured.last, ['Sam']);
  });
}
```

- [ ] **Step 2: Run, verify it fails**

Run: `flutter test test/ui/widgets/chip_input_test.dart`

Expected: file not found.

- [ ] **Step 3: Implement**

Create `lib/ui/widgets/chip_input.dart`:

```dart
import 'package:flutter/material.dart';

class ChipInput extends StatefulWidget {
  final List<String> initialValues;
  final List<String> autocompleteOptions;
  final void Function(List<String> values) onChanged;
  final String hintText;

  const ChipInput({
    super.key,
    required this.initialValues,
    required this.autocompleteOptions,
    required this.onChanged,
    this.hintText = 'Add…',
  });

  @override
  State<ChipInput> createState() => _ChipInputState();
}

class _ChipInputState extends State<ChipInput> {
  late List<String> _values;
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _values = [...widget.initialValues];
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _add(String raw) {
    final v = raw.trim();
    if (v.isEmpty || _values.contains(v)) {
      _controller.clear();
      return;
    }
    setState(() => _values.add(v));
    _controller.clear();
    widget.onChanged(_values);
  }

  void _remove(String v) {
    setState(() => _values.remove(v));
    widget.onChanged(_values);
  }

  @override
  Widget build(BuildContext context) {
    final available = widget.autocompleteOptions
        .where((o) => !_values.contains(o))
        .toList();

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final v in _values)
          Chip(
            label: Text(v),
            onDeleted: () => _remove(v),
            deleteIcon: const Icon(Icons.close, size: 16),
          ),
        SizedBox(
          width: 160,
          child: Autocomplete<String>(
            optionsBuilder: (TextEditingValue tev) {
              if (tev.text.isEmpty) return const Iterable<String>.empty();
              return available.where(
                  (o) => o.toLowerCase().contains(tev.text.toLowerCase()));
            },
            onSelected: _add,
            fieldViewBuilder:
                (context, textController, focusNode, onSubmitted) {
              // Sync our controller with Autocomplete's so external clears work.
              return TextField(
                controller: textController,
                focusNode: focusNode,
                decoration: InputDecoration(
                  hintText: widget.hintText,
                  isDense: true,
                ),
                onSubmitted: (v) {
                  _add(v);
                  textController.clear();
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 4: Run, verify all 3 tests pass**

Run: `flutter test test/ui/widgets/chip_input_test.dart`

Expected: 3/3 passing. If the typing-+-Enter test fails because the inner `Autocomplete` field controller is the one receiving the input (not our `_controller`), the implementation in Step 3 works around it by using the inner field controller passed to `fieldViewBuilder`.

- [ ] **Step 5: Run analyzer**

Run: `flutter analyze lib/ test/`

Expected: clean.

- [ ] **Step 6: Commit**

```bash
git add lib/ui/widgets/chip_input.dart test/ui/widgets/chip_input_test.dart
git commit -m "feat(annotations): ChipInput widget with autocomplete"
```

---

### Task 8: `DiveAnnotationsNotifier`

**Files:**
- Create: `lib/ui/notifiers/dive_annotations_notifier.dart`
- Create: `test/ui/notifiers/dive_annotations_notifier_test.dart`

- [ ] **Step 1: Write failing tests**

Create `test/ui/notifiers/dive_annotations_notifier_test.dart`:

```dart
import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/data/db/dive_annotations_dao.dart';
import 'package:ccrlogger/ui/notifiers/dive_annotations_notifier.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late DiveAnnotationsDao dao;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    dao = DiveAnnotationsDao(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('load → set fields → dirty == true → save → dirty == false', () async {
    final n = DiveAnnotationsNotifier(dao);
    await n.load('dive_x');
    expect(n.dirty, isFalse);

    n.setSiteName('Test Site');
    expect(n.dirty, isTrue);

    await n.save();
    expect(n.dirty, isFalse);

    final got = await dao.get('dive_x');
    expect(got?.siteName, 'Test Site');
  });

  test('save persists cylinder mappings', () async {
    final n = DiveAnnotationsNotifier(dao);
    await n.load('dive_y');
    n.setCylinderForMix(0, 'cyl_o2');
    n.setCylinderForMix(1, null);
    await n.save();

    final rows = await dao.listCylindersForDive('dive_y');
    expect(rows, hasLength(2));
    expect(rows.firstWhere((r) => r.gasMixIndex == 0).cylinderId, 'cyl_o2');
    expect(rows.firstWhere((r) => r.gasMixIndex == 1).cylinderId, isNull);
  });
}
```

- [ ] **Step 2: Run, verify it fails**

Run: `flutter test test/ui/notifiers/dive_annotations_notifier_test.dart`

Expected: missing class.

- [ ] **Step 3: Implement**

Create `lib/ui/notifiers/dive_annotations_notifier.dart`:

```dart
import 'package:flutter/foundation.dart';

import '../../data/db/dive_annotations_dao.dart';
import '../../data/models/annotation.dart';

class DiveAnnotationsNotifier extends ChangeNotifier {
  final DiveAnnotationsDao _dao;

  DiveAnnotationsNotifier(this._dao);

  String? _diveId;
  DiveAnnotation? _annotation;
  Map<int, String?> _cylinderByMix = {};
  bool _dirty = false;

  // ── Read accessors ────────────────────────────────────────────────────

  String? get siteName => _annotation?.siteName;
  double? get siteLatitude => _annotation?.siteLatitude;
  double? get siteLongitude => _annotation?.siteLongitude;
  String? get notes => _annotation?.notes;
  List<String> get buddies => _annotation?.buddies ?? const [];
  List<String> get tags => _annotation?.tags ?? const [];
  int? get rating => _annotation?.rating;
  String? get conditions => _annotation?.conditions;
  Map<int, String?> get cylinderByMix => Map.unmodifiable(_cylinderByMix);
  bool get dirty => _dirty;
  bool get loaded => _annotation != null;

  // ── Lifecycle ─────────────────────────────────────────────────────────

  Future<void> load(String diveId) async {
    _diveId = diveId;
    final existing = await _dao.get(diveId);
    if (existing != null) {
      _annotation = existing;
    } else {
      final now = DateTime.now();
      _annotation = DiveAnnotation(
        diveId: diveId,
        createdAt: now,
        updatedAt: now,
      );
    }
    final cylinders = await _dao.listCylindersForDive(diveId);
    _cylinderByMix = {for (final c in cylinders) c.gasMixIndex: c.cylinderId};
    _dirty = false;
    notifyListeners();
  }

  // ── Setters ───────────────────────────────────────────────────────────

  void setSiteName(String? v) {
    _annotation = _annotation?.copyWith(siteName: v);
    _markDirty();
  }

  void setLatLon(double? lat, double? lon) {
    _annotation = _annotation?.copyWith(siteLatitude: lat, siteLongitude: lon);
    _markDirty();
  }

  void setNotes(String? v) {
    _annotation = _annotation?.copyWith(notes: v);
    _markDirty();
  }

  void setBuddies(List<String> v) {
    _annotation = _annotation?.copyWith(buddies: v);
    _markDirty();
  }

  void setTags(List<String> v) {
    _annotation = _annotation?.copyWith(tags: v);
    _markDirty();
  }

  void setRating(int? v) {
    _annotation = _annotation?.copyWith(rating: v);
    _markDirty();
  }

  void setConditions(String? v) {
    _annotation = _annotation?.copyWith(conditions: v);
    _markDirty();
  }

  void setCylinderForMix(int gasMixIndex, String? cylinderId) {
    _cylinderByMix = {..._cylinderByMix, gasMixIndex: cylinderId};
    _markDirty();
  }

  void _markDirty() {
    _dirty = true;
    notifyListeners();
  }

  // ── Save ──────────────────────────────────────────────────────────────

  Future<void> save() async {
    if (_annotation == null || _diveId == null) return;
    final mappings = _cylinderByMix.entries
        .map((e) => (gasMixIndex: e.key, cylinderId: e.value))
        .toList();
    await _dao.saveAll(_annotation!, mappings);
    _dirty = false;
    notifyListeners();
  }
}
```

> Note: `copyWith` in `DiveAnnotation` uses `??` everywhere so passing `null` doesn't clear fields. For MVP this matches how we cleared fields on the equipment screens (treat empty string as "no value" at the read site). If field-clear becomes important, the `copyWith` signature needs to switch to a `Value<T?>?` sentinel pattern — out of scope here.

- [ ] **Step 4: Run, verify all tests pass**

Run: `flutter test test/ui/notifiers/dive_annotations_notifier_test.dart`

Expected: 2/2 passing.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/notifiers/dive_annotations_notifier.dart test/ui/notifiers/dive_annotations_notifier_test.dart
git commit -m "feat(annotations): DiveAnnotationsNotifier with dirty tracking + saveAll"
```

---

### Task 9: `MapPickerScreen`

**Files:**
- Create: `lib/ui/screens/map_picker_screen.dart`

No automated test. The picker is a thin wrapper around `flutter_map` + `geolocator`. Manual on-device verification: open picker, drop pin, confirm, verify lat/lon round-trip.

- [ ] **Step 1: Implement**

Create `lib/ui/screens/map_picker_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// OpenStreetMap tile server. Note: tile.openstreetmap.org's usage policy
/// disallows production use in mobile apps; swap to a permitted provider
/// (MapTiler / Stadia / self-hosted) before public release.
const String _tileUrlTemplate =
    'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

class MapPickerScreen extends StatefulWidget {
  final double? initialLat;
  final double? initialLon;

  const MapPickerScreen({super.key, this.initialLat, this.initialLon});

  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  final _mapController = MapController();
  LatLng _pin = const LatLng(0, 0);
  bool _initialised = false;

  @override
  void initState() {
    super.initState();
    _initPin();
  }

  Future<void> _initPin() async {
    LatLng? p;
    if (widget.initialLat != null && widget.initialLon != null) {
      p = LatLng(widget.initialLat!, widget.initialLon!);
    } else {
      p = await _currentLocation();
    }
    p ??= const LatLng(0, 0);
    if (!mounted) return;
    setState(() {
      _pin = p!;
      _initialised = true;
    });
    _mapController.move(_pin, 13);
  }

  Future<LatLng?> _currentLocation() async {
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        final req = await Geolocator.requestPermission();
        if (req != LocationPermission.always &&
            req != LocationPermission.whileInUse) {
          return null;
        }
      }
      final pos = await Geolocator.getCurrentPosition();
      return LatLng(pos.latitude, pos.longitude);
    } catch (_) {
      return null;
    }
  }

  Future<void> _useCurrent() async {
    final p = await _currentLocation();
    if (p == null || !mounted) return;
    setState(() => _pin = p);
    _mapController.move(p, 13);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pick location'),
        actions: [
          IconButton(
            icon: const Icon(Icons.my_location),
            onPressed: _useCurrent,
            tooltip: 'Use current location',
          ),
        ],
      ),
      body: !_initialised
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _pin,
                    initialZoom: 13,
                    onTap: (_, point) => setState(() => _pin = point),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: _tileUrlTemplate,
                      userAgentPackageName: 'app.ccrlogger',
                    ),
                    MarkerLayer(markers: [
                      Marker(
                        point: _pin,
                        width: 36,
                        height: 36,
                        child: const Icon(Icons.location_pin,
                            color: Colors.red, size: 36),
                      ),
                    ]),
                  ],
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 24,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.check),
                    label: Text(
                        'Use ${_pin.latitude.toStringAsFixed(5)}, ${_pin.longitude.toStringAsFixed(5)}'),
                    onPressed: () => Navigator.of(context).pop(
                      (lat: _pin.latitude, lon: _pin.longitude),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
```

- [ ] **Step 2: Run analyzer**

Run: `flutter analyze lib/ test/`

Expected: clean. If `flutter_map` API differs (e.g. `MapOptions` requires different params in the resolved version), adapt to the actual API; the structure above is for `flutter_map ^7.x`.

- [ ] **Step 3: Manual smoke test (optional, do this once during implementation)**

Build the app on macOS or iOS, navigate to a dive, tap "Pick on map", verify the screen renders, drop a pin, confirm. The lat/lon should print or appear in the consumer of `Navigator.pop`. (The full user flow is exercised in Task 10 once `DiveAnnotationsSection` wires it up.)

- [ ] **Step 4: Commit**

```bash
git add lib/ui/screens/map_picker_screen.dart
git commit -m "feat(annotations): MapPickerScreen with flutter_map + geolocator"
```

---

### Task 10: `DiveAnnotationsSection` composite widget

**Files:**
- Create: `lib/ui/widgets/dive_annotations_section.dart`
- Create: `test/ui/widgets/dive_annotations_section_test.dart`

- [ ] **Step 1: Write the failing widget smoke test**

Create `test/ui/widgets/dive_annotations_section_test.dart`:

```dart
import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/data/db/dive_annotations_dao.dart';
import 'package:ccrlogger/data/db/equipment_dao.dart';
import 'package:ccrlogger/data/models/dive.dart';
import 'package:ccrlogger/ui/widgets/dive_annotations_section.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders all field labels for a fresh (no-row-yet) dive',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final annotationsDao = DiveAnnotationsDao(db);
    final equipmentDao = EquipmentDao(db);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: DiveAnnotationsSection(
            diveId: 'dive_x',
            gasMixes: const [],
            activeSecondsByMix: const {},
            annotationsDao: annotationsDao,
            equipmentDao: equipmentDao,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Site'), findsOneWidget);
    expect(find.text('Notes'), findsOneWidget);
    expect(find.text('Buddies'), findsOneWidget);
    expect(find.text('Tags'), findsOneWidget);
    expect(find.text('Rating'), findsOneWidget);
    expect(find.text('Conditions'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Save'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run, verify it fails**

Run: `flutter test test/ui/widgets/dive_annotations_section_test.dart`

Expected: file not found.

- [ ] **Step 3: Implement**

Create `lib/ui/widgets/dive_annotations_section.dart`:

```dart
import 'package:flutter/material.dart';

import '../../data/db/database.dart';
import '../../data/db/dive_annotations_dao.dart';
import '../../data/db/equipment_dao.dart';
import '../../data/models/dive.dart';
import '../notifiers/dive_annotations_notifier.dart';
import '../screens/map_picker_screen.dart';
import 'chip_input.dart';
import 'star_rating.dart';

class DiveAnnotationsSection extends StatefulWidget {
  final String diveId;
  final List<DiveGasMix> gasMixes;
  final Map<int, int> activeSecondsByMix;
  final DiveAnnotationsDao annotationsDao;
  final EquipmentDao equipmentDao;

  const DiveAnnotationsSection({
    super.key,
    required this.diveId,
    required this.gasMixes,
    required this.activeSecondsByMix,
    required this.annotationsDao,
    required this.equipmentDao,
  });

  @override
  State<DiveAnnotationsSection> createState() =>
      _DiveAnnotationsSectionState();
}

class _DiveAnnotationsSectionState extends State<DiveAnnotationsSection> {
  late final DiveAnnotationsNotifier _n;
  final _site = TextEditingController();
  final _lat = TextEditingController();
  final _lon = TextEditingController();
  final _notes = TextEditingController();
  final _conditions = TextEditingController();

  List<String> _siteOptions = const [];
  List<String> _buddyOptions = const [];
  List<String> _tagOptions = const [];
  List<Cylinder> _cylinders = const [];

  @override
  void initState() {
    super.initState();
    _n = DiveAnnotationsNotifier(widget.annotationsDao);
    _n.addListener(_onChanged);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _n.load(widget.diveId);
    _siteOptions = await widget.annotationsDao.distinctSiteNames();
    _buddyOptions = await widget.annotationsDao.distinctBuddies();
    _tagOptions = await widget.annotationsDao.distinctTags();
    _cylinders = await widget.equipmentDao.listCylinders();
    if (!mounted) return;
    _site.text = _n.siteName ?? '';
    _lat.text = _n.siteLatitude?.toString() ?? '';
    _lon.text = _n.siteLongitude?.toString() ?? '';
    _notes.text = _n.notes ?? '';
    _conditions.text = _n.conditions ?? '';
    setState(() {});
  }

  void _onChanged() => setState(() {});

  @override
  void dispose() {
    _n.removeListener(_onChanged);
    _n.dispose();
    _site.dispose();
    _lat.dispose();
    _lon.dispose();
    _notes.dispose();
    _conditions.dispose();
    super.dispose();
  }

  Future<void> _pickOnMap() async {
    final result = await Navigator.of(context).push<({double lat, double lon})>(
      MaterialPageRoute(
        builder: (_) => MapPickerScreen(
          initialLat: double.tryParse(_lat.text.trim()),
          initialLon: double.tryParse(_lon.text.trim()),
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _lat.text = result.lat.toStringAsFixed(6);
      _lon.text = result.lon.toStringAsFixed(6);
    });
    _n.setLatLon(result.lat, result.lon);
  }

  Future<void> _save() async {
    _n.setSiteName(_site.text.trim().isEmpty ? null : _site.text.trim());
    _n.setLatLon(
      double.tryParse(_lat.text.trim()),
      double.tryParse(_lon.text.trim()),
    );
    _n.setNotes(_notes.text.trim().isEmpty ? null : _notes.text.trim());
    _n.setConditions(
        _conditions.text.trim().isEmpty ? null : _conditions.text.trim());
    await _n.save();
  }

  @override
  Widget build(BuildContext context) {
    if (!_n.loaded) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Site
          Text('Site', style: Theme.of(context).textTheme.titleSmall),
          Autocomplete<String>(
            initialValue: TextEditingValue(text: _site.text),
            optionsBuilder: (tev) {
              if (tev.text.isEmpty) return const Iterable<String>.empty();
              return _siteOptions.where(
                  (o) => o.toLowerCase().contains(tev.text.toLowerCase()));
            },
            onSelected: (v) {
              _site.text = v;
              _n.setSiteName(v);
            },
            fieldViewBuilder: (_, controller, focusNode, __) {
              controller.text = _site.text;
              return TextField(
                controller: controller,
                focusNode: focusNode,
                decoration: const InputDecoration(hintText: 'Site name'),
                onChanged: (v) {
                  _site.text = v;
                  _n.setSiteName(v);
                },
              );
            },
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _lat,
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true, signed: true),
                decoration: const InputDecoration(labelText: 'Latitude'),
                onChanged: (_) => _n.setLatLon(
                    double.tryParse(_lat.text.trim()),
                    double.tryParse(_lon.text.trim())),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _lon,
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true, signed: true),
                decoration: const InputDecoration(labelText: 'Longitude'),
                onChanged: (_) => _n.setLatLon(
                    double.tryParse(_lat.text.trim()),
                    double.tryParse(_lon.text.trim())),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            TextButton.icon(
              icon: const Icon(Icons.my_location, size: 18),
              label: const Text('Use current location'),
              onPressed: _pickOnMap, // simplest: route through map picker;
              // it can also just-use-current via its own button.
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              icon: const Icon(Icons.map, size: 18),
              label: const Text('Pick on map'),
              onPressed: _pickOnMap,
            ),
          ]),

          const SizedBox(height: 16),

          // Notes
          Text('Notes', style: Theme.of(context).textTheme.titleSmall),
          TextField(
            controller: _notes,
            maxLines: 4,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            onChanged: (v) => _n.setNotes(v.trim().isEmpty ? null : v.trim()),
          ),

          const SizedBox(height: 16),

          // Buddies
          Text('Buddies', style: Theme.of(context).textTheme.titleSmall),
          ChipInput(
            initialValues: _n.buddies,
            autocompleteOptions: _buddyOptions,
            onChanged: _n.setBuddies,
          ),

          const SizedBox(height: 16),

          // Tags
          Text('Tags', style: Theme.of(context).textTheme.titleSmall),
          ChipInput(
            initialValues: _n.tags,
            autocompleteOptions: _tagOptions,
            onChanged: _n.setTags,
          ),

          const SizedBox(height: 16),

          // Rating
          Text('Rating', style: Theme.of(context).textTheme.titleSmall),
          StarRating(value: _n.rating, onChanged: _n.setRating),

          const SizedBox(height: 16),

          // Conditions
          Text('Conditions', style: Theme.of(context).textTheme.titleSmall),
          TextField(
            controller: _conditions,
            decoration: const InputDecoration(
              hintText: 'e.g. 8m viz, no current',
            ),
            onChanged: (v) =>
                _n.setConditions(v.trim().isEmpty ? null : v.trim()),
          ),

          const SizedBox(height: 16),

          // Gas mixes ↔ cylinders
          if (widget.gasMixes.isNotEmpty) ...[
            Text('Gas mixes',
                style: Theme.of(context).textTheme.titleSmall),
            for (var i = 0; i < widget.gasMixes.length; i++)
              _GasMixRow(
                index: i,
                mix: widget.gasMixes[i],
                activeSeconds: widget.activeSecondsByMix[i] ?? 0,
                cylinders: _cylinders,
                selectedCylinderId: _n.cylinderByMix[i],
                onChanged: (cylinderId) =>
                    _n.setCylinderForMix(i, cylinderId),
              ),
            const SizedBox(height: 16),
          ],

          // Save
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _n.dirty ? _save : null,
              child: const Text('Save'),
            ),
          ),
        ],
      ),
    );
  }
}

class _GasMixRow extends StatelessWidget {
  final int index;
  final DiveGasMix mix;
  final int activeSeconds;
  final List<Cylinder> cylinders;
  final String? selectedCylinderId;
  final void Function(String? cylinderId) onChanged;

  const _GasMixRow({
    required this.index,
    required this.mix,
    required this.activeSeconds,
    required this.cylinders,
    required this.selectedCylinderId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final mixLabel = '${mix.oxygenPercent}/${mix.heliumPercent}';
    final mins = activeSeconds ~/ 60;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(
          child: Text('Mix ${index + 1} · $mixLabel · ~${mins}m active'),
        ),
        DropdownButton<String?>(
          value: selectedCylinderId,
          hint: const Text('—'),
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('—')),
            for (final c in cylinders)
              DropdownMenuItem<String?>(
                value: c.id,
                child: Text('${c.label} (${c.role})'),
              ),
          ],
          onChanged: onChanged,
        ),
      ]),
    );
  }
}
```

- [ ] **Step 4: Run the test, verify it passes**

Run: `flutter test test/ui/widgets/dive_annotations_section_test.dart`

Expected: 1/1 passing.

- [ ] **Step 5: Run full suite + analyzer**

Run: `flutter analyze lib/ test/` and `flutter test`.

Expected: all green.

- [ ] **Step 6: Commit**

```bash
git add lib/ui/widgets/dive_annotations_section.dart test/ui/widgets/dive_annotations_section_test.dart
git commit -m "feat(annotations): DiveAnnotationsSection composite widget"
```

---

### Task 11: Wire annotations into AppShell + DiveListScreen + DiveDetailScreen

**Files:**
- Modify: `lib/ui/app_shell.dart`
- Modify: `lib/ui/screens/dive_list_screen.dart`
- Modify: `lib/ui/screens/dive_detail_screen.dart`

- [ ] **Step 1: Add `DiveAnnotationsDao` to `AppShell`**

In `lib/ui/app_shell.dart`, add the field, instantiation, and pass-through.

Add the import:

```dart
import '../data/db/dive_annotations_dao.dart';
```

Add the field alongside the other DAOs:

```dart
late final DiveAnnotationsDao _diveAnnotationsDao;
```

In `initState()`:

```dart
_diveAnnotationsDao = DiveAnnotationsDao(widget.db);
```

In the `IndexedStack`'s `DiveListScreen` instantiation, add:

```dart
DiveListScreen(
  notifier: _diveListNotifier,
  diveDao: _diveDao,
  annotationsDao: _diveAnnotationsDao,
  equipmentDao: _equipmentDao,
),
```

(`equipmentDao` is needed because `DiveDetailScreen` will pass it down to `DiveAnnotationsSection`. If `DiveListScreen` already takes `equipmentDao` from the cell-tap-to-dive wiring in Task 12 of the equipment view plan, this is just adding `annotationsDao`.)

- [ ] **Step 2: Plumb both DAOs through `DiveListScreen`**

In `lib/ui/screens/dive_list_screen.dart`, update the constructor:

```dart
class DiveListScreen extends StatefulWidget {
  final DiveListNotifier notifier;
  final DiveDao diveDao;
  final DiveAnnotationsDao annotationsDao;
  final EquipmentDao equipmentDao;

  const DiveListScreen({
    super.key,
    required this.notifier,
    required this.diveDao,
    required this.annotationsDao,
    required this.equipmentDao,
  });
  // ...
}
```

Add the imports at the top:

```dart
import '../../data/db/dive_annotations_dao.dart';
import '../../data/db/equipment_dao.dart';
```

In the `Navigator.push(...)` call where the screen pushes `DiveDetailScreen`, pass the new daos:

```dart
DiveDetailScreen(
  dive: dive,
  dao: widget.diveDao,
  annotationsDao: widget.annotationsDao,
  equipmentDao: widget.equipmentDao,
)
```

- [ ] **Step 3: Embed `DiveAnnotationsSection` into `DiveDetailScreen`**

In `lib/ui/screens/dive_detail_screen.dart`, update the constructor:

```dart
class DiveDetailScreen extends StatefulWidget {
  final Dive dive;
  final DiveDao dao;
  final DiveAnnotationsDao annotationsDao;
  final EquipmentDao equipmentDao;
  const DiveDetailScreen({
    super.key,
    required this.dive,
    required this.dao,
    required this.annotationsDao,
    required this.equipmentDao,
  });
  // ...
}
```

Add the imports:

```dart
import 'dart:convert';
import '../../data/db/dive_annotations_dao.dart';
import '../../data/db/equipment_dao.dart';
import '../../data/models/dive.dart';
import '../../data/sample_codec/active_per_mix.dart';
import '../widgets/dive_annotations_section.dart';
```

In the `build()` method, after the existing profile chart section, add the annotations section. Decode `gasMixesJson` and compute `activeSecondsByMix` from the loaded samples:

```dart
// Decode gas mixes from the dive's JSON column.
final gasMixes = (jsonDecode(dive.gasMixesJson) as List)
    .map((e) => DiveGasMix.fromJson(e as Map<String, dynamic>))
    .toList();

// Active seconds per mix (from already-loaded samples).
Map<int, int> activeByMix = const {};
final samples = _notifier.samples;
if (samples != null) {
  activeByMix = activeSecondsPerMix(
    gasMixIndexes: samples.gasMixIndex,
    sampleCount: samples.sampleCount,
    sampleIntervalMs: samples.sampleIntervalMs,
  );
}
```

(`samples.gasMixIndex` is the already-decoded `Uint8List` view from `SampleCodec.decode`. `samples.sampleIntervalMs` and `samples.sampleCount` are also available — verify against `lib/data/models/sample_set.dart`.)

Then below the existing profile chart, append:

```dart
if (samples != null)
  DiveAnnotationsSection(
    diveId: dive.id,
    gasMixes: gasMixes,
    activeSecondsByMix: activeByMix,
    annotationsDao: widget.annotationsDao,
    equipmentDao: widget.equipmentDao,
  ),
```

If samples haven't loaded yet, the annotations section is hidden until they do (so the gas-mix sub-section has its active-time data).

- [ ] **Step 4: Run analyzer**

Run: `flutter analyze lib/ test/`

Expected: clean. If `DiveListScreen`'s constructor signature change breaks `app_shell.dart` test, update the test setup to pass the new DAOs.

- [ ] **Step 5: Run the full test suite**

Run: `flutter test`

Expected: all tests passing. If any widget test for `DiveDetailScreen` fails because it now requires the new DAO parameters, update the test setup to pass `DiveAnnotationsDao(db)` and `EquipmentDao(db)`.

- [ ] **Step 6: Manual smoke test**

`flutter run -d macos`. Open a dive → verify the annotation section renders below the profile chart, the field labels are present, and entering a site name + tapping Save persists across closing/reopening the screen.

- [ ] **Step 7: Commit**

```bash
git add lib/ui/app_shell.dart lib/ui/screens/dive_list_screen.dart lib/ui/screens/dive_detail_screen.dart
git commit -m "feat(annotations): wire DiveAnnotationsSection into dive detail screen"
```

---

## Self-review

After completing all tasks the spec is fully covered:

- ✅ Schema migration v2 → v3 with `DiveCylinders` table + migration test (Task 1).
- ✅ `DiveAnnotationsDao` with annotation CRUD, distinct lookups, cylinder linkage, and transactional `saveAll` (Tasks 2 + 3).
- ✅ `activeSecondsPerMix` codec helper (Task 4).
- ✅ Pubspec deps + platform permissions (iOS, macOS, Android) (Task 5).
- ✅ `StarRating` widget (Task 6).
- ✅ `ChipInput` widget with autocomplete (Task 7).
- ✅ `DiveAnnotationsNotifier` with dirty tracking (Task 8).
- ✅ `MapPickerScreen` with `flutter_map` + `geolocator` and the OSM tile-URL constant for later swap (Task 9).
- ✅ `DiveAnnotationsSection` composite widget covering all eight UI sub-blocks + Save button (Task 10).
- ✅ Wired into `AppShell` → `DiveListScreen` → `DiveDetailScreen` (Task 11).

## Open verifications during implementation

- The Drift row class for `DiveAnnotations` is named `DiveAnnotation` (singular), shadowing our domain class. Resolve via prefix import in the DAO and notifier files (Task 2 step 4 note).
- `flutter_map ^7.0.0` and `geolocator ^14.0.0` versions resolve cleanly against Dart `^3.11.5`. If `flutter_map ^7.x` rejects, fall back to `^6.1.0` and adapt the `MapOptions` API (Task 9 has an OSM-7.x-flavoured snippet).
- macOS sandbox + location entitlement actually surfaces the permission prompt on first GPS call (Task 11 step 6 manual verification).
- `Dives.gasMixesJson` shape is `List<{'o2': int, 'he': int, 'dil': bool}>`; verified against `lib/data/models/dive.dart:111`.
- `SampleSet.gasMixIndex` is a `Uint8List`; verified against `lib/data/models/sample_set.dart` (or update Task 11's sample access if the field is named differently).
