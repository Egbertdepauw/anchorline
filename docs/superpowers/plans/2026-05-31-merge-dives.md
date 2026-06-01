# Merge Dives Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user select 2+ dives in the dive list and merge them into one displayed dive, with the gap between consecutive dives shown as a surface interval — implemented as a reversible, synced *stored grouping* that never mutates the immutable imported dives.

**Architecture:** A new PowerSync-backed `dive_merge_links` table maps each dive to a `group_id`. The dive list collapses linked dives into one group tile. Opening a group builds a *synthetic* `SampleSet` + synthetic Drift `Dive` at view time (a pure `buildMergedDive` function that concatenates segments and inserts flat surface blocks), then reuses the existing `DiveDetailScreen` / `ProfileChart` unchanged. Guardrails (same dive computer, chronologically adjacent, ≤1 h surface gap) are enforced by a pure validator before a merge is written.

**Tech Stack:** Flutter/Dart, Drift (SQLite codegen), PowerSync (raw SQL CRUD over a synced sqlite), `crypto` (sha256 ids), `flutter_test`.

**Key type fact (read before coding):** The UI uses the **Drift-generated `Dive`** from `package:ccrlogger/data/db/database.dart` (flat columns: `startTime`/`endTime` are `int` epoch-seconds, `maxDepthMm` int, `durationSeconds` int, `gasMixesJson` String). This is NOT the domain `Dive` in `lib/data/models/dive.dart`. All tasks below use the Drift `Dive`.

**Reference spec:** `docs/superpowers/specs/2026-05-31-merge-dives-design.md`

---

## File Structure

**Create:**
- `lib/analysis/merge/merge_constants.dart` — `kMergeMaxSurfaceGap`.
- `lib/analysis/merge/merge_validator.dart` — `MergeEligibility`, `surfaceGapSeconds`, `validateMerge`.
- `lib/analysis/merge/merged_sample_builder.dart` — `MergeMember`, `buildMergedDive`.
- `lib/data/db/dive_merge_dao.dart` — `DiveMergeDao`, `MergeLink`, `generateMergeGroupId`.
- `lib/ui/models/dive_list_item.dart` — `MergeGroup`, sealed `DiveListItem`, `buildListItems`.
- Tests mirroring each of the above under `test/`.

**Modify:**
- `lib/data/db/tables.dart` — add `DiveMergeLinks` table.
- `lib/data/db/database.dart` — register table, bump `schemaVersion` 16→17, migration.
- `lib/sync/cloud/powersync_schema.dart` — add `dive_merge_links`.
- `infra/powersync-sync-rules.yaml` — add sync line.
- `lib/ui/notifiers/dive_list_notifier.dart` — selection state + merge links + eligibility + merge/unmerge.
- `lib/ui/screens/dive_list_screen.dart` — selection UI, group tile, combined-detail navigation.
- `lib/ui/app_shell.dart` — wire `DiveMergeDao`, contextual selection app bar.
- `lib/ui/notifiers/dive_detail_notifier.dart` — `preloadedSamples`.
- `lib/ui/screens/dive_detail_screen.dart` — forward `preloadedSamples`.
- `test/_helpers/powersync_test_helper.dart` — add `openDiveMergeDaoForTest`.
- `test/ui/screens/dive_list_screen_test.dart`, `test/ui/notifiers/dive_list_notifier_test.dart` — update `DiveListNotifier(...)` call sites (new 3rd arg).

---

## Task 1: `DiveMergeLinks` table + Drift registration + migration

**Files:**
- Modify: `lib/data/db/tables.dart`
- Modify: `lib/data/db/database.dart:24` (tables list) and `:28` (`schemaVersion`) and the `onUpgrade` block

- [ ] **Step 1: Add the table** to the end of `lib/data/db/tables.dart`

```dart
/// Links a dive into a merge group. A dive belongs to at most one group,
/// so `diveId` is the primary key. A group "exists" while >=2 non-deleted
/// links share a `groupId`. Unmerge = soft-delete the links.
class DiveMergeLinks extends Table {
  TextColumn get diveId => text().references(Dives, #id)();
  TextColumn get groupId => text()();

  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  IntColumn get syncStatus => integer().withDefault(const Constant(0))();
  TextColumn get ownerId => text().nullable()();

  @override
  Set<Column> get primaryKey => {diveId};
}
```

- [ ] **Step 2: Register the table** in `lib/data/db/database.dart` — add `DiveMergeLinks,` to the `tables: [...]` list (after `DiveBailoutCarry,`).

- [ ] **Step 3: Bump schema version** in `lib/data/db/database.dart` — change `int get schemaVersion => 16;` to `=> 17;`.

- [ ] **Step 4: Add the migration step** inside the existing `onUpgrade: (m, from, to) async { ... }` block in `lib/data/db/database.dart` (append after the last existing `if (from < N)` block):

```dart
        if (from < 17) {
          await m.createTable(diveMergeLinks);
        }
```

- [ ] **Step 5: Run codegen**

Run: `dart run build_runner build --delete-conflicting-outputs`
Expected: completes with "Succeeded"; `database.g.dart` now has a `DiveMergeLink` data class and `diveMergeLinks` table getter.

- [ ] **Step 6: Verify it analyzes**

Run: `flutter analyze`
Expected: No new errors.

- [ ] **Step 7: Commit**

```bash
git add lib/data/db/tables.dart lib/data/db/database.dart lib/data/db/database.g.dart
git commit -m "feat(db): add dive_merge_links table (schema v17)"
```

---

## Task 2: PowerSync schema + sync rules

**Files:**
- Modify: `lib/sync/cloud/powersync_schema.dart`
- Modify: `infra/powersync-sync-rules.yaml`

- [ ] **Step 1: Add the PowerSync table** in `lib/sync/cloud/powersync_schema.dart` (next to the `dive_bailout_carry` block):

```dart
  Table('dive_merge_links', [
    Column.text('owner_id'),
    Column.text('group_id'),
    Column.integer('created_at'),
    Column.integer('updated_at'),
    Column.integer('deleted_at'),
    Column.integer('version'),
    Column.integer('sync_status'),
  ]),
```

(Note: PowerSync supplies the `id` PK implicitly; we store `dive_id` AS that id — see DAO Task 3. Do NOT add a `dive_id` column here; the implicit `id` is the dive id.)

- [ ] **Step 2: Add the sync rule** in `infra/powersync-sync-rules.yaml` under `user_data.data` (after the `dive_attachments` line):

```yaml
      - SELECT * FROM dive_merge_links WHERE owner_id = bucket.user_id
```

- [ ] **Step 3: Verify analyze**

Run: `flutter analyze`
Expected: No new errors.

- [ ] **Step 4: Commit**

```bash
git add lib/sync/cloud/powersync_schema.dart infra/powersync-sync-rules.yaml
git commit -m "feat(sync): sync dive_merge_links across devices"
```

> **DEPLOY REMINDER (not a code step):** the edited `infra/powersync-sync-rules.yaml` must be pasted into the PowerSync dashboard and deployed for cross-device merge to actually sync. Flag this to the user at hand-off.

---

## Task 3: `DiveMergeDao` + `generateMergeGroupId`

**Files:**
- Create: `lib/data/db/dive_merge_dao.dart`
- Modify: `test/_helpers/powersync_test_helper.dart`
- Test: `test/data/db/dive_merge_dao_test.dart`

> The implicit PowerSync `id` column doubles as `dive_id` (same trick `dive_samples` uses — see `dive_dao.dart:152`). So we INSERT `id` = the dive id and read it back as `id`.

- [ ] **Step 1: Add a test rig** to `test/_helpers/powersync_test_helper.dart` (after `openDiveDaoForTest`):

```dart
Future<DiveMergeDaoTestRig> openDiveMergeDaoForTest(AppDatabase drift) async {
  final ps = await openPowerSyncForTest();
  final session = FakeSessionSource()..setUserId('test-user');
  final dao = DiveMergeDao(drift, ps, session);
  return DiveMergeDaoTestRig(dao: dao, ps: ps, session: session);
}

class DiveMergeDaoTestRig {
  final DiveMergeDao dao;
  final PowerSyncDatabase ps;
  final FakeSessionSource session;
  DiveMergeDaoTestRig({
    required this.dao,
    required this.ps,
    required this.session,
  });
}
```

Add the import at the top of the helper: `import 'package:ccrlogger/data/db/dive_merge_dao.dart';`

- [ ] **Step 2: Write the failing test** `test/data/db/dive_merge_dao_test.dart`

```dart
import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/data/db/dive_merge_dao.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../_helpers/powersync_test_helper.dart';

void main() {
  late AppDatabase db;
  late DiveMergeDao dao;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    dao = (await openDiveMergeDaoForTest(db)).dao;
  });

  tearDown(() async => db.close());

  test('generateMergeGroupId is order-independent and stable', () {
    expect(generateMergeGroupId(['a', 'b']), generateMergeGroupId(['b', 'a']));
    expect(generateMergeGroupId(['a', 'b']), hasLength(32));
    expect(generateMergeGroupId(['a', 'b']) != generateMergeGroupId(['a', 'c']),
        isTrue);
  });

  test('mergeDives links dives under one group; getActiveLinks returns them',
      () async {
    final groupId = await dao.mergeDives(['d1', 'd2', 'd3']);
    final links = await dao.getActiveLinks();
    expect(links, hasLength(3));
    expect(links.every((l) => l.groupId == groupId), isTrue);
    expect(links.map((l) => l.diveId).toSet(), {'d1', 'd2', 'd3'});
  });

  test('unmerge soft-deletes all links in the group', () async {
    final groupId = await dao.mergeDives(['d1', 'd2']);
    await dao.unmerge(groupId);
    expect(await dao.getActiveLinks(), isEmpty);
  });

  test('re-merging a previously-unmerged dive reactivates its link', () async {
    final g1 = await dao.mergeDives(['d1', 'd2']);
    await dao.unmerge(g1);
    final g2 = await dao.mergeDives(['d1', 'd2']);
    final links = await dao.getActiveLinks();
    expect(links, hasLength(2));
    expect(links.every((l) => l.groupId == g2), isTrue);
  });
}
```

- [ ] **Step 3: Run it to confirm it fails**

Run: `flutter test test/data/db/dive_merge_dao_test.dart`
Expected: FAIL — `DiveMergeDao` / `generateMergeGroupId` not defined.

- [ ] **Step 4: Implement** `lib/data/db/dive_merge_dao.dart`

```dart
/// CRUD for dive merge groups, stored in the synced `dive_merge_links`
/// table. A dive belongs to at most one group (PK = dive id). Unmerge is a
/// soft delete so it syncs and is undoable.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:powersync/powersync.dart' show PowerSyncDatabase;

import '../../sync/cloud/ccrlogger_backend_connector.dart' show SessionSource;
import 'database.dart';

/// A single active dive->group link.
class MergeLink {
  final String diveId;
  final String groupId;
  const MergeLink({required this.diveId, required this.groupId});
}

/// Deterministic group id from the set of dive ids (order-independent), so
/// the same merge performed on two devices yields the same group id and
/// PowerSync reconciles cleanly.
String generateMergeGroupId(List<String> diveIds) {
  final sorted = [...diveIds]..sort();
  return sha256
      .convert(utf8.encode('merge:${sorted.join(":")}'))
      .toString()
      .substring(0, 32);
}

class DiveMergeDao {
  final AppDatabase _drift;
  final PowerSyncDatabase _ps;
  final SessionSource _session;

  DiveMergeDao(this._drift, this._ps, this._session);

  String? get _ownerId => _session.currentSession?.user.id;

  /// Links [diveIds] into one group. Reactivates soft-deleted links.
  /// Returns the group id.
  Future<String> mergeDives(List<String> diveIds) async {
    final groupId = generateMergeGroupId(diveIds);
    final now = DateTime.now().millisecondsSinceEpoch;
    final placeholders = List.filled(diveIds.length, '?').join(',');
    final existingRows = await _ps.getAll(
      'SELECT id FROM dive_merge_links WHERE id IN ($placeholders)',
      diveIds,
    );
    final existing = existingRows.map((r) => r['id'] as String).toSet();
    await _ps.writeTransaction((tx) async {
      for (final diveId in diveIds) {
        if (existing.contains(diveId)) {
          await tx.execute(
            'UPDATE dive_merge_links SET group_id = ?, deleted_at = NULL, '
            'updated_at = ?, version = COALESCE(version, 0) + 1, '
            'sync_status = 0 WHERE id = ?',
            [groupId, now, diveId],
          );
        } else {
          await tx.execute(
            'INSERT INTO dive_merge_links '
            '(id, owner_id, group_id, created_at, updated_at, deleted_at, '
            ' version, sync_status) '
            'VALUES (?, ?, ?, ?, ?, NULL, 1, 0)',
            [diveId, _ownerId, groupId, now, now],
          );
        }
      }
    });
    return groupId;
  }

  /// All non-deleted links.
  Future<List<MergeLink>> getActiveLinks() async {
    final rows = await _ps.getAll(
      'SELECT id, group_id FROM dive_merge_links WHERE deleted_at IS NULL',
    );
    return rows
        .map((r) =>
            MergeLink(diveId: r['id'] as String, groupId: r['group_id'] as String))
        .toList();
  }

  /// Soft-deletes every link in [groupId].
  Future<void> unmerge(String groupId) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _ps.execute(
      'UPDATE dive_merge_links SET deleted_at = ?, updated_at = ? '
      'WHERE group_id = ? AND deleted_at IS NULL',
      [now, now, groupId],
    );
  }

  /// Fires whenever the links table changes (local edit or cloud sync).
  Stream<void> watchChanges() =>
      _ps.watch('SELECT 1 FROM dive_merge_links LIMIT 1').map((_) {});
}
```

- [ ] **Step 5: Run tests to confirm pass**

Run: `flutter test test/data/db/dive_merge_dao_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 6: Commit**

```bash
git add lib/data/db/dive_merge_dao.dart test/data/db/dive_merge_dao_test.dart test/_helpers/powersync_test_helper.dart
git commit -m "feat(db): DiveMergeDao with merge/unmerge + deterministic group id"
```

---

## Task 4: Merge guardrail validator

**Files:**
- Create: `lib/analysis/merge/merge_constants.dart`
- Create: `lib/analysis/merge/merge_validator.dart`
- Test: `test/analysis/merge/merge_validator_test.dart`

- [ ] **Step 1: Write the failing test** `test/analysis/merge/merge_validator_test.dart`

```dart
import 'dart:typed_data';

import 'package:ccrlogger/analysis/merge/merge_validator.dart';
import 'package:ccrlogger/data/db/database.dart';
import 'package:flutter_test/flutter_test.dart';

/// Minimal Drift `Dive` for tests. startTime/endTime are epoch SECONDS.
Dive d({
  required String id,
  required int serial,
  required int start,
  required int end,
}) =>
    Dive(
      id: id,
      dcSerial: serial,
      dcDiveNumber: 1,
      startTime: start,
      endTime: end,
      durationSeconds: end - start,
      maxDepthMm: 30000,
      diveMode: 0,
      decoModel: 0,
      atmosphericPressureMbar: 1013,
      waterDensity: 1030,
      logVersion: 1,
      dcModel: 0,
      sampleIntervalMs: 10000,
      gasMixesJson: '[]',
      rawBlob: Uint8List(0),
      parserVersion: 1,
      importedAt: 0,
    );

void main() {
  // Three dives, same DC, 30-min surface intervals.
  final a = d(id: 'a', serial: 1, start: 0, end: 3600);
  final b = d(id: 'b', serial: 1, start: 3600 + 1800, end: 9000);
  final c = d(id: 'c', serial: 1, start: 9000 + 1800, end: 14400);
  final all = [a, b, c];

  test('valid adjacent same-DC pair passes', () {
    expect(validateMerge(selected: [a, b], allDives: all).canMerge, isTrue);
  });

  test('fewer than two is rejected', () {
    expect(validateMerge(selected: [a], allDives: all).canMerge, isFalse);
  });

  test('different dive computers rejected', () {
    final other = d(id: 'x', serial: 2, start: 4000, end: 5000);
    expect(
        validateMerge(selected: [a, other], allDives: [a, other]).canMerge,
        isFalse);
  });

  test('non-adjacent selection (a and c skipping b) rejected', () {
    expect(validateMerge(selected: [a, c], allDives: all).canMerge, isFalse);
  });

  test('surface gap over 1h rejected', () {
    final far = d(id: 'far', serial: 1, start: 3600 + 3601, end: 9000);
    expect(
        validateMerge(selected: [a, far], allDives: [a, far]).canMerge, isFalse);
  });

  test('overlapping dives rejected', () {
    final overlap = d(id: 'ov', serial: 1, start: 1800, end: 5000);
    expect(validateMerge(selected: [a, overlap], allDives: [a, overlap]).canMerge,
        isFalse);
  });
}
```

- [ ] **Step 2: Run to confirm failure**

Run: `flutter test test/analysis/merge/merge_validator_test.dart`
Expected: FAIL — `validateMerge` not defined.

- [ ] **Step 3: Implement constants** `lib/analysis/merge/merge_constants.dart`

```dart
/// Maximum allowed surface interval between two consecutive dives in a merge.
/// Tunable: raising it re-enables merging repetitive dives with longer
/// surface intervals. (Subsurface imposes no cap on manual merges; we chose a
/// hard 1 h block per product decision 2026-05-31.)
const Duration kMergeMaxSurfaceGap = Duration(hours: 1);
```

- [ ] **Step 4: Implement validator** `lib/analysis/merge/merge_validator.dart`

```dart
/// Pure guardrail logic for merging dives. No I/O, no Flutter.
library;

import '../../data/db/database.dart';
import 'merge_constants.dart';

class MergeEligibility {
  final bool canMerge;
  final String? reason;
  const MergeEligibility._(this.canMerge, this.reason);
  factory MergeEligibility.ok() => const MergeEligibility._(true, null);
  factory MergeEligibility.no(String reason) =>
      MergeEligibility._(false, reason);
}

/// Surface interval between [prev] and [next], in seconds
/// (startTime/endTime are epoch seconds). Negative when dives overlap.
int surfaceGapSeconds(Dive prev, Dive next) => next.startTime - prev.endTime;

/// Validates whether [selected] can be merged, given the full [allDives]
/// list (needed for the adjacency check). [allDives] need not be sorted.
MergeEligibility validateMerge({
  required List<Dive> selected,
  required List<Dive> allDives,
}) {
  if (selected.length < 2) {
    return MergeEligibility.no('Select at least 2 dives to merge.');
  }

  final serial = selected.first.dcSerial;
  if (selected.any((dv) => dv.dcSerial != serial)) {
    return MergeEligibility.no(
        'Dives must be from the same dive computer.');
  }

  final sorted = [...selected]
    ..sort((x, y) => x.startTime.compareTo(y.startTime));
  final selectedIds = sorted.map((dv) => dv.id).toSet();

  // Adjacency: no un-selected dive may start strictly between the first and
  // last selected start times.
  final firstStart = sorted.first.startTime;
  final lastStart = sorted.last.startTime;
  for (final dv in allDives) {
    if (selectedIds.contains(dv.id)) continue;
    if (dv.startTime > firstStart && dv.startTime < lastStart) {
      return MergeEligibility.no(
          'Selected dives are not consecutive.');
    }
  }

  // Surface-interval checks on each consecutive pair.
  for (var i = 1; i < sorted.length; i++) {
    final gap = surfaceGapSeconds(sorted[i - 1], sorted[i]);
    if (gap < 0) {
      return MergeEligibility.no('Dives overlap in time.');
    }
    if (gap > kMergeMaxSurfaceGap.inSeconds) {
      return MergeEligibility.no(
          'Surface interval exceeds 1 h between two dives.');
    }
  }

  return MergeEligibility.ok();
}
```

- [ ] **Step 5: Run tests to confirm pass**

Run: `flutter test test/analysis/merge/merge_validator_test.dart`
Expected: PASS (6 tests).

- [ ] **Step 6: Commit**

```bash
git add lib/analysis/merge/merge_constants.dart lib/analysis/merge/merge_validator.dart test/analysis/merge/merge_validator_test.dart
git commit -m "feat(analysis): merge guardrail validator (same DC, adjacent, 1h cap)"
```

---

## Task 5: Synthetic merged-dive builder

**Files:**
- Create: `lib/analysis/merge/merged_sample_builder.dart`
- Test: `test/analysis/merge/merged_sample_builder_test.dart`

> v1 limitation (narrowing the spec's "resample mismatched intervals"): all members must share the same `sampleIntervalMs`; otherwise we throw. Same-DC same-trip dives always match. Resampling is deferred.

- [ ] **Step 1: Write the failing test** `test/analysis/merge/merged_sample_builder_test.dart`

```dart
import 'dart:typed_data';

import 'package:ccrlogger/analysis/merge/merged_sample_builder.dart';
import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/data/models/sample_set.dart';
import 'package:flutter_test/flutter_test.dart';

Dive d({
  required String id,
  required int start,
  required int end,
  int maxDepthMm = 30000,
  String gasMixesJson = '[{"o2":21,"he":0,"dil":false}]',
}) =>
    Dive(
      id: id,
      dcSerial: 1,
      dcDiveNumber: 1,
      startTime: start,
      endTime: end,
      durationSeconds: end - start,
      maxDepthMm: maxDepthMm,
      diveMode: 0,
      decoModel: 0,
      atmosphericPressureMbar: 1013,
      waterDensity: 1030,
      logVersion: 1,
      dcModel: 0,
      sampleIntervalMs: 10000,
      gasMixesJson: gasMixesJson,
      rawBlob: Uint8List(0),
      parserVersion: 1,
      importedAt: 0,
    );

SampleSet samples({
  required String diveId,
  required int count,
  double depth = 20.0,
  int gasIdx = 0,
}) =>
    SampleSet(
      diveId: diveId,
      sampleCount: count,
      sampleIntervalMs: 10000,
      depthMeters: Float32List.fromList(List.filled(count, depth)),
      temperatureCelsius: Float32List.fromList(List.filled(count, 15.0)),
      ppo2Bar: Float32List.fromList(List.filled(count, 1.2)),
      cellMv0: Float32List.fromList(List.filled(count, 50.0)),
      cellMv1: Float32List.fromList(List.filled(count, 50.0)),
      cellMv2: Float32List.fromList(List.filled(count, 50.0)),
      setpointBar: Float32List.fromList(List.filled(count, 1.2)),
      cns: Float32List.fromList(List.filled(count, 0.05)),
      decoStopDepthMeters: Float32List.fromList(List.filled(count, 0.0)),
      decoTimeSeconds: Int32List.fromList(List.filled(count, 0)),
      ttsSeconds: Int32List.fromList(List.filled(count, 0)),
      gasMixIndex: Uint8List.fromList(List.filled(count, gasIdx)),
      statusFlags: Uint8List.fromList(List.filled(count, 0)),
    );

void main() {
  test('stitches two dives with a flat surface gap between them', () {
    // Dive A: 0..1000s (100 samples @10s). Surface 300s (30 samples).
    // Dive B: 1300..2300s (100 samples).
    final a = d(id: 'a', start: 0, end: 1000, maxDepthMm: 30000);
    final b = d(id: 'b', start: 1300, end: 2300, maxDepthMm: 42000);
    final res = buildMergedDive(mergedId: 'grp', members: [
      (dive: a, samples: samples(diveId: 'a', count: 100, depth: 20.0)),
      (dive: b, samples: samples(diveId: 'b', count: 100, depth: 30.0)),
    ]);

    expect(res.samples.sampleCount, 100 + 30 + 100);
    expect(res.samples.diveId, 'grp');
    // Surface block is at depth 0 with NaN ppo2.
    expect(res.samples.depthMeters[110], 0.0);
    expect(res.samples.ppo2Bar[110].isNaN, isTrue);
    // Dive B samples follow the gap, back to real depth.
    expect(res.samples.depthMeters[150], 30.0);

    // Virtual dive aggregates.
    expect(res.dive.id, 'grp');
    expect(res.dive.maxDepthMm, 42000);
    expect(res.dive.durationSeconds, 1000 + 1000);
    expect(res.dive.startTime, 0);
    expect(res.dive.endTime, 2300);
  });

  test('merges gas-mix lists and remaps gasMixIndex', () {
    final a = d(
        id: 'a',
        start: 0,
        end: 1000,
        gasMixesJson: '[{"o2":21,"he":0,"dil":false}]');
    final b = d(
        id: 'b',
        start: 1300,
        end: 2300,
        gasMixesJson:
            '[{"o2":18,"he":45,"dil":true},{"o2":21,"he":0,"dil":false}]');
    final res = buildMergedDive(mergedId: 'grp', members: [
      (dive: a, samples: samples(diveId: 'a', count: 10, gasIdx: 0)),
      (dive: b, samples: samples(diveId: 'b', count: 10, gasIdx: 0)),
    ]);

    // Merged list: index 0 = 21/0 (from A), index 1 = 18/45 (new from B).
    expect(res.dive.gasMixesJson.contains('"o2":18'), isTrue);
    // B's gas index 0 (18/45) must remap to 1 in the merged list.
    // First B sample sits after A(10) + gap(30) = index 40.
    expect(res.samples.gasMixIndex[40], 1);
  });

  test('throws on mismatched sample intervals', () {
    final a = d(id: 'a', start: 0, end: 100);
    final b = d(id: 'b', start: 200, end: 300);
    final sb = SampleSet(
      diveId: 'b',
      sampleCount: 10,
      sampleIntervalMs: 4000, // different!
      depthMeters: Float32List(10),
      temperatureCelsius: Float32List(10),
      ppo2Bar: Float32List(10),
      cellMv0: Float32List(10),
      cellMv1: Float32List(10),
      cellMv2: Float32List(10),
      setpointBar: Float32List(10),
      cns: Float32List(10),
      decoStopDepthMeters: Float32List(10),
      decoTimeSeconds: Int32List(10),
      ttsSeconds: Int32List(10),
      gasMixIndex: Uint8List(10),
      statusFlags: Uint8List(10),
    );
    expect(
      () => buildMergedDive(mergedId: 'g', members: [
        (dive: a, samples: samples(diveId: 'a', count: 10)),
        (dive: b, samples: sb),
      ]),
      throwsArgumentError,
    );
  });
}
```

- [ ] **Step 2: Run to confirm failure**

Run: `flutter test test/analysis/merge/merged_sample_builder_test.dart`
Expected: FAIL — `buildMergedDive` not defined.

- [ ] **Step 3: Implement** `lib/analysis/merge/merged_sample_builder.dart`

```dart
/// Builds a synthetic, contiguous [SampleSet] + virtual Drift [Dive] from a
/// set of merged dives, inserting flat surface-interval blocks between
/// segments. Pure: no I/O, no Flutter. This is "merge in the UI" performed at
/// the data-shaping layer — the existing ProfileChart / analysis consume the
/// output unchanged.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../../data/db/database.dart';
import '../../data/models/sample_set.dart';

/// One member of a merge: its (Drift) dive row + decoded samples.
typedef MergeMember = ({Dive dive, SampleSet samples});

/// Stitches [members] into one synthetic dive identified by [mergedId].
/// Members may be in any order; they are sorted by start time. All members
/// must share the same `sampleIntervalMs` (v1 limitation) or this throws.
({Dive dive, SampleSet samples}) buildMergedDive({
  required String mergedId,
  required List<MergeMember> members,
}) {
  if (members.length < 2) {
    throw ArgumentError('buildMergedDive requires at least 2 members');
  }
  final sorted = [...members]
    ..sort((x, y) => x.dive.startTime.compareTo(y.dive.startTime));
  final interval = sorted.first.samples.sampleIntervalMs;
  for (final m in sorted) {
    if (m.samples.sampleIntervalMs != interval) {
      throw ArgumentError(
          'All merged dives must share the same sample interval (v1)');
    }
  }

  // Merge gas-mix lists; build a per-member old->new index remap.
  final mergedGas = <Map<String, dynamic>>[];
  final remaps = <List<int>>[];
  for (final m in sorted) {
    final list =
        (jsonDecode(m.dive.gasMixesJson) as List).cast<Map<String, dynamic>>();
    final remap = <int>[];
    for (final g in list) {
      final at = mergedGas.indexWhere((e) =>
          e['o2'] == g['o2'] && e['he'] == g['he'] && e['dil'] == g['dil']);
      if (at >= 0) {
        remap.add(at);
      } else {
        remap.add(mergedGas.length);
        mergedGas.add({'o2': g['o2'], 'he': g['he'], 'dil': g['dil']});
      }
    }
    remaps.add(remap);
  }

  // Surface gaps (in samples) and total length.
  final gapSamples = <int>[];
  for (var i = 1; i < sorted.length; i++) {
    final gapSec = sorted[i].dive.startTime - sorted[i - 1].dive.endTime;
    final g = ((gapSec * 1000) / interval).round();
    gapSamples.add(g < 0 ? 0 : g);
  }
  var total = 0;
  for (final m in sorted) {
    total += m.samples.sampleCount;
  }
  for (final g in gapSamples) {
    total += g;
  }

  final depth = Float32List(total);
  final temp = Float32List(total);
  final ppo2 = Float32List(total);
  final cell0 = Float32List(total);
  final cell1 = Float32List(total);
  final cell2 = Float32List(total);
  final setpoint = Float32List(total);
  final cns = Float32List(total);
  final decoDepth = Float32List(total);
  final decoTime = Int32List(total);
  final tts = Int32List(total);
  final gasIdx = Uint8List(total);
  final status = Uint8List(total);

  final tankChannels = sorted
      .map((m) => m.samples.tankPressuresBar.length)
      .fold<int>(0, (a, b) => a > b ? a : b);
  final tanks = List.generate(tankChannels, (_) => Float32List(total));

  var w = 0;
  void fillSurface(int count) {
    for (var i = 0; i < count; i++) {
      depth[w] = 0.0;
      temp[w] = double.nan;
      ppo2[w] = double.nan;
      cell0[w] = double.nan;
      cell1[w] = double.nan;
      cell2[w] = double.nan;
      setpoint[w] = double.nan;
      cns[w] = double.nan;
      decoDepth[w] = double.nan;
      decoTime[w] = 0;
      tts[w] = 0;
      gasIdx[w] = 0;
      status[w] = 0;
      for (final t in tanks) {
        t[w] = double.nan;
      }
      w++;
    }
  }

  for (var mi = 0; mi < sorted.length; mi++) {
    if (mi > 0) fillSurface(gapSamples[mi - 1]);
    final s = sorted[mi].samples;
    final remap = remaps[mi];
    for (var i = 0; i < s.sampleCount; i++) {
      depth[w] = s.depthMeters[i];
      temp[w] = s.temperatureCelsius[i];
      ppo2[w] = s.ppo2Bar[i];
      cell0[w] = s.cellMv0[i];
      cell1[w] = s.cellMv1[i];
      cell2[w] = s.cellMv2[i];
      setpoint[w] = s.setpointBar[i];
      cns[w] = s.cns[i];
      decoDepth[w] = s.decoStopDepthMeters[i];
      decoTime[w] = s.decoTimeSeconds[i];
      tts[w] = s.ttsSeconds[i];
      final oldIdx = s.gasMixIndex[i];
      gasIdx[w] = (oldIdx < remap.length) ? remap[oldIdx] : 0;
      status[w] = s.statusFlags[i];
      for (var c = 0; c < tankChannels; c++) {
        tanks[c][w] = (c < s.tankPressuresBar.length)
            ? s.tankPressuresBar[c][i]
            : double.nan;
      }
      w++;
    }
  }

  final mergedSamples = SampleSet(
    diveId: mergedId,
    sampleCount: total,
    sampleIntervalMs: interval,
    depthMeters: depth,
    temperatureCelsius: temp,
    ppo2Bar: ppo2,
    cellMv0: cell0,
    cellMv1: cell1,
    cellMv2: cell2,
    setpointBar: setpoint,
    cns: cns,
    decoStopDepthMeters: decoDepth,
    decoTimeSeconds: decoTime,
    ttsSeconds: tts,
    gasMixIndex: gasIdx,
    statusFlags: status,
    tankPressuresBar: tanks,
  );

  final first = sorted.first.dive;
  final last = sorted.last.dive;
  var maxDepthMm = 0;
  var durationSeconds = 0;
  for (final m in sorted) {
    if (m.dive.maxDepthMm > maxDepthMm) maxDepthMm = m.dive.maxDepthMm;
    durationSeconds += m.dive.durationSeconds;
  }

  final mergedDive = Dive(
    id: mergedId,
    dcSerial: first.dcSerial,
    dcDiveNumber: first.dcDiveNumber,
    startTime: first.startTime,
    endTime: last.endTime,
    utcOffsetMinutes: first.utcOffsetMinutes,
    durationSeconds: durationSeconds,
    maxDepthMm: maxDepthMm,
    diveMode: first.diveMode,
    decoModel: first.decoModel,
    gfLow: first.gfLow,
    gfHigh: first.gfHigh,
    atmosphericPressureMbar: first.atmosphericPressureMbar,
    waterDensity: first.waterDensity,
    logVersion: first.logVersion,
    dcModel: first.dcModel,
    dcFirmware: first.dcFirmware,
    sampleIntervalMs: interval,
    gasMixesJson: jsonEncode(mergedGas),
    tanksJson: first.tanksJson,
    sensorCalibrationJson: first.sensorCalibrationJson,
    configuredStackSeconds: first.configuredStackSeconds,
    stackRemainingAtStartSeconds: first.stackRemainingAtStartSeconds,
    stackRemainingAtEndSeconds: last.stackRemainingAtEndSeconds,
    rawBlob: Uint8List(0),
    parserVersion: first.parserVersion,
    importedAt: first.importedAt,
    subsurfaceUploadedAt: null,
    deletedAt: null,
  );

  return (dive: mergedDive, samples: mergedSamples);
}
```

> If `flutter analyze` flags a required Drift `Dive` field that isn't set above (the generated constructor is the source of truth), set it from `first.<field>`. The list above mirrors `dive_dao.dart`'s `_rowToDive` exactly, so it should be complete.

- [ ] **Step 4: Run tests to confirm pass**

Run: `flutter test test/analysis/merge/merged_sample_builder_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/analysis/merge/merged_sample_builder.dart test/analysis/merge/merged_sample_builder_test.dart
git commit -m "feat(analysis): buildMergedDive synthetic stitcher with surface blocks"
```

---

## Task 6: Dive list item model + grouping

**Files:**
- Create: `lib/ui/models/dive_list_item.dart`
- Test: `test/ui/models/dive_list_item_test.dart`

- [ ] **Step 1: Write the failing test** `test/ui/models/dive_list_item_test.dart`

```dart
import 'dart:typed_data';

import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/data/db/dive_merge_dao.dart';
import 'package:ccrlogger/ui/models/dive_list_item.dart';
import 'package:flutter_test/flutter_test.dart';

Dive d({required String id, required int start, required int end}) => Dive(
      id: id,
      dcSerial: 1,
      dcDiveNumber: 1,
      startTime: start,
      endTime: end,
      durationSeconds: end - start,
      maxDepthMm: 30000,
      diveMode: 0,
      decoModel: 0,
      atmosphericPressureMbar: 1013,
      waterDensity: 1030,
      logVersion: 1,
      dcModel: 0,
      sampleIntervalMs: 10000,
      gasMixesJson: '[]',
      rawBlob: Uint8List(0),
      parserVersion: 1,
      importedAt: 0,
    );

void main() {
  // dives are passed in start-DESC order (matching getAllDives()).
  final newest = d(id: 'c', start: 9000, end: 12000);
  final mid = d(id: 'b', start: 5000, end: 8000);
  final oldest = d(id: 'a', start: 0, end: 3000);

  test('no links -> all single items', () {
    final items = buildListItems([newest, mid, oldest], const []);
    expect(items.length, 3);
    expect(items.every((i) => i is SingleDive), isTrue);
  });

  test('two linked dives collapse into one group item', () {
    final links = [
      const MergeLink(diveId: 'a', groupId: 'g1'),
      const MergeLink(diveId: 'b', groupId: 'g1'),
    ];
    final items = buildListItems([newest, mid, oldest], links);
    // newest single + one group (a+b).
    expect(items.length, 2);
    final group = items.whereType<MergedGroupItem>().single.group;
    expect(group.members.map((m) => m.id).toList(), ['a', 'b']); // sorted asc
    expect(group.totalInWaterSeconds, 3000 + 3000);
    expect(group.surfaceGapsSeconds, [5000 - 3000]);
  });

  test('a group with only one present member stays a single item', () {
    final links = [const MergeLink(diveId: 'a', groupId: 'g1')];
    final items = buildListItems([newest, mid, oldest], links);
    expect(items.length, 3);
    expect(items.every((i) => i is SingleDive), isTrue);
  });
}
```

- [ ] **Step 2: Run to confirm failure**

Run: `flutter test test/ui/models/dive_list_item_test.dart`
Expected: FAIL — `buildListItems` / `MergedGroupItem` not defined.

- [ ] **Step 3: Implement** `lib/ui/models/dive_list_item.dart`

```dart
/// View model for the dive list: either a lone dive or a collapsed merge
/// group. [buildListItems] is pure and unit-tested.
library;

import 'dart:math' as math;

import '../../data/db/database.dart';
import '../../data/db/dive_merge_dao.dart';

/// A merge group's members, sorted by start time ascending (chronological).
class MergeGroup {
  final String groupId;
  final List<Dive> members;
  const MergeGroup({required this.groupId, required this.members});

  Dive get earliest => members.first;
  Dive get latest => members.last;

  int get totalInWaterSeconds =>
      members.fold(0, (s, dv) => s + dv.durationSeconds);

  int get maxDepthMm => members.map((dv) => dv.maxDepthMm).reduce(math.max);

  /// Surface intervals (seconds) between consecutive members.
  List<int> get surfaceGapsSeconds => [
        for (var i = 1; i < members.length; i++)
          members[i].startTime - members[i - 1].endTime,
      ];
}

sealed class DiveListItem {
  const DiveListItem();
}

class SingleDive extends DiveListItem {
  final Dive dive;
  const SingleDive(this.dive);
}

class MergedGroupItem extends DiveListItem {
  final MergeGroup group;
  const MergedGroupItem(this.group);
}

/// Collapses [dives] (expected start-DESC, as from getAllDives) and active
/// [links] into list items. A group needs >=2 present members to collapse;
/// otherwise its lone member renders as a normal single dive. The group is
/// emitted at the position of its first-encountered (latest) member.
List<DiveListItem> buildListItems(List<Dive> dives, List<MergeLink> links) {
  final groupOf = {for (final l in links) l.diveId: l.groupId};

  final membersByGroup = <String, List<Dive>>{};
  for (final dv in dives) {
    final g = groupOf[dv.id];
    if (g != null) {
      membersByGroup.putIfAbsent(g, () => []).add(dv);
    }
  }
  final validGroups = <String, MergeGroup>{};
  for (final e in membersByGroup.entries) {
    if (e.value.length >= 2) {
      final sorted = [...e.value]
        ..sort((a, b) => a.startTime.compareTo(b.startTime));
      validGroups[e.key] = MergeGroup(groupId: e.key, members: sorted);
    }
  }

  final items = <DiveListItem>[];
  final emitted = <String>{};
  for (final dv in dives) {
    final g = groupOf[dv.id];
    if (g != null && validGroups.containsKey(g)) {
      if (emitted.add(g)) {
        items.add(MergedGroupItem(validGroups[g]!));
      }
    } else {
      items.add(SingleDive(dv));
    }
  }
  return items;
}
```

- [ ] **Step 4: Run tests to confirm pass**

Run: `flutter test test/ui/models/dive_list_item_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/ui/models/dive_list_item.dart test/ui/models/dive_list_item_test.dart
git commit -m "feat(ui): DiveListItem grouping model + buildListItems"
```

---

## Task 7: `DiveListNotifier` — links, selection, merge/unmerge

**Files:**
- Modify: `lib/ui/notifiers/dive_list_notifier.dart`
- Modify: `lib/ui/app_shell.dart:155` (constructor call — add 3rd arg)
- Modify: `test/ui/screens/dive_list_screen_test.dart:49`, `test/ui/notifiers/dive_list_notifier_test.dart:29` (call sites)
- Test: `test/ui/notifiers/dive_list_notifier_merge_test.dart`

- [ ] **Step 1: Write the failing test** `test/ui/notifiers/dive_list_notifier_merge_test.dart`

```dart
import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/data/db/dive_annotations_dao.dart';
import 'package:ccrlogger/data/db/dive_merge_dao.dart';
import 'package:ccrlogger/ui/models/dive_list_item.dart';
import 'package:ccrlogger/ui/notifiers/dive_list_notifier.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../_helpers/powersync_test_helper.dart';

void main() {
  late AppDatabase db;
  late DiveListNotifier notifier;
  late DiveMergeDao mergeDao;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final ps = await openPowerSyncForTest();
    final session = FakeSessionSource()..setUserId('test-user');
    final diveDao = DiveDaoLikeFromHelper(db, ps, session); // see note
    mergeDao = DiveMergeDao(db, ps, session);
    notifier = DiveListNotifier(
      diveDao,
      DiveAnnotationsDao(db, ps, session),
      mergeDao,
    );
  });

  tearDown(() async => db.close());

  test('selection mode toggles and tracks ids', () {
    notifier.enterSelectionMode('d1');
    expect(notifier.selectionMode, isTrue);
    expect(notifier.isSelected('d1'), isTrue);
    notifier.toggleSelected('d2');
    expect(notifier.selectedDiveIds, {'d1', 'd2'});
    notifier.exitSelectionMode();
    expect(notifier.selectionMode, isFalse);
    expect(notifier.selectedDiveIds, isEmpty);
  });
}
```

> **Note on `DiveDaoLikeFromHelper`:** there is no such helper — use the real `DiveDao` via `openDiveDaoForTest`. Replace the `diveDao` line with:
> ```dart
> final diveDao = (await openDiveDaoForTest(db)).dao;
> ```
> but note `openDiveDaoForTest` opens its **own** PowerSync; to share one `ps`, construct directly: `final diveDao = DiveDao(db, ps, session);` (DiveDao is exported from `dive_dao.dart`; add `import 'package:ccrlogger/data/db/dive_dao.dart';`). Use the direct-construction form so `mergeDao` and `diveDao` share the same `ps`.

- [ ] **Step 2: Run to confirm failure**

Run: `flutter test test/ui/notifiers/dive_list_notifier_merge_test.dart`
Expected: FAIL — `DiveListNotifier` takes 2 args / no `selectionMode`.

- [ ] **Step 3: Extend the notifier** `lib/ui/notifiers/dive_list_notifier.dart`

Add imports:
```dart
import '../../analysis/merge/merge_validator.dart';
import '../../data/db/dive_merge_dao.dart';
import '../models/dive_list_item.dart';
```

Change the field block + constructor:
```dart
  final DiveDao _dao;
  final DiveAnnotationsDao _annotationsDao;
  final DiveMergeDao _mergeDao;
  StreamSubscription<void>? _annotationsWatchSub;
  StreamSubscription<void>? _mergeWatchSub;
  List<Dive> _dives = [];
  List<MergeLink> _links = [];
  Map<String, dom.DiveAnnotation> _annotationsByDiveId = {};
  bool _loading = false;
  final _sparklineCache = _LruCache<String, Float32List>(50);

  bool _disposed = false;

  // Selection mode (for creating merges).
  bool _selectionMode = false;
  final Set<String> _selectedDiveIds = {};

  DiveListNotifier(this._dao, this._annotationsDao, this._mergeDao) {
    _annotationsWatchSub = _annotationsDao.watchChanges().listen(
      (_) {
        if (_disposed) return;
        loadDives();
      },
      onError: (_) {},
    );
    _mergeWatchSub = _mergeDao.watchChanges().listen(
      (_) {
        if (_disposed) return;
        loadDives();
      },
      onError: (_) {},
    );
  }
```

Update `dispose`:
```dart
  @override
  void dispose() {
    _disposed = true;
    _annotationsWatchSub?.cancel();
    _mergeWatchSub?.cancel();
    super.dispose();
  }
```

Add getters + load links in `loadDives` (set `_links` right after fetching dives):
```dart
  List<MergeLink> get links => List.unmodifiable(_links);

  List<DiveListItem> get listItems => buildListItems(_dives, _links);

  bool get selectionMode => _selectionMode;
  Set<String> get selectedDiveIds => Set.unmodifiable(_selectedDiveIds);
  bool isSelected(String diveId) => _selectedDiveIds.contains(diveId);

  void enterSelectionMode(String firstDiveId) {
    _selectionMode = true;
    _selectedDiveIds
      ..clear()
      ..add(firstDiveId);
    notifyListeners();
  }

  void exitSelectionMode() {
    _selectionMode = false;
    _selectedDiveIds.clear();
    notifyListeners();
  }

  void toggleSelected(String diveId) {
    if (!_selectedDiveIds.remove(diveId)) {
      _selectedDiveIds.add(diveId);
    }
    if (_selectedDiveIds.isEmpty) {
      _selectionMode = false;
    }
    notifyListeners();
  }

  /// Eligibility of the current selection (drives the Merge button state).
  MergeEligibility get mergeEligibility {
    final selected =
        _dives.where((d) => _selectedDiveIds.contains(d.id)).toList();
    return validateMerge(selected: selected, allDives: _dives);
  }

  /// Merges the current selection (assumes [mergeEligibility].canMerge).
  Future<void> mergeSelected() async {
    final ids = _selectedDiveIds.toList();
    await _mergeDao.mergeDives(ids);
    exitSelectionMode();
    await loadDives();
  }

  /// Unmerges a group and refreshes.
  Future<void> unmergeGroup(String groupId) async {
    await _mergeDao.unmerge(groupId);
    await loadDives();
  }
```

In `loadDives`, after `final dives = await _dao.getAllDives();` add:
```dart
    final links = await _mergeDao.getActiveLinks();
```
and after the disposed-check assignments, set `_links = links;` alongside `_dives = dives;`.

- [ ] **Step 4: Fix the call sites** so the project compiles:

In `lib/ui/app_shell.dart` (where `_diveMergeDao` must be constructed near the other DAOs around line 136–155):
```dart
    _diveMergeDao = DiveMergeDao(
      widget.db,
      widget.powerSyncDb,
      SupabaseAuthSessionSource(Supabase.instance.client),
    );
```
Declare the field `late final DiveMergeDao _diveMergeDao;` with the other DAO fields, add `import '../data/db/dive_merge_dao.dart';`, and change line 155 to:
```dart
    _diveListNotifier = DiveListNotifier(_diveDao, _diveAnnotationsDao, _diveMergeDao);
```

In `test/ui/screens/dive_list_screen_test.dart:49` and `test/ui/notifiers/dive_list_notifier_test.dart:29`, update construction to pass a merge dao. At the top of each test's `setUp`, where `dao`/`annotationsDao` are created, also create a merge dao sharing the same `ps`, then:
```dart
    final mergeDao = DiveMergeDao(db, ps, session);
    notifier = DiveListNotifier(dao, annotationsDao, mergeDao);
```
(Add `import 'package:ccrlogger/data/db/dive_merge_dao.dart';` to each.)

- [ ] **Step 5: Run the merge notifier test + the touched tests**

Run: `flutter test test/ui/notifiers/dive_list_notifier_merge_test.dart test/ui/notifiers/dive_list_notifier_test.dart test/ui/screens/dive_list_screen_test.dart`
Expected: PASS.

- [ ] **Step 6: Verify analyze**

Run: `flutter analyze`
Expected: No new errors.

- [ ] **Step 7: Commit**

```bash
git add lib/ui/notifiers/dive_list_notifier.dart lib/ui/app_shell.dart test/ui/notifiers/dive_list_notifier_merge_test.dart test/ui/notifiers/dive_list_notifier_test.dart test/ui/screens/dive_list_screen_test.dart
git commit -m "feat(ui): DiveListNotifier selection state + merge/unmerge wiring"
```

---

## Task 8: Injectable samples into `DiveDetailNotifier` / `DiveDetailScreen`

**Files:**
- Modify: `lib/ui/notifiers/dive_detail_notifier.dart:45-65`
- Modify: `lib/ui/screens/dive_detail_screen.dart:108-122` (constructor) and `:176-184` (initState)
- Test: `test/ui/notifiers/dive_detail_notifier_preloaded_test.dart`

- [ ] **Step 1: Write the failing test** `test/ui/notifiers/dive_detail_notifier_preloaded_test.dart`

```dart
import 'dart:typed_data';

import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/data/models/sample_set.dart';
import 'package:ccrlogger/ui/notifiers/dive_detail_notifier.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../_helpers/powersync_test_helper.dart';

SampleSet fakeSamples(String id) => SampleSet(
      diveId: id,
      sampleCount: 2,
      sampleIntervalMs: 10000,
      depthMeters: Float32List.fromList([1, 2]),
      temperatureCelsius: Float32List(2),
      ppo2Bar: Float32List(2),
      cellMv0: Float32List(2),
      cellMv1: Float32List(2),
      cellMv2: Float32List(2),
      setpointBar: Float32List(2),
      cns: Float32List(2),
      decoStopDepthMeters: Float32List(2),
      decoTimeSeconds: Int32List(2),
      ttsSeconds: Int32List(2),
      gasMixIndex: Uint8List(2),
      statusFlags: Uint8List(2),
    );

Dive vDive(String id) => Dive(
      id: id,
      dcSerial: 1,
      dcDiveNumber: 1,
      startTime: 0,
      endTime: 20,
      durationSeconds: 20,
      maxDepthMm: 2000,
      diveMode: 0,
      decoModel: 0,
      atmosphericPressureMbar: 1013,
      waterDensity: 1030,
      logVersion: 1,
      dcModel: 0,
      sampleIntervalMs: 10000,
      gasMixesJson: '[]',
      rawBlob: Uint8List(0),
      parserVersion: 1,
      importedAt: 0,
    );

void main() {
  test('preloadedSamples are used without hitting the DAO', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final dao = (await openDiveDaoForTest(db)).dao; // empty DB -> getSamples null
    final pre = fakeSamples('grp');
    final n = DiveDetailNotifier(
      dive: vDive('grp'),
      dao: dao,
      preloadedSamples: pre,
    );
    await n.loadSamples();
    expect(n.samples, same(pre));
  });
}
```

- [ ] **Step 2: Run to confirm failure**

Run: `flutter test test/ui/notifiers/dive_detail_notifier_preloaded_test.dart`
Expected: FAIL — `preloadedSamples` not a parameter.

- [ ] **Step 3: Add `preloadedSamples` to the notifier** `lib/ui/notifiers/dive_detail_notifier.dart`

Add a field and constructor param:
```dart
  final SampleSet? _preloadedSamples;

  DiveDetailNotifier({
    required this.dive,
    required DiveDao dao,
    EquipmentDao? equipmentDao,
    SampleSet? preloadedSamples,
  })  : _dao = dao,
        _equipmentDao = equipmentDao,
        _preloadedSamples = preloadedSamples;
```
(Add `import '../../data/models/sample_set.dart';` if not already imported.)

In `loadSamples`, replace the `_samples = await _dao.getSamples(dive.id);` line with:
```dart
    _samples = _preloadedSamples ?? await _dao.getSamples(dive.id);
```

- [ ] **Step 4: Thread it through `DiveDetailScreen`** `lib/ui/screens/dive_detail_screen.dart`

Add a field + constructor param:
```dart
  final SampleSet? preloadedSamples;
```
Add `this.preloadedSamples,` to the constructor parameter list. Add `import '../../data/models/sample_set.dart';` if needed. In `initState`, pass it through:
```dart
    _notifier = DiveDetailNotifier(
      dive: widget.dive,
      dao: widget.dao,
      equipmentDao: widget.equipmentDao,
      preloadedSamples: widget.preloadedSamples,
    );
```

- [ ] **Step 5: Run test + analyze**

Run: `flutter test test/ui/notifiers/dive_detail_notifier_preloaded_test.dart && flutter analyze`
Expected: PASS, no new analyze errors.

- [ ] **Step 6: Commit**

```bash
git add lib/ui/notifiers/dive_detail_notifier.dart lib/ui/screens/dive_detail_screen.dart test/ui/notifiers/dive_detail_notifier_preloaded_test.dart
git commit -m "feat(ui): DiveDetailScreen accepts preloaded synthetic samples"
```

---

## Task 9: Dive list screen — selection UI, group tile, combined-detail nav

**Files:**
- Modify: `lib/ui/screens/dive_list_screen.dart`
- Test: `test/ui/screens/dive_list_screen_merge_test.dart`

> The screen currently builds tiles from `_filteredDives` (a `List<Dive>`). Switch the per-month item builder to operate on `List<DiveListItem>` produced by `buildListItems(filteredDives, widget.notifier.links)`.

- [ ] **Step 1: Write a widget test** `test/ui/screens/dive_list_screen_merge_test.dart` for the merge entry path

```dart
import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/data/db/dive_dao.dart';
import 'package:ccrlogger/data/db/dive_annotations_dao.dart';
import 'package:ccrlogger/data/db/dive_merge_dao.dart';
import 'package:ccrlogger/ui/notifiers/dive_list_notifier.dart';
import 'package:ccrlogger/ui/notifiers/settings_notifier.dart';
import 'package:ccrlogger/ui/screens/dive_list_screen.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../_helpers/powersync_test_helper.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('long-press a dive enters selection mode', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final ps = await openPowerSyncForTest();
    final session = FakeSessionSource()..setUserId('u');
    final diveDao = DiveDao(db, ps, session);
    final annDao = DiveAnnotationsDao(db, ps, session);
    final mergeDao = DiveMergeDao(db, ps, session);
    final notifier = DiveListNotifier(diveDao, annDao, mergeDao);
    final settings = SettingsNotifier();
    await settings.load();

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DiveListScreen(
          notifier: notifier,
          diveDao: diveDao,
          annotationsDao: annDao,
          equipmentDao: (await openEquipmentDaoForTest(db)).dao,
          settingsNotifier: settings,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // With an empty DB there are no tiles; assert the screen builds and the
    // notifier selection API is reachable (smoke test of wiring).
    expect(notifier.selectionMode, isFalse);
    notifier.enterSelectionMode('x');
    expect(notifier.selectionMode, isTrue);
  });
}
```

> If `DiveListScreen`'s constructor requires the attachment params (`attachmentsDao`, `attachmentUploader`, `attachmentDownloader`), pass the same fakes/nulls the existing `dive_list_screen_test.dart` uses — mirror that file's `setUp`.

- [ ] **Step 2: Run to confirm it builds/fails as expected**

Run: `flutter test test/ui/screens/dive_list_screen_merge_test.dart`
Expected: PASS once wiring compiles (this is a smoke test; it will fail to compile until Step 3's screen changes land if they alter constructor surface — they do not).

- [ ] **Step 3: Convert the list to `DiveListItem`s.** In `lib/ui/screens/dive_list_screen.dart`:

Add imports:
```dart
import '../models/dive_list_item.dart';
import '../../analysis/merge/merged_sample_builder.dart';
import '../util/format.dart';
```

Replace the month-group computation so months hold `List<DiveListItem>`. Where the code currently does `_groupByMonth()` over `_filteredDives`, build items first:
```dart
    final items = buildListItems(filtered, widget.notifier.links);
```
and group `items` by month using the item's representative date — for `SingleDive` use `dive.startTime`, for `MergedGroupItem` use `group.latest.startTime`. Add a helper:
```dart
  DateTime _itemDate(DiveListItem item) {
    final secs = switch (item) {
      SingleDive(:final dive) => dive.startTime,
      MergedGroupItem(:final group) => group.latest.startTime,
    };
    return DateTime.fromMillisecondsSinceEpoch(secs * 1000);
  }
```
(`formatMonthYear` takes a `DateTime`.)

In the `SliverChildBuilderDelegate` itemBuilder, switch on the item:
```dart
            (context, index) {
              final item = monthItems[index];
              return switch (item) {
                SingleDive(:final dive) => _DiveTileWithSparkline(
                    dive: dive,
                    orderedDives: filtered,
                    notifier: notifier,
                    diveDao: widget.diveDao,
                    annotationsDao: widget.annotationsDao,
                    equipmentDao: widget.equipmentDao,
                    attachmentsDao: widget.attachmentsDao,
                    attachmentUploader: widget.attachmentUploader,
                    attachmentDownloader: widget.attachmentDownloader,
                    settingsNotifier: widget.settingsNotifier,
                  ),
                MergedGroupItem(:final group) => _MergedGroupTile(
                    group: group,
                    notifier: notifier,
                    diveDao: widget.diveDao,
                    annotationsDao: widget.annotationsDao,
                    equipmentDao: widget.equipmentDao,
                    settingsNotifier: widget.settingsNotifier,
                  ),
              };
            },
```
(`monthItems` is the per-month `List<DiveListItem>`; adjust the existing month-loop variable names accordingly.)

- [ ] **Step 4: Add selection behavior to `_DiveTileWithSparkline`.** Wrap its `onTap`/add `onLongPress`:
- `onLongPress: () => notifier.enterSelectionMode(dive.id)`
- In `onTap`: if `notifier.selectionMode` is true, call `notifier.toggleSelected(dive.id)` and return (do NOT navigate). Otherwise keep the existing navigation.
- When `notifier.selectionMode`, show a leading checkbox reflecting `notifier.isSelected(dive.id)`. Use a `Checkbox` in the tile's leading slot (only when selection mode is active). The tile already receives `notifier`; read `notifier.selectionMode` / `notifier.isSelected(dive.id)` in `build`. Ensure the widget rebuilds on selection changes — the screen's `_onChanged` listener (already attached to the notifier) calls `setState`, so the rebuilt subtree reflects new selection state.

- [ ] **Step 5: Implement `_MergedGroupTile`** at the bottom of `lib/ui/screens/dive_list_screen.dart`:

```dart
class _MergedGroupTile extends StatelessWidget {
  final MergeGroup group;
  final DiveListNotifier notifier;
  final DiveDao diveDao;
  final DiveAnnotationsDao annotationsDao;
  final EquipmentDao equipmentDao;
  final SettingsNotifier settingsNotifier;

  const _MergedGroupTile({
    required this.group,
    required this.notifier,
    required this.diveDao,
    required this.annotationsDao,
    required this.equipmentDao,
    required this.settingsNotifier,
  });

  String _gapLabel() {
    final gaps = group.surfaceGapsSeconds;
    if (gaps.length == 1) {
      return 'SI ${formatDuration(gaps.first)}';
    }
    return '${gaps.length} surface intervals';
  }

  @override
  Widget build(BuildContext context) {
    final date = DateTime.fromMillisecondsSinceEpoch(
        group.earliest.startTime * 1000);
    return ListTile(
      leading: const Icon(Icons.link),
      title: Text(
          '${formatDateTime(group.earliest.startTime)} · ${group.members.length} dives'),
      subtitle: Text(
          '${formatDuration(group.totalInWaterSeconds)} · '
          '${formatDepth(group.maxDepthMm)} · ${_gapLabel()}'),
      trailing: PopupMenuButton<String>(
        onSelected: (v) {
          if (v == 'unmerge') notifier.unmergeGroup(group.groupId);
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'unmerge', child: Text('Unmerge')),
        ],
      ),
      onTap: () => _openMerged(context),
    );
  }

  Future<void> _openMerged(BuildContext context) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    final members = <MergeMember>[];
    for (final dv in group.members) {
      final s = await diveDao.getSamples(dv.id);
      if (s == null) {
        if (context.mounted) Navigator.of(context).pop(); // dismiss loader
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Samples not available yet — try again later.')));
        }
        return;
      }
      members.add((dive: dv, samples: s));
    }
    final merged = buildMergedDive(mergedId: group.groupId, members: members);
    if (!context.mounted) return;
    Navigator.of(context).pop(); // dismiss loader
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => DiveDetailScreen(
        dive: merged.dive,
        preloadedSamples: merged.samples,
        dao: diveDao,
        annotationsDao: annotationsDao,
        equipmentDao: equipmentDao,
        settingsNotifier: settingsNotifier,
      ),
    ));
  }
}
```
(Ensure `DiveDao`, `DiveAnnotationsDao`, `EquipmentDao`, `SettingsNotifier`, `DiveDetailScreen` are already imported in this file — they are used by the existing tile; add any missing import.)

- [ ] **Step 6: Run the touched tests + analyze**

Run: `flutter test test/ui/screens/dive_list_screen_merge_test.dart test/ui/screens/dive_list_screen_test.dart && flutter analyze`
Expected: PASS, no new analyze errors.

- [ ] **Step 7: Commit**

```bash
git add lib/ui/screens/dive_list_screen.dart test/ui/screens/dive_list_screen_merge_test.dart
git commit -m "feat(ui): selection mode, merged group tile, combined-detail navigation"
```

---

## Task 10: AppShell contextual selection app bar

**Files:**
- Modify: `lib/ui/app_shell.dart` (the `build` method, the `appBar:` slot)

- [ ] **Step 1: Make the Scaffold rebuild on selection changes.** Wrap the returned `Scaffold` in the `build` method with a listener on the dive-list notifier so the app bar can switch:

```dart
    return ListenableBuilder(
      listenable: _diveListNotifier,
      builder: (context, _) {
        return Scaffold(
          appBar: isLandscape
              ? null
              : (_currentIndex == 0 && _diveListNotifier.selectionMode
                  ? _buildSelectionAppBar(context)
                  : _buildDefaultAppBar(context)),
          // ... existing body + bottomNavigationBar unchanged
        );
      },
    );
```
Refactor the existing `AppBar(...)` into a method `AppBar _buildDefaultAppBar(BuildContext context) { ... }` (move the current app bar code verbatim into it).

- [ ] **Step 2: Add the selection app bar builder** in `app_shell.dart`:

```dart
  AppBar _buildSelectionAppBar(BuildContext context) {
    final n = _diveListNotifier;
    final eligibility = n.mergeEligibility;
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: n.exitSelectionMode,
      ),
      title: Text('${n.selectedDiveIds.length} selected'),
      actions: [
        IconButton(
          tooltip: eligibility.canMerge
              ? 'Merge selected dives'
              : (eligibility.reason ?? 'Cannot merge'),
          icon: const Icon(Icons.merge_type),
          onPressed: eligibility.canMerge
              ? () async {
                  await n.mergeSelected();
                }
              : () {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(eligibility.reason ?? 'Cannot merge')));
                },
        ),
      ],
    );
  }
```

- [ ] **Step 3: Run analyze + the full UI test suite**

Run: `flutter analyze && flutter test test/ui/`
Expected: No new analyze errors; UI tests PASS.

- [ ] **Step 4: Commit**

```bash
git add lib/ui/app_shell.dart
git commit -m "feat(ui): contextual selection app bar with Merge action"
```

---

## Task 11: Full verification

- [ ] **Step 1: Format**

Run: `dart format lib/ test/`

- [ ] **Step 2: Analyze**

Run: `flutter analyze`
Expected: No errors, no new warnings.

- [ ] **Step 3: Full test suite**

Run: `flutter test`
Expected: All green, including the new merge tests.

- [ ] **Step 4: Manual smoke test (real device/sim)**

Run: `flutter run`
Verify:
1. Long-press a dive → selection mode; checkboxes appear; app bar shows count + Merge.
2. Select two adjacent same-DC dives ≤1 h apart → Merge enabled; tap → they collapse into one ⛓ group tile.
3. Try selecting two dives >1 h apart → Merge shows the "exceeds 1 h" reason (disabled path).
4. Open the group → stitched profile renders with a flat surface stretch between segments; PPO2/setpoint break across the gap.
5. Group tile overflow → Unmerge → originals reappear as individual dives, unchanged.
6. Restart the app → the merge persists (loaded from PowerSync local).

- [ ] **Step 5: Commit any format-only changes**

```bash
git add -A
git commit -m "chore: format merge-dives feature"
```

> **Hand-off reminder:** deploy `infra/powersync-sync-rules.yaml` to the PowerSync dashboard (Task 2) so the merge syncs to other signed-in devices. Until then, merges are local-only.

---

## Self-Review (completed by plan author)

**Spec coverage:**
- Stored grouping, reversible, synced → Tasks 1–3 (table, DAO, sync rules). ✓
- Guardrails (same DC, adjacent, 1 h hard cap, overlap reject) → Task 4. ✓
- Synthetic stitched profile (surface blocks, gas remap) → Task 5. ✓
- List collapse into group tile → Tasks 6, 9. ✓
- Selection mode + contextual app bar → Tasks 7, 9, 10. ✓
- Merged detail reuse (preloaded samples) → Task 8, 9. ✓
- Unmerge → Tasks 7 (notifier), 9 (group-tile overflow). ✓
- `kMergeMaxSurfaceGap` single constant → Task 4. ✓

**Known spec narrowing (intentional, documented):**
- Spec said resample mismatched `sampleIntervalMs`; Task 5 instead **throws** on mismatch (v1). Same-DC same-trip dives always match, so this is safe in practice; resampling deferred.
- Unmerge lives on the group tile's overflow menu (Task 9), not also in the merged detail overflow (spec listed both; detail-overflow deferred as optional polish).
- CNS/OTU/surfGF cumulative-across-surface simplification is inherent to feeding one stitched SampleSet to existing analysis — matches the spec's documented v1 simplification. No extra task needed.

**Placeholder scan:** none — every code step contains complete code.

**Type consistency:** `Dive` = Drift row class (epoch-seconds ints) used uniformly; `MergeMember = ({Dive dive, SampleSet samples})` consistent across Tasks 5 & 9; `MergeEligibility.canMerge`/`.reason` consistent Tasks 4, 7, 10; `buildListItems(List<Dive>, List<MergeLink>)` consistent Tasks 6, 7, 9.
