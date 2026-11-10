# Information Tab v2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship Track 1 of today's plan — a real Divemaster field (schema + sync round-trip), a Dive Computer info section on the Information tab, and a conditional Form/Map tab-group replacing the site form when coords exist.

**Architecture:** Three loosely-coupled changes shipping together: (a) net-new `divemaster` column threaded through schema → model → DAO → notifier → UI → Subsurface bidirectional mapper; (b) read-only `DiveComputer` section appended to `DiveInformationSection` using existing design-system components; (c) the site sub-block inside `DiveAnnotationsSection` extracted to a `SiteFormView` widget and conditionally wrapped in a 2-tab group (`SiteFormView` / `SiteMapView`) when lat+lon are both set.

**Tech Stack:** Flutter, Dart, Drift (local SQLite migration), PowerSync (cloud sync, `SELECT *` rules auto-pick up new columns), Supabase Postgres migration, existing `SectionHeader` / `DataRow` / `NumericReadout` / `StatusDot` / `SiteMiniMap` components.

**Reference spec:** `docs/superpowers/specs/2026-05-12-information-tab-v2-design.md`

---

## File Structure

| File | Action | Responsibility |
|---|---|---|
| `lib/data/db/tables.dart` | Modify | Add `divemaster TextColumn` to `DiveAnnotations` |
| `lib/data/db/database.dart` | Modify | Bump `schemaVersion` 12→13, add migration step |
| `lib/data/db/database.g.dart` | Regen | Drift codegen output (`build_runner` regenerates) |
| `supabase/migrations/0009_dive_annotation_divemaster.sql` | Create | `ALTER TABLE dive_annotations ADD COLUMN divemaster TEXT;` |
| `lib/data/models/annotation.dart` | Modify | Add `final String? divemaster;` + constructor + `copyWith` |
| `lib/data/db/dive_annotations_dao.dart` | Modify | Read/write `divemaster` in `upsert()` + `_rowToModel()` |
| `lib/ui/notifiers/dive_annotations_notifier.dart` | Modify | `String? get divemaster` + `setDivemaster()` |
| `lib/sync/subsurface_git/mapper.dart` | Modify | Emit `annotation.divemaster ?? ''` instead of hardcoded `''` |
| `lib/sync/subsurface_git/subsurface_to_ccrlog_mapper.dart` | Modify | Parse `divemaster` `QuotedLine` into annotation |
| `lib/ui/widgets/dive_annotations_section.dart` | Modify | Divemaster TextField; later: extract site sub-block to `SiteFormView` and wrap in conditional tab-group |
| `lib/ui/widgets/site_form_view.dart` | Create | Extracted site form (autocomplete + lat/lon + buttons) |
| `lib/ui/widgets/site_map_view.dart` | Create | Tab-2 content: wider SiteMiniMap with name+coords overlay, tap → SitesMapScreen |
| `lib/ui/widgets/dive_information_section.dart` | Modify | Append `DiveComputer` section (DC + Sensors + Scrubber sub-blocks) |
| `test/data/db/dive_annotations_dao_divemaster_test.dart` | Create | Round-trip divemaster through DAO upsert + get |
| `test/sync/subsurface_git/mapper_divemaster_test.dart` | Create | Mapper emits real divemaster value |
| `test/sync/subsurface_git/subsurface_to_ccrlog_divemaster_test.dart` | Create | Bootstrap importer reads divemaster |
| `test/ui/widgets/dive_annotations_section_divemaster_test.dart` | Create | Divemaster TextField renders + writes back to notifier |
| `test/ui/widgets/dive_information_section_test.dart` | Modify | DC section assertions added |
| `test/ui/widgets/site_form_view_test.dart` | Create | Site form smoke test |
| `test/ui/widgets/dive_annotations_section_site_tabs_test.dart` | Create | Coords present → tab strip + Map default; coords absent → no tab strip |

---

## Task 1: Schema migration — local Drift

**Files:**
- Modify: `lib/data/db/tables.dart`
- Modify: `lib/data/db/database.dart`
- Regen: `lib/data/db/database.g.dart` (via `build_runner`)

- [ ] **Step 1: Add `divemaster` column to the table definition**

In `lib/data/db/tables.dart`, find the `DiveAnnotations` class (~line 135). Add the column right after `conditions`:

```dart
  TextColumn get conditions => text().nullable()();
  TextColumn get divemaster => text().nullable()();
```

(Keep all other columns unchanged.)

- [ ] **Step 2: Bump schema version + add migration step**

In `lib/data/db/database.dart`, change `schemaVersion` from `12` to `13`:

```dart
  @override
  int get schemaVersion => 13;
```

Then in the `onUpgrade` block, after the existing `if (from < 12)` block, add:

```dart
          if (from < 13) {
            // Divemaster string — new per-annotation field exposing the
            // Subsurface "divemaster" line that we previously emitted as
            // empty. Nullable; existing rows get NULL.
            await m.addColumn(diveAnnotations, diveAnnotations.divemaster);
          }
```

- [ ] **Step 3: Regenerate Drift code**

Run: `dart run build_runner build --delete-conflicting-outputs`
Expected: `database.g.dart` regenerates with `divemaster` references. Should complete in 30–60 s with no errors.

- [ ] **Step 4: Sanity-build**

Run: `flutter analyze lib/data/db/`
Expected: 0 issues.

- [ ] **Step 5: Commit**

```bash
git add lib/data/db/tables.dart lib/data/db/database.dart lib/data/db/database.g.dart
git commit -m "$(cat <<'EOF'
feat(db): add divemaster column to dive_annotations (schema v13)

Net-new nullable TEXT column. Migration from v12 just adds the column;
existing rows get NULL. Subsequent tasks plumb the value through the
model/DAO/UI/sync layers.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Supabase migration

**Files:**
- Create: `supabase/migrations/0009_dive_annotation_divemaster.sql`

- [ ] **Step 1: Write the migration**

Create the file with this exact content:

```sql
-- Adds the divemaster annotation column. CCRLog and Subsurface both
-- model divemaster as a free-text string per dive. Previously the
-- Subsurface-side write was emitted as an empty placeholder; with this
-- column the field round-trips properly through bootstrap import and
-- the CCRLog → Subsurface push.

ALTER TABLE dive_annotations
  ADD COLUMN IF NOT EXISTS divemaster TEXT;
```

- [ ] **Step 2: Verify against the migration set**

Run: `ls supabase/migrations/`
Expected: `0009_dive_annotation_divemaster.sql` appears in order after `0008_sync_health_guards.sql`.

(PowerSync sync rules at `infra/powersync-sync-rules.yaml` use `SELECT *` so the new column is picked up automatically. No rules edit needed.)

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/0009_dive_annotation_divemaster.sql
git commit -m "$(cat <<'EOF'
feat(supabase): migration 0009 — divemaster column on dive_annotations

Mirrors the Drift schema v13 change. PowerSync sync rules use SELECT *
so no rules update is required.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Model + DAO

**Files:**
- Modify: `lib/data/models/annotation.dart`
- Modify: `lib/data/db/dive_annotations_dao.dart`
- Test: `test/data/db/dive_annotations_dao_divemaster_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/data/db/dive_annotations_dao_divemaster_test.dart`:

```dart
import 'package:ccrlogger/data/db/dive_annotations_dao.dart';
import 'package:ccrlogger/data/models/annotation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../_helpers/powersync_test_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('divemaster round-trips through upsert + get', () async {
    final psDb = await openPowerSyncForTest();
    final dao = DiveAnnotationsDao(psDb, FakeSessionSource());
    final now = DateTime.utc(2026, 5, 12);
    final ann = DiveAnnotation(
      diveId: 'dive_dm_1',
      divemaster: 'Alex Marlin',
      createdAt: now,
      updatedAt: now,
    );

    await dao.upsert(ann);
    final back = await dao.get('dive_dm_1');

    expect(back, isNotNull);
    expect(back!.divemaster, 'Alex Marlin');
  });

  test('divemaster null round-trips as null', () async {
    final psDb = await openPowerSyncForTest();
    final dao = DiveAnnotationsDao(psDb, FakeSessionSource());
    final now = DateTime.utc(2026, 5, 12);
    final ann = DiveAnnotation(
      diveId: 'dive_dm_2',
      createdAt: now,
      updatedAt: now,
    );

    await dao.upsert(ann);
    final back = await dao.get('dive_dm_2');

    expect(back, isNotNull);
    expect(back!.divemaster, isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/db/dive_annotations_dao_divemaster_test.dart`
Expected: FAIL — `divemaster` not defined on `DiveAnnotation`.

- [ ] **Step 3: Add `divemaster` to the `DiveAnnotation` model**

In `lib/data/models/annotation.dart`, find the field block (~line 64). Add `divemaster` right after `conditions`:

```dart
  final String? conditions;
  final String? divemaster;
```

Then update the constructor (~line 99) — add `this.divemaster` to the parameter list keeping nullable optional convention:

```dart
  DiveAnnotation({
    required this.diveId,
    this.siteName,
    this.siteLatitude,
    this.siteLongitude,
    this.notes,
    this.buddies = const [],
    this.tags = const [],
    this.rating,
    this.conditions,
    this.divemaster,
    this.suit,
    // ... rest unchanged
```

Also update `copyWith` (search for `copyWith` inside `annotation.dart`). Add a `Value<String?>? divemaster` parameter alongside the existing `conditions` parameter, with the same `Value`-wrapped null-safe pattern other fields use. If `copyWith` uses `Value` wrappers throughout, mirror that pattern; if it uses simple null defaults, mirror that. Just keep the file's existing convention.

Update `toJson`/`fromJson` if present in the file. Add `'divemaster': divemaster` to `toJson`'s map and `divemaster: json['divemaster'] as String?` to `fromJson`.

- [ ] **Step 4: Update the DAO**

In `lib/data/db/dive_annotations_dao.dart`:

**Update INSERT** (~line 62). Add `divemaster` to the column list after `conditions`, and add `a.divemaster` to the values list in the same position:

```dart
        'INSERT INTO dive_annotations '
        '(id, owner_id, dive_id, site_name, site_latitude_e5, site_longitude_e5, '
        'notes, buddies_json, tags_json, rating, conditions, divemaster, '
        'suit, undersuit, weight_system, dpv, camera, '
        // ... rest unchanged
```

```dart
          a.rating,
          a.conditions,
          a.divemaster,
          a.suit,
          // ... rest unchanged
```

(Make sure the `VALUES (?,...)` placeholder count increases to match — add one extra `?` after the `conditions` placeholder.)

**Update UPDATE** (~line 107) — add a line for `divemaster = ?` after `conditions = ?`, and a corresponding `a.divemaster` in the values list:

```dart
        'conditions = ?, '
        'divemaster = ?, '
        'suit = ?, '
        // ... rest unchanged
```

```dart
          a.conditions,
          a.divemaster,
          a.suit,
          // ... rest unchanged
```

**Update `_rowToModel`** (~line 305) — add the read of the column right after `conditions`:

```dart
      conditions: row['conditions'] as String?,
      divemaster: row['divemaster'] as String?,
      suit: row['suit'] as String?,
      // ... rest unchanged
```

- [ ] **Step 5: Run test**

Run: `flutter test test/data/db/dive_annotations_dao_divemaster_test.dart`
Expected: PASS (both tests).

Run: `flutter test test/data/db/`
Expected: every test in `data/db/` still passes (no other test relies on column counts).

Run: `flutter analyze`
Expected: 0 issues.

- [ ] **Step 6: Commit**

```bash
git add lib/data/models/annotation.dart lib/data/db/dive_annotations_dao.dart test/data/db/dive_annotations_dao_divemaster_test.dart
git commit -m "$(cat <<'EOF'
feat: divemaster on DiveAnnotation model + DAO

Round-trips through INSERT/UPDATE/SELECT. Null-tolerant. Tests cover
the round-trip for both populated and null values.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Notifier getter / setter

**Files:**
- Modify: `lib/ui/notifiers/dive_annotations_notifier.dart`

- [ ] **Step 1: Write the failing test**

Append to `test/ui/notifiers/dive_annotations_notifier_test.dart` if it exists, or create it. Find the file first:

Run: `ls test/ui/notifiers/dive_annotations_notifier*.dart 2>/dev/null`

If the file exists, add this test inside the main `void main()`:

```dart
  test('setDivemaster updates value and marks dirty', () async {
    final psDb = await openPowerSyncForTest();
    final annotationsDao = DiveAnnotationsDao(psDb, FakeSessionSource());
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final equipmentDao = EquipmentDao(db, psDb, FakeSessionSource());
    final n = DiveAnnotationsNotifier(annotationsDao, equipmentDao);
    await n.load('dive_dm_3');
    expect(n.divemaster, isNull);

    n.setDivemaster('Alex');

    expect(n.divemaster, 'Alex');
    expect(n.dirty, isTrue);
  });
```

If the file doesn't exist, create it with the test wrapped in `void main()` plus the standard imports — pattern matches `test/ui/widgets/dive_annotations_section_test.dart`.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/notifiers/dive_annotations_notifier_test.dart`
Expected: FAIL — `divemaster` getter not defined.

- [ ] **Step 3: Implement getter and setter**

In `lib/ui/notifiers/dive_annotations_notifier.dart`, find the field-access block (search `String? get conditions`). Add the getter immediately after `conditions`:

```dart
  String? get conditions => _annotation?.conditions;
  String? get divemaster => _annotation?.divemaster;
```

Find the setters section (search `void setConditions`). Add a setter mirroring the pattern:

```dart
  void setDivemaster(String? v) {
    _annotation = _annotation?.copyWith(divemaster: Value(v));
    _markDirty();
  }
```

- [ ] **Step 4: Run test + analyzer**

Run: `flutter test test/ui/notifiers/`
Expected: PASS.

Run: `flutter analyze`
Expected: 0 issues.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/notifiers/dive_annotations_notifier.dart test/ui/notifiers/dive_annotations_notifier_test.dart
git commit -m "$(cat <<'EOF'
feat(ui): divemaster getter + setter on DiveAnnotationsNotifier

Mirrors the conditions/suit/undersuit pattern. setDivemaster marks
the notifier dirty so the existing unsaved-changes guard catches
edits.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Mapper outbound — emit real divemaster

**Files:**
- Modify: `lib/sync/subsurface_git/mapper.dart`
- Test: `test/sync/subsurface_git/mapper_divemaster_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/sync/subsurface_git/mapper_divemaster_test.dart`:

```dart
import 'dart:typed_data';

import 'package:ccrlogger/data/db/database.dart' hide DiveAnnotation;
import 'package:ccrlogger/data/models/annotation.dart';
import 'package:ccrlogger/data/models/dive.dart' show DiveGasMix;
import 'package:ccrlogger/data/models/sample_set.dart';
import 'package:ccrlogger/shearwater/parser/constants.dart' show DiveMode;
import 'package:ccrlogger/sync/subsurface_git/format/subsurface_serializer.dart';
import 'package:ccrlogger/sync/subsurface_git/format/subsurface_format.dart';
import 'package:ccrlogger/sync/subsurface_git/mapper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mapDive emits divemaster from annotation when set', () {
    final mapper = CcrlogToSubsurfaceMapper();
    final ann = DiveAnnotation(
      diveId: 'd1',
      divemaster: 'Alex Marlin',
      createdAt: DateTime.utc(2026, 5, 12),
      updatedAt: DateTime.utc(2026, 5, 12),
    );
    final mapped = mapper.mapDive(
      dive: _testDive(),
      samples: _testSamples(),
      annotation: ann,
      gasMixes: const [],
      tanks: const [],
      cylindersByMixIndex: const {},
      nextSubsurfaceDiveNumber: 1,
    );
    final text = serializeSubsurfaceFile(SubsurfaceFile(lines: mapped.diveLines));
    expect(text, contains('divemaster "Alex Marlin"'));
  });

  test('mapDive emits empty divemaster when annotation field is null', () {
    final mapper = CcrlogToSubsurfaceMapper();
    final ann = DiveAnnotation(
      diveId: 'd1',
      createdAt: DateTime.utc(2026, 5, 12),
      updatedAt: DateTime.utc(2026, 5, 12),
    );
    final mapped = mapper.mapDive(
      dive: _testDive(),
      samples: _testSamples(),
      annotation: ann,
      gasMixes: const [],
      tanks: const [],
      cylindersByMixIndex: const {},
      nextSubsurfaceDiveNumber: 1,
    );
    final text = serializeSubsurfaceFile(SubsurfaceFile(lines: mapped.diveLines));
    expect(text, contains('divemaster ""'));
  });
}

Dive _testDive() => Dive(
      id: 'd1',
      dcSerial: 0xb89641e4,
      dcDiveNumber: 1,
      startTime: 1776611925,
      endTime: 1776611925 + 3450,
      utcOffsetMinutes: null,
      durationSeconds: 3450,
      maxDepthMm: 18000,
      diveMode: DiveMode.ccr.value,
      decoModel: 0,
      gfLow: 50,
      gfHigh: 95,
      atmosphericPressureMbar: 1013,
      waterDensity: 1025,
      logVersion: 17,
      dcModel: 3,
      dcFirmware: 0xa3,
      sampleIntervalMs: 10000,
      gasMixesJson: '',
      tanksJson: null,
      configuredStackSeconds: 25200,
      stackRemainingAtStartSeconds: 10847,
      stackRemainingAtEndSeconds: 7347,
      rawBlob: Uint8List(0),
      parserVersion: 1,
      importedAt: 1776591525,
    );

SampleSet _testSamples() => SampleSet(
      diveId: 'd1',
      sampleCount: 0,
      sampleIntervalMs: 10000,
      depthMeters: Float32List(0),
      temperatureCelsius: Float32List(0),
      ppo2Bar: Float32List(0),
      cellMv0: Float32List(0),
      cellMv1: Float32List(0),
      cellMv2: Float32List(0),
      setpointBar: Float32List(0),
      cns: Float32List(0),
      decoStopDepthMeters: Float32List(0),
      decoTimeSeconds: Int32List(0),
      ttsSeconds: Int32List(0),
      gasMixIndex: Uint8List(0),
      statusFlags: Uint8List(0),
    );
```

If your codebase has a `_threeMinSampleSet` helper in `test/sync/subsurface_git/mapper_test.dart`, prefer reusing it. Otherwise the inline helpers above are fine.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/sync/subsurface_git/mapper_divemaster_test.dart`
Expected: FAIL — the first test fails because the mapper currently emits a hardcoded empty divemaster.

- [ ] **Step 3: Update the mapper**

In `lib/sync/subsurface_git/mapper.dart` find the line emitting divemaster (search `divemaster` in the file). Replace:

```dart
    // Subsurface always emits divemaster + buddy + suit, even when empty.
    lines.add(QuotedLine(key: 'divemaster', value: ''));
```

with:

```dart
    // Subsurface always emits divemaster + buddy + suit, even when empty.
    lines.add(QuotedLine(key: 'divemaster', value: annotation?.divemaster ?? ''));
```

- [ ] **Step 4: Run test + analyzer**

Run: `flutter test test/sync/subsurface_git/mapper_divemaster_test.dart`
Expected: both tests PASS.

Run: `flutter test test/sync/subsurface_git/mapper_test.dart`
Expected: existing mapper tests still PASS.

Run: `flutter analyze`
Expected: 0 issues.

- [ ] **Step 5: Commit**

```bash
git add lib/sync/subsurface_git/mapper.dart test/sync/subsurface_git/mapper_divemaster_test.dart
git commit -m "$(cat <<'EOF'
feat(subsurface): mapper emits real divemaster from annotation

Previously hardcoded to empty. Reads annotation.divemaster, falls
back to "" when null so the line shape stays identical to what
Subsurface itself emits.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Bootstrap importer reads divemaster

**Files:**
- Modify: `lib/sync/subsurface_git/subsurface_to_ccrlog_mapper.dart`
- Test: `test/sync/subsurface_git/subsurface_to_ccrlog_divemaster_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/sync/subsurface_git/subsurface_to_ccrlog_divemaster_test.dart`. The exact API of the importer varies — base the test on what an existing importer test looks like. First inspect:

Run: `ls test/sync/subsurface_git/ | grep -i subsurface_to`

If `subsurface_to_ccrlog_mapper_test.dart` exists, read its structure and mirror it. The test should:

1. Construct a `Dive-NNN` `SubsurfaceFile` (parse from text or build lines directly) that includes `divemaster "Bob"`.
2. Call the import mapper.
3. Assert `imported.annotation?.divemaster == 'Bob'`.

Template:

```dart
import 'package:ccrlogger/sync/subsurface_git/format/subsurface_parser.dart';
import 'package:ccrlogger/sync/subsurface_git/subsurface_to_ccrlog_mapper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('importer copies divemaster from Dive-NNN into annotation', () {
    const text = '''
duration 57:30 min
divemaster "Bob"
buddy "Alice"
suit ""
''';
    final lines = parseSubsurfaceFile(text, kind: SubsurfaceFileKind.dive).lines;
    // ... call the importer with whatever signature it has — typically
    //     SubsurfaceToCcrlogMapper.mapDive(diveLines: ..., divecomputerLines: ...)
    //     returns a struct with `annotation`.
    final imported = /* invoke importer */ ;
    expect(imported.annotation?.divemaster, 'Bob');
  });

  test('importer leaves divemaster null when source has empty value', () {
    const text = '''
duration 57:30 min
divemaster ""
suit ""
''';
    final lines = parseSubsurfaceFile(text, kind: SubsurfaceFileKind.dive).lines;
    final imported = /* invoke importer */ ;
    // We treat empty-string-from-Subsurface as "no divemaster set" so
    // round-tripping unset stays unset, not "" → " " → "".
    expect(imported.annotation?.divemaster, isNull);
  });
}
```

Adapt the importer call to whatever signature `SubsurfaceToCcrlogMapper` exposes.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/sync/subsurface_git/subsurface_to_ccrlog_divemaster_test.dart`
Expected: FAIL — `divemaster` not read by importer; annotation field stays null.

- [ ] **Step 3: Update the importer**

In `lib/sync/subsurface_git/subsurface_to_ccrlog_mapper.dart` find the parsing loop that handles `notes`/`buddy`/`suit` (search `case 'suit':` — there's a `case`-style switch around line 750 based on the earlier grep). Add a `divemaster` case alongside `suit`, using the same "empty → null" convention so an empty `divemaster ""` doesn't accidentally set the field to empty-string-not-null:

```dart
          case 'divemaster':
            if (l.value.isNotEmpty) divemaster = l.value;
            break;
```

Declare the local `String? divemaster;` near the other field locals (alongside `notes`, `suit`, etc.).

Pass `divemaster: divemaster` to the `DiveAnnotation(...)` constructor where it's built at the end of the function.

- [ ] **Step 4: Run test + analyzer**

Run: `flutter test test/sync/subsurface_git/`
Expected: every test passes including the new ones.

Run: `flutter analyze`
Expected: 0 issues.

- [ ] **Step 5: Commit**

```bash
git add lib/sync/subsurface_git/subsurface_to_ccrlog_mapper.dart test/sync/subsurface_git/subsurface_to_ccrlog_divemaster_test.dart
git commit -m "$(cat <<'EOF'
feat(subsurface): importer reads divemaster into annotation

Empty divemaster value (Subsurface's default for unset) maps to null
locally so the column doesn't fill with empty strings.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: Divemaster UI field

**Files:**
- Modify: `lib/ui/widgets/dive_annotations_section.dart`
- Test: `test/ui/widgets/dive_annotations_section_divemaster_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/ui/widgets/dive_annotations_section_divemaster_test.dart`. The existing `test/ui/widgets/dive_annotations_section_test.dart` shows the harness pattern. Use it as the model:

```dart
import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/data/db/dive_annotations_dao.dart';
import 'package:ccrlogger/data/db/equipment_dao.dart';
import 'package:ccrlogger/ui/notifiers/dive_annotations_notifier.dart';
import 'package:ccrlogger/ui/widgets/dive_annotations_section.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../_helpers/powersync_test_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Divemaster field renders + writes back to notifier',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    late final DiveAnnotationsNotifier notifier;
    late final DiveAnnotationsDao annotationsDao;
    late final EquipmentDao equipmentDao;
    await tester.runAsync(() async {
      final psDb = await openPowerSyncForTest();
      annotationsDao = DiveAnnotationsDao(psDb, FakeSessionSource());
      equipmentDao = EquipmentDao(db, psDb, FakeSessionSource());
      notifier = DiveAnnotationsNotifier(annotationsDao, equipmentDao);
      await notifier.load('dive_x');
    });
    addTearDown(notifier.dispose);

    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: DiveAnnotationsSection(
              notifier: notifier,
              gasMixes: const [],
              activeSecondsByMix: const {},
              annotationsDao: annotationsDao,
              equipmentDao: equipmentDao,
            ),
          ),
        ),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();

    expect(find.text('Divemaster'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Divemaster name'),
      'Alex Marlin',
    );
    await tester.pump();

    expect(notifier.divemaster, 'Alex Marlin');
  });
}
```

(If the existing section test uses a different sentinel for finding the field by label, mirror that.)

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/widgets/dive_annotations_section_divemaster_test.dart`
Expected: FAIL — no `Divemaster` text found.

- [ ] **Step 3: Add the Divemaster field to the annotations section**

In `lib/ui/widgets/dive_annotations_section.dart`, find the Buddies field (search `Text('Buddies'`). Add a state controller near the top of the State class:

```dart
  final _divemaster = TextEditingController();
```

Add it to `initState` hydration alongside the existing controllers (look for where `_site.text = ...` is set on load):

```dart
    _divemaster.text = _n.divemaster ?? '';
```

Dispose it next to the others (search `_site.dispose`):

```dart
    _divemaster.dispose();
```

Then in `build`, immediately above the `Text('Buddies'...)` block, add:

```dart
          Text('Divemaster', style: Theme.of(context).textTheme.titleSmall),
          TextField(
            controller: _divemaster,
            decoration: const InputDecoration(hintText: 'Divemaster name'),
            onChanged: (v) =>
                _n.setDivemaster(v.trim().isEmpty ? null : v.trim()),
          ),
          const SizedBox(height: 16),
```

- [ ] **Step 4: Run test + analyzer**

Run: `flutter test test/ui/widgets/dive_annotations_section_divemaster_test.dart`
Expected: PASS.

Run: `flutter test test/ui/widgets/dive_annotations_section_test.dart`
Expected: existing assertions still pass (we only added a field above Buddies).

Run: `flutter analyze`
Expected: 0 issues.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/widgets/dive_annotations_section.dart test/ui/widgets/dive_annotations_section_divemaster_test.dart
git commit -m "$(cat <<'EOF'
feat(ui): Divemaster text field on annotations section

Renders above Buddies. Empty input becomes null per the trim-to-null
pattern other text fields use. With the model/DAO/sync layers from
prior tasks, edits round-trip end-to-end.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: Dive Computer section

**Files:**
- Modify: `lib/ui/widgets/dive_information_section.dart`
- Test: `test/ui/widgets/dive_information_section_test.dart`

- [ ] **Step 1: Add the failing test**

Append to `test/ui/widgets/dive_information_section_test.dart`. The file already has helpers; reuse them.

```dart
  testWidgets('DC section renders Model + Serial + Firmware + Deco + log',
      (tester) async {
    final harness = await setup(tester);
    await pumpSection(
      tester,
      notifier: harness.notifier,
      dive: _testDive(),  // Petrel 3, dcSerial: 0xb89641e4, gfLow 50, gfHigh 95, logVersion 17, sampleIntervalMs 10000
    );

    expect(find.text('DIVE COMPUTER'), findsOneWidget);
    expect(find.text('Shearwater Petrel 3'), findsOneWidget);
    expect(find.text('b89641e4'), findsOneWidget);
    expect(find.text('Bühlmann ZHL-16 · GF 50 / 95'), findsOneWidget);
    expect(find.text('10 s'), findsOneWidget);
    expect(find.textContaining('17'), findsOneWidget); // log version
  });

  testWidgets('DC section renders Scrubber sub-block when configured stack present',
      (tester) async {
    final harness = await setup(tester);
    await pumpSection(
      tester,
      notifier: harness.notifier,
      // configuredStackSeconds = 25200 = 7h, start=10847, end=7347 from _testDive.
      dive: _testDive(),
    );

    expect(find.text('SCRUBBER'), findsOneWidget);
    expect(find.text('7:00'), findsOneWidget); // configured
  });
```

If `_testDive()` already exists in the file, no change is needed; otherwise the existing test file has a similar helper that should already produce a Petrel 3 dive with these values — reuse it.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/widgets/dive_information_section_test.dart`
Expected: FAIL — `DIVE COMPUTER` section header not found.

- [ ] **Step 3: Add the DC section to the widget**

In `lib/ui/widgets/dive_information_section.dart`, find the end of the Column children inside the `build` method (after the Atm. pressure row). Add the new section:

```dart
          const SizedBox(height: Spacing.lg),
          ..._buildDiveComputerSection(context),
```

Then add the helper method on the State class:

```dart
  List<Widget> _buildDiveComputerSection(BuildContext context) {
    final dive = widget.dive;
    final modelName = _modelDisplayName(dive.dcModel);
    final serialHex = dive.dcSerial.toRadixString(16).padLeft(8, '0');
    final firmware = dive.dcFirmware == null
        ? '—'
        : '0x${dive.dcFirmware!.toRadixString(16).toUpperCase()}';
    final decoModelLabel = _decoModelLabel(
      dive.decoModel,
      dive.gfLow,
      dive.gfHigh,
    );
    final sampleInterval = '${(dive.sampleIntervalMs / 1000).round()} s';
    final logVersion =
        '${dive.logVersion}${_isPnf(dive.logVersion) ? ' (PNF)' : ''}';
    final unitsLabel = 'Metric'; // CCRLog always stores metric per CLAUDE.md.

    final children = <Widget>[
      const SectionHeader('Dive computer'),
      components.DataRow(label: 'Model', value: modelName),
      components.DataRow(label: 'Serial', value: serialHex, numeric: true),
      components.DataRow(label: 'Firmware', value: firmware, numeric: true),
      components.DataRow(label: 'Deco model', value: decoModelLabel),
      components.DataRow(
          label: 'Sample interval', value: sampleInterval, numeric: true),
      components.DataRow(label: 'Log version', value: logVersion, numeric: true),
      components.DataRow(label: 'Units', value: unitsLabel),
      const SizedBox(height: Spacing.md),
      const SectionHeader('Sensors'),
      _cellCalibrationRow(context),
      components.DataRow(
          label: 'Calibrated mask',
          value: _calibratedMaskLabel(dive.calibratedSensorMask ?? 0)),
      components.DataRow(label: 'Air-integration', value: _aiModeLabel(dive)),
    ];

    if (dive.configuredStackSeconds != null) {
      children.addAll([
        const SizedBox(height: Spacing.md),
        const SectionHeader('Scrubber'),
        components.DataRow(
          label: 'Configured',
          value: _formatStackHm(dive.configuredStackSeconds!),
          numeric: true,
        ),
        if (dive.stackRemainingAtStartSeconds != null)
          components.DataRow(
            label: 'Remaining start',
            value: _formatStackHm(dive.stackRemainingAtStartSeconds!),
            numeric: true,
          ),
        if (dive.stackRemainingAtEndSeconds != null)
          components.DataRow(
            label: 'Remaining end',
            value: _formatStackHm(dive.stackRemainingAtEndSeconds!),
            numeric: true,
          ),
        if (dive.stackRemainingAtStartSeconds != null &&
            dive.stackRemainingAtEndSeconds != null)
          components.DataRow(
            label: 'Used this dive',
            value: _formatStackHm(
                dive.stackRemainingAtStartSeconds! -
                    dive.stackRemainingAtEndSeconds!),
            numeric: true,
          ),
      ]);
    }

    return children;
  }

  Widget _cellCalibrationRow(BuildContext context) {
    // Sensor calibration JSON is on the dive (sensorCalibrationJson:
    // nullable list-of-doubles). Default Petrel 0.021 when absent.
    final raw = widget.dive.sensorCalibrationJson;
    List<double> cal = const [0.021, 0.021, 0.021];
    if (raw != null && raw.isNotEmpty) {
      try {
        final parsed = (jsonDecode(raw) as List).cast<num>();
        if (parsed.length >= 3) {
          cal = parsed.take(3).map((n) => n.toDouble()).toList();
        }
      } catch (_) {/* fallback to defaults */}
    }
    final scheme = Theme.of(context).colorScheme;
    final cellColors = [
      AppColors.wreck.cell1,
      AppColors.wreck.cell2,
      AppColors.wreck.cell3,
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
      child: Row(
        children: [
          SizedBox(
            width: 130,
            child: Text(
              'Cell calibration',
              style: AppTypography.body.copyWith(color: scheme.outlineVariant),
            ),
          ),
          for (var i = 0; i < 3; i++) ...[
            StatusDot(color: cellColors[i]),
            const SizedBox(width: Spacing.xs),
            NumericReadout(
              cal[i].toStringAsFixed(4),
              size: ReadoutSize.sm,
            ),
            if (i < 2) const SizedBox(width: Spacing.md),
          ],
        ],
      ),
    );
  }

  String _modelDisplayName(int modelIdx) {
    final values = ShearwaterModel.values;
    if (modelIdx < 0 || modelIdx >= values.length) return 'Unknown';
    return switch (values[modelIdx]) {
      ShearwaterModel.predator => 'Shearwater Predator',
      ShearwaterModel.petrel => 'Shearwater Petrel',
      ShearwaterModel.petrel2 => 'Shearwater Petrel 2',
      ShearwaterModel.petrel3 => 'Shearwater Petrel 3',
      ShearwaterModel.nerd => 'Shearwater NERD',
      ShearwaterModel.nerd2 => 'Shearwater NERD 2',
      ShearwaterModel.perdix => 'Shearwater Perdix',
      ShearwaterModel.perdixAi => 'Shearwater Perdix AI',
      ShearwaterModel.perdix2 => 'Shearwater Perdix 2',
      ShearwaterModel.teric => 'Shearwater Teric',
      ShearwaterModel.peregrine => 'Shearwater Peregrine',
      ShearwaterModel.peregrineTx => 'Shearwater Peregrine TX',
      ShearwaterModel.unknown => 'Shearwater (unknown)',
    };
  }

  String _decoModelLabel(int decoCode, int? gfLow, int? gfHigh) {
    final base = switch (decoCode) {
      0 => 'Bühlmann ZHL-16',
      1 => 'VPM-B',
      2 => 'VPM-B/GFS',
      _ => 'Unknown',
    };
    if (decoCode == 0 && gfLow != null && gfHigh != null) {
      return '$base · GF $gfLow / $gfHigh';
    }
    return base;
  }

  bool _isPnf(int logVersion) => logVersion >= 13;

  String _calibratedMaskLabel(int mask) {
    if (mask == 0) return 'None';
    final cells = <String>[];
    if ((mask & 0x1) != 0) cells.add('Cell 1');
    if ((mask & 0x2) != 0) cells.add('Cell 2');
    if ((mask & 0x4) != 0) cells.add('Cell 3');
    return cells.join(', ');
  }

  String _aiModeLabel(Dive dive) {
    // aiMode lives on Dive (logVersion >= 7). Tank-channel count comes
    // from the tanks_json length. Be defensive — both nullable.
    final raw = dive.tanksJson;
    int tanksCount = 0;
    if (raw != null && raw.isNotEmpty) {
      try {
        tanksCount = (jsonDecode(raw) as List).length;
      } catch (_) {}
    }
    if (tanksCount == 0) return 'Off';
    if (tanksCount <= 2) return 'Standard ($tanksCount tank${tanksCount == 1 ? '' : 's'})';
    return 'HP-CCR ($tanksCount tanks)';
  }

  String _formatStackHm(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    return '$h:${m.toString().padLeft(2, '0')}';
  }
```

Add the missing imports at the top of the file:

```dart
import 'dart:convert';

import '../../shearwater/parser/hardware.dart' show ShearwaterModel;
import '../components/numeric_readout.dart';
import '../components/section_header.dart';
import '../components/status_dot.dart';
import '../theme/tokens.dart';
import 'data_row.dart' as components;  // if not already imported
```

(Note: `components` alias may already exist from a previous edit. If so, don't duplicate the import.)

- [ ] **Step 4: Run test + analyzer**

Run: `flutter test test/ui/widgets/dive_information_section_test.dart`
Expected: both new tests PASS plus all the prior tests in the same file.

Run: `flutter analyze`
Expected: 0 issues.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/widgets/dive_information_section.dart test/ui/widgets/dive_information_section_test.dart
git commit -m "$(cat <<'EOF'
feat(ui): Dive Computer section on Information tab

Three sub-blocks (DC / Sensors / Scrubber) rendered as DataRow under
SectionHeader. Cell calibration row uses StatusDot in the locked
cell-palette colours next to each calibration value (4-decimal).
Scrubber sub-block hidden when stack tracking wasn't configured.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 9: Extract SiteFormView

**Files:**
- Create: `lib/ui/widgets/site_form_view.dart`
- Modify: `lib/ui/widgets/dive_annotations_section.dart`
- Test: `test/ui/widgets/site_form_view_test.dart`

- [ ] **Step 1: Identify the site sub-block to extract**

In `lib/ui/widgets/dive_annotations_section.dart`, the site form starts at the `Text('Site', ...)` widget and runs through the lat/lon row and "Use current location" / "Pick on map" buttons, ending around the `const SizedBox(height: 16),` that separates Site from Buddies (or now, Divemaster).

The extracted widget must own:
- The `_site`, `_lat`, `_lon` controllers + `_siteFocus` FocusNode
- The `_useCurrentLocation`, `_pickOnMap` methods
- The `_parseDecimal` helper if private

Extract into a new `StatefulWidget` named `SiteFormView` taking exactly the deps it needs (`DiveAnnotationsNotifier`, `DiveAnnotationsDao`, and a callback `Future<void> Function()? onPickOnMap` that pushes the map picker screen — keep the navigation external so the new widget doesn't depend on the picker screen).

- [ ] **Step 2: Write the failing test**

Create `test/ui/widgets/site_form_view_test.dart`:

```dart
import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/data/db/dive_annotations_dao.dart';
import 'package:ccrlogger/data/db/equipment_dao.dart';
import 'package:ccrlogger/ui/notifiers/dive_annotations_notifier.dart';
import 'package:ccrlogger/ui/widgets/site_form_view.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../_helpers/powersync_test_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('SiteFormView renders Site / Lat / Lon and writes to notifier',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    late final DiveAnnotationsNotifier notifier;
    late final DiveAnnotationsDao annotationsDao;
    await tester.runAsync(() async {
      final psDb = await openPowerSyncForTest();
      annotationsDao = DiveAnnotationsDao(psDb, FakeSessionSource());
      final equipmentDao = EquipmentDao(db, psDb, FakeSessionSource());
      notifier = DiveAnnotationsNotifier(annotationsDao, equipmentDao);
      await notifier.load('dive_y');
    });
    addTearDown(notifier.dispose);

    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SiteFormView(
              notifier: notifier,
              annotationsDao: annotationsDao,
              onPickOnMap: () async {},
            ),
          ),
        ),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();

    expect(find.text('Site'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Site name'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Latitude'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Longitude'), findsOneWidget);

    await tester.enterText(
        find.widgetWithText(TextField, 'Latitude'), '52.2366');
    await tester.enterText(
        find.widgetWithText(TextField, 'Longitude'), '4.9570');
    await tester.pump();

    expect(notifier.siteLatitude, closeTo(52.2366, 0.0001));
    expect(notifier.siteLongitude, closeTo(4.9570, 0.0001));
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `flutter test test/ui/widgets/site_form_view_test.dart`
Expected: FAIL — `SiteFormView` not defined.

- [ ] **Step 4: Create the new widget**

Create `lib/ui/widgets/site_form_view.dart`. Move the site-related code from `dive_annotations_section.dart` verbatim (controllers, focus node, `RawAutocomplete`, lat/lon row, action buttons, `_useCurrentLocation`, `_parseDecimal`). The widget exposes:

```dart
class SiteFormView extends StatefulWidget {
  final DiveAnnotationsNotifier notifier;
  final DiveAnnotationsDao annotationsDao;
  final Future<void> Function()? onPickOnMap;

  const SiteFormView({
    super.key,
    required this.notifier,
    required this.annotationsDao,
    this.onPickOnMap,
  });

  @override
  State<SiteFormView> createState() => _SiteFormViewState();
}
```

`_SiteFormViewState` is the existing state, scoped down to just site/lat/lon concerns. The "Pick on map" button calls `widget.onPickOnMap?.call()` rather than directly pushing a screen.

- [ ] **Step 5: Update the annotations section to use SiteFormView**

In `lib/ui/widgets/dive_annotations_section.dart`, replace the inline site code with a `SiteFormView(...)`. The pick-on-map callback is passed through from the existing implementation. Remove the now-unused private methods + controllers (`_site`, `_lat`, `_lon`, `_siteFocus`, `_useCurrentLocation`, `_pickOnMap`, `_parseDecimal`) from the section.

Add the import:

```dart
import 'site_form_view.dart';
```

- [ ] **Step 6: Run tests + analyzer**

Run: `flutter test test/ui/widgets/`
Expected: all section + form tests PASS.

Run: `flutter analyze`
Expected: 0 issues.

- [ ] **Step 7: Commit**

```bash
git add lib/ui/widgets/site_form_view.dart lib/ui/widgets/dive_annotations_section.dart test/ui/widgets/site_form_view_test.dart
git commit -m "$(cat <<'EOF'
refactor(ui): extract SiteFormView from DiveAnnotationsSection

Verbatim move — same controllers, autocomplete behaviour, and
buttons. The annotations section now embeds <SiteFormView>; the
pick-on-map navigation is hoisted to the parent via an onPickOnMap
callback so the new widget has no screen dependency.

Sets up the next task (tab-group around the form) without conflating
concerns.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 10: SiteMapView widget

**Files:**
- Create: `lib/ui/widgets/site_map_view.dart`
- Test: `test/ui/widgets/site_map_view_test.dart`

- [ ] **Step 1: Failing test**

Create `test/ui/widgets/site_map_view_test.dart`:

```dart
import 'package:ccrlogger/ui/theme/app_theme.dart';
import 'package:ccrlogger/ui/widgets/site_map_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('SiteMapView shows coords label and is tappable',
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        body: SiteMapView(
          lat: 52.2366,
          lon: 4.9570,
          siteName: 'Vinkeveen — de Dierentuin',
          onTap: () => taps++,
        ),
      ),
    ));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect(find.text('Vinkeveen — de Dierentuin'), findsOneWidget);
    expect(find.textContaining('52.2366'), findsOneWidget);
    expect(find.textContaining('4.9570'), findsOneWidget);

    await tester.tap(find.byType(SiteMapView));
    expect(taps, 1);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/widgets/site_map_view_test.dart`
Expected: FAIL — `SiteMapView` not defined.

- [ ] **Step 3: Implement the widget**

Create `lib/ui/widgets/site_map_view.dart`:

```dart
import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'site_mini_map.dart';

/// Tab-2 content of the site tab-group: a wider read-only minimap
/// showing the dive's coords with a name + lat/lon overlay strip.
/// Tap → caller-defined navigation (typically opens SitesMapScreen).
class SiteMapView extends StatelessWidget {
  const SiteMapView({
    super.key,
    required this.lat,
    required this.lon,
    this.siteName,
    this.onTap,
  });

  final double lat;
  final double lon;
  final String? siteName;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final coordsLabel =
        '${lat.toStringAsFixed(4)}, ${lon.toStringAsFixed(4)}';
    return InkWell(
      onTap: onTap,
      child: Stack(
        children: [
          SiteMiniMap(lat: lat, lon: lon, size: 200),
          Positioned(
            left: Spacing.sm,
            right: Spacing.sm,
            bottom: Spacing.sm,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.sm, vertical: Spacing.xs),
              decoration: BoxDecoration(
                color: scheme.surface.withValues(alpha: 0.85),
                borderRadius: Radii.cardBr,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (siteName != null && siteName!.isNotEmpty)
                    Flexible(
                      child: Text(
                        siteName!,
                        style: AppTypography.body.copyWith(
                          color: scheme.onSurface,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  const SizedBox(width: Spacing.sm),
                  Text(
                    coordsLabel,
                    style: AppTypography.readoutSm.copyWith(
                      color: scheme.outlineVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run test + analyzer**

Run: `flutter test test/ui/widgets/site_map_view_test.dart`
Expected: PASS.

Run: `flutter analyze`
Expected: 0 issues.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/widgets/site_map_view.dart test/ui/widgets/site_map_view_test.dart
git commit -m "$(cat <<'EOF'
feat(ui): SiteMapView — read-only mini-map with name+coords overlay

Uses the existing SiteMiniMap scaled to 200px, with an overlay strip
showing site name (truncated) + lat/lon. Tap routes through an
onTap callback so the caller controls navigation. Track 2 will add
zoom-to-dive and satellite toggle to the underlying SiteMiniMap.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 11: Conditional tab-group inside annotations section

**Files:**
- Modify: `lib/ui/widgets/dive_annotations_section.dart`
- Test: `test/ui/widgets/dive_annotations_section_site_tabs_test.dart`

- [ ] **Step 1: Failing test**

Create `test/ui/widgets/dive_annotations_section_site_tabs_test.dart`:

```dart
import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/data/db/dive_annotations_dao.dart';
import 'package:ccrlogger/data/db/equipment_dao.dart';
import 'package:ccrlogger/ui/notifiers/dive_annotations_notifier.dart';
import 'package:ccrlogger/ui/widgets/dive_annotations_section.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../_helpers/powersync_test_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<DiveAnnotationsNotifier> _loadedNotifier(
    WidgetTester tester,
    String diveId, {
    double? lat,
    double? lon,
  }) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    late final DiveAnnotationsNotifier notifier;
    await tester.runAsync(() async {
      final psDb = await openPowerSyncForTest();
      final annotationsDao = DiveAnnotationsDao(psDb, FakeSessionSource());
      final equipmentDao = EquipmentDao(db, psDb, FakeSessionSource());
      notifier = DiveAnnotationsNotifier(annotationsDao, equipmentDao);
      await notifier.load(diveId);
      if (lat != null && lon != null) notifier.setLatLon(lat, lon);
    });
    addTearDown(notifier.dispose);
    return notifier;
  }

  Future<void> pumpSection(
    WidgetTester tester,
    DiveAnnotationsNotifier notifier,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    late final DiveAnnotationsDao annotationsDao;
    late final EquipmentDao equipmentDao;
    await tester.runAsync(() async {
      final psDb = await openPowerSyncForTest();
      annotationsDao = DiveAnnotationsDao(psDb, FakeSessionSource());
      equipmentDao = EquipmentDao(db, psDb, FakeSessionSource());
    });
    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: DiveAnnotationsSection(
              notifier: notifier,
              gasMixes: const [],
              activeSecondsByMix: const {},
              annotationsDao: annotationsDao,
              equipmentDao: equipmentDao,
            ),
          ),
        ),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
  }

  testWidgets('no coords → no tab strip, form alone', (tester) async {
    final n = await _loadedNotifier(tester, 'd_no_coords');
    await pumpSection(tester, n);

    expect(find.text('Site'), findsOneWidget);
    expect(find.text('Form'), findsNothing);
    expect(find.text('Map'), findsNothing);
  });

  testWidgets('coords present → tab strip visible, Map default',
      (tester) async {
    final n = await _loadedNotifier(tester, 'd_with_coords',
        lat: 52.2366, lon: 4.9570);
    await pumpSection(tester, n);

    expect(find.text('Form'), findsOneWidget);
    expect(find.text('Map'), findsOneWidget);
    // Map tab is initial: SiteMapView should be visible (its coords text)
    expect(find.textContaining('52.2366'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/widgets/dive_annotations_section_site_tabs_test.dart`
Expected: FAIL — both tests, because the tab strip doesn't exist.

- [ ] **Step 3: Wrap SiteFormView in a conditional tab-group**

In `lib/ui/widgets/dive_annotations_section.dart` find the `SiteFormView(...)` from Task 9. Replace it with a builder that reads the notifier's coords each rebuild:

```dart
Builder(builder: (context) {
  final lat = _n.siteLatitude;
  final lon = _n.siteLongitude;
  final hasCoords = lat != null && lon != null;
  if (!hasCoords) {
    return SiteFormView(
      notifier: _n,
      annotationsDao: widget.annotationsDao,
      onPickOnMap: _pickOnMap,
    );
  }
  return DefaultTabController(
    length: 2,
    initialIndex: 1, // default to Map
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const TabBar(
          tabs: [
            Tab(text: 'Form'),
            Tab(text: 'Map'),
          ],
          isScrollable: false,
        ),
        SizedBox(
          height: 280,
          child: TabBarView(
            children: [
              SingleChildScrollView(
                child: SiteFormView(
                  notifier: _n,
                  annotationsDao: widget.annotationsDao,
                  onPickOnMap: _pickOnMap,
                ),
              ),
              SiteMapView(
                lat: lat,
                lon: lon,
                siteName: _n.siteName,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SitesMapScreen(
                      dao: widget.annotationsDao,
                      currentLat: lat,
                      currentLon: lon,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}),
```

Add imports if not already present:

```dart
import 'site_map_view.dart';
import '../screens/sites_map_screen.dart';
```

The `_pickOnMap` method (existing or hoisted earlier) stays on the annotations section as the caller of `SiteFormView`'s onPickOnMap callback.

- [ ] **Step 4: Run tests + analyzer + full suite**

Run: `flutter test test/ui/widgets/dive_annotations_section_site_tabs_test.dart`
Expected: PASS.

Run: `flutter test test/ui/widgets/dive_annotations_section_test.dart`
Expected: PASS — existing tests assert on `find.text('Site')` etc., which still match the form view inside the tab structure.

Run: `flutter test`
Expected: full suite green.

Run: `flutter analyze`
Expected: 0 issues.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/widgets/dive_annotations_section.dart test/ui/widgets/dive_annotations_section_site_tabs_test.dart
git commit -m "$(cat <<'EOF'
feat(ui): conditional Form/Map tab-group around site sub-block

When the annotation has no GPS coords, render <SiteFormView> alone —
identical to today's behaviour for new dives. When coords are set,
wrap SiteFormView + SiteMapView in a 2-tab DefaultTabController
defaulting to the Map tab. Tapping the map opens the existing
SitesMapScreen.

Track 2 will polish the map itself (zoom-to-dive, satellite toggle,
provider choice). This task is purely the structural change.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 12: Full-suite verification + push

- [ ] **Step 1: Full sweep**

Run:

```bash
flutter analyze
flutter test
```

Expected: 0 analyzer issues, every test passes.

- [ ] **Step 2: Manual smoke**

Run the app (macOS or iPhone). Walk through:

1. **Existing dive with site coords** — open Dive Detail → site sub-block now shows a Form/Map tab strip, defaulting to Map. Tap the map → opens `SitesMapScreen`. Switch to Form → matches today's editing experience. Type a Divemaster name (above Buddies); save with the AppBar save button; reload the dive — value persists.
2. **Existing dive with no site coords yet** — open Dive Detail → site sub-block looks identical to today (form, no tab strip). Type a site name and "Use current location"; the tab strip should appear once both lat and lon are filled, defaulting to Map.
3. **Information tab** — scroll past Conditions/Environment; the new Dive Computer section shows Model + Serial + Firmware + Deco model + GF + Sample interval + Log version + Units. Sensors block shows three coloured cell dots with calibration values. Scrubber block shows when the dive has stack tracking; hidden for older dives that didn't.
4. **Subsurface push** (against a throwaway clone if you have one) — confirm a dive with a Divemaster name pushes as `divemaster "Name"` rather than `divemaster ""`.

- [ ] **Step 3: Push**

```bash
git push origin main
```

- [ ] **Step 4: Update memory**

Edit `/Users/egbert/.claude/projects/-Users-egbert-Dev-CCRLog-ccrlogger/memory/project_next_session_priority.md`: mark Track 1 (Information Tab v2) as shipped with commit range, note remaining tracks (Track 2 = map polish, Track 3 = dive list, Track 4 = dive detail polish) as the next brainstorming targets.

- [ ] **Step 5: No code commit on Step 4** — the memory file lives outside the repo.

---

## Self-Review

**Spec coverage:**

- Item 1 (Divemaster field) → Tasks 1–7 (schema → model → DAO → notifier → mapper outbound → bootstrap inbound → UI).
- Item 2 (Dive Computer section) → Task 8.
- Item 11 (site tab-group) → Tasks 9–11 (extract SiteFormView → new SiteMapView → conditional wrap).
- Tests called out in spec: schema migration (Task 1 runs Drift's apply through tests; an explicit migration test isn't separately scaffolded but the existing DAO round-trip test in Task 3 exercises the new column post-migration). Model round-trip (Task 3). Mapper outbound (Task 5). Bootstrap import (Task 6). Information widget DC section (Task 8). Site tab-group (Task 11). All covered.

**Placeholder scan:** No TBDs, no "implement later". Some adaptive instructions where a method signature can't be predicted without reading existing code (e.g. Task 6 bootstrap importer call signature, Task 7 widget-finder pattern in existing tests) — those are flagged as "mirror the existing test pattern" with the actual file referenced.

**Type consistency:** `divemaster` is declared `String?` in tables, model, DAO, notifier, mapper, UI — same type everywhere. `SiteFormView` props (notifier, annotationsDao, onPickOnMap) match between widget creation (Task 9) and consumer in tab-group (Task 11). `SiteMapView` props (lat, lon, siteName, onTap) match between Task 10 and Task 11.

**Open observation:** Task 4 (notifier) assumes a `copyWith` accepting `Value<String?>` for divemaster — which matches the pattern already established for other nullable string fields in `DiveAnnotation`. If the existing `copyWith` uses simple positional defaults instead, the implementer adapts to mirror the convention — flagged in the task. No blocker.
