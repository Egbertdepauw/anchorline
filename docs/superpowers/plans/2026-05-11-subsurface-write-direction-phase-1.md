# Subsurface write-direction Phase 1 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Lift the safety hold on CCRLog → Subsurface git sync. Push new BLE-imported dives in full, push annotation edits onto existing Dive-NNN files via a constrained line-by-line merge, never modify Subsurface-side Divecomputer files, abort with a clear reason when the merge would touch foreign edits.

**Architecture:** The orchestrator's outer flow (clone → pull → snapshot → plan → write → commit → push) is unchanged. The whole change lives in `SyncPlanner.plan()` for the existing-dive branch (today: full overwrite; new: line-merge + diff-check + abort) plus a few supporting changes: mapper emits Information-tab annotation fields, `ExistingRemoteDive` carries the parsed Dive-NNN lines so the merge can run pure, `SubsurfaceSyncResult` surfaces a list of aborted dives, the Settings UI gains a Push button and an aborted-dives status block.

**Tech Stack:** Dart, Flutter, existing SsLine parsed-line model, existing `_mergeSiteLines` / `_mergeTopLevel` are the reference patterns for the new `_mergeDiveLines`.

**Reference spec:** `docs/superpowers/specs/2026-05-11-subsurface-write-direction-phase-1-design.md`

---

## File Structure

| File | Action | Responsibility |
|---|---|---|
| `lib/sync/subsurface_git/mapper.dart` | Modify | Extend `_buildDiveLines` to emit Information-tab annotation lines (visibility, wavesize, current, surge, chill, airtemp, watertemp, weightsystem). |
| `lib/sync/subsurface_git/sync_planner.dart` | Modify | Add `AbortedDive` + `AbortReason` types. Extend `ExistingRemoteDive` with `diveLines`. Add fields `abortedDives` to `SyncPlan` + `SyncPlanStats`. Write `_mergeDiveLines` helper. Rewrite existing-dive branch in `plan()` to use merge + diff-check + abort. Stop staging Divecomputer for existing dives. |
| `lib/sync/subsurface_git/remote_snapshot.dart` | Modify | Have `RemoteSnapshot.scan()` parse each existing Dive-NNN file and populate the new `ExistingRemoteDive.diveLines` field. |
| `lib/sync/subsurface_git/sync_orchestrator.dart` | Modify | Remove the safety throw + `ignore_for_file: dead_code`. Add `abortedDives` field to `SubsurfaceSyncResult`. Plumb the aborts from `SyncPlan` through. |
| `lib/ui/widgets/subsurface_sync_section.dart` | Modify | Add "Push to Subsurface" button. Render the post-sync status block with the aborted-dives list. |
| `test/fixtures/subsurface_incident_replica/` | Create | Synthetic fixture: an existing Divecomputer file in the bad-flavour format (sparse `dc_supplied_ppo2`, frequent rounded `po2`) and the matching Dive-NNN. The fixture mirrors the 2026-05-08 incident shape. |
| `test/sync/subsurface_git/sync_planner_test.dart` | Modify | Add merge tests (happy path, added owned line, foreign edit conflict, idempotent re-sync, Divecomputer-protected, incident replica). |
| `test/sync/subsurface_git/sync_orchestrator_test.dart` | Modify | Remove `skip:` clause on line 142 and any sibling skips. Add test that aborts surface in `SubsurfaceSyncResult.abortedDives`. |
| `test/ui/widgets/subsurface_sync_section_test.dart` | Modify | Add widget test for the Push button + aborts-displayed-after-sync. |

---

## Task 1: Mapper emits all Phase-1 owned annotation lines

The mapper currently emits `rating`, `tags`, `divesiteid`, `divemaster`, `buddy`, `suit`, `notes` and cylinder lines. The spec adds these owned keys: `visibility`, `wavesize`, `current`, `surge`, `chill`, `airtemp`, `watertemp`, `weightsystem` (repeating). Phase 1 needs the mapper to emit them so the merge has something to write.

**Files:**
- Modify: `lib/sync/subsurface_git/mapper.dart` — `_buildDiveLines()` (around line 201)
- Test: `test/sync/subsurface_git/mapper_test.dart`

- [ ] **Step 1: Write the failing tests** (append to mapper_test.dart)

```dart
test('mapDive emits Information-tab fields when annotation carries them', () {
  final mapper = CcrlogToSubsurfaceMapper();
  final ann = DiveAnnotation(
    diveId: 'd1',
    visibility: 5,
    wavesize: 3,
    current: 4,
    surge: 4,
    chill: 5,
    airTempC: 24.0,
    waterTempC: 22.5,
    createdAt: DateTime.utc(2026, 5, 1),
    updatedAt: DateTime.utc(2026, 5, 1),
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
  expect(text, contains('visibility 5'));
  expect(text, contains('wavesize 3'));
  expect(text, contains('current 4'));
  expect(text, contains('surge 4'));
  expect(text, contains('chill 5'));
  expect(text, contains('airtemp 24.0°C'));
  expect(text, contains('watertemp 22.5°C'));
});

test('mapDive emits one weightsystem line per Weight entry', () {
  final mapper = CcrlogToSubsurfaceMapper();
  final ann = DiveAnnotation(
    diveId: 'd1',
    weights: const [
      Weight(weightKg: 2.0, description: 'backplate'),
      Weight(weightKg: 1.5, description: 'belt'),
    ],
    createdAt: DateTime.utc(2026, 5, 1),
    updatedAt: DateTime.utc(2026, 5, 1),
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
  expect(text, contains('weightsystem weight=2.0kg description="backplate"'));
  expect(text, contains('weightsystem weight=1.5kg description="belt"'));
});
```

If `_testDive()` / `_testSamples()` helpers don't already exist in mapper_test.dart, copy them from the top of `sync_planner_test.dart` (search for `_diveIdA`, `_bundle`).

- [ ] **Step 2: Run tests to verify they fail**

```bash
flutter test test/sync/subsurface_git/mapper_test.dart -p vm
```
Expected: both new tests FAIL because the mapper doesn't emit those lines yet.

- [ ] **Step 3: Extend `_buildDiveLines()` to emit Information-tab fields**

In `lib/sync/subsurface_git/mapper.dart`, replace lines 219–234 (the `tags` / `divesiteid` / `divemaster` / `buddy` / `suit` / `notes` block) with:

```dart
    final tags = annotation?.tags ?? const [];
    if (tags.isNotEmpty) {
      lines.add(TagsLine(tags: List.of(tags)));
    }
    // Information-tab star ratings — Subsurface convention is 1..5.
    void emitStar(String key, int? value) {
      if (value != null && value > 0) {
        lines.add(ScalarLine(key: key, value: value.toString()));
      }
    }
    emitStar('visibility', annotation?.visibility);
    emitStar('wavesize', annotation?.wavesize);
    emitStar('current', annotation?.current);
    emitStar('surge', annotation?.surge);
    emitStar('chill', annotation?.chill);
    // Environment temperatures — Subsurface writes with °C suffix.
    void emitTemp(String key, double? celsius) {
      if (celsius == null) return;
      final formatted = celsius == celsius.roundToDouble()
          ? '${celsius.toStringAsFixed(1)}°C'
          : '${celsius.toStringAsFixed(1)}°C';
      lines.add(ScalarLine(key: key, value: formatted));
    }
    emitTemp('airtemp', annotation?.airTempC);
    emitTemp('watertemp', annotation?.waterTempC);
    if (siteId != null) {
      lines.add(ScalarLine(key: 'divesiteid', value: siteId));
    }
    lines.add(QuotedLine(key: 'divemaster', value: ''));
    final buddy = (annotation?.buddies ?? const <String>[]).join(', ');
    lines.add(QuotedLine(key: 'buddy', value: buddy));
    lines.add(QuotedLine(key: 'suit', value: annotation?.suit ?? ''));
    final notes = annotation?.notes;
    if (notes != null && notes.isNotEmpty) {
      lines.add(QuotedLine(key: 'notes', value: notes));
    }
    // Weights — one `weightsystem` line per entry.
    final weights = annotation?.weights ?? const <Weight>[];
    for (final w in weights) {
      final desc = w.description;
      lines.add(KeyvaluePairLine(
        key: 'weightsystem',
        fields: [
          MapEntry('weight', '${_formatDecimal(w.weightKg, 1)}kg'),
          MapEntry('description', '"$desc"'),
        ],
      ));
    }
```

If `Weight` isn't already imported, add to the imports at the top of `mapper.dart`:
```dart
import '../../data/models/annotation.dart' show Weight;
```

If `KeyvaluePairLine` isn't already imported from `format/subsurface_format.dart`, verify it is (search the file for `KeyvaluePairLine`); if absent, add to the `show` clause.

- [ ] **Step 4: Run tests to verify they pass**

```bash
flutter test test/sync/subsurface_git/mapper_test.dart -p vm
```
Expected: both new tests PASS. All previously-passing tests still PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/sync/subsurface_git/mapper.dart test/sync/subsurface_git/mapper_test.dart
git commit -m "feat(subsurface): mapper emits Information-tab annotation fields

Adds visibility/wavesize/current/surge/chill star ratings, airtemp/
watertemp environment values, and weightsystem lines (one per Weight
entry) to the CCRLog→Subsurface emission. These match the fields the
Information tab + Equipment tab now write into DiveAnnotation. Phase 1
write-direction merge needs them so existing-dive Dive-NNN files pick
up the user's CCRLog edits.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: New types — `AbortReason`, `AbortedDive`, plus `abortedDives` fields on `SyncPlan` + `SyncPlanStats`

Aborts are a first-class outcome of the plan (not exceptions). The orchestrator surfaces them on `SubsurfaceSyncResult`; the UI lists them as "Skipped". This task adds the data shape so later tasks have somewhere to populate.

**Files:**
- Modify: `lib/sync/subsurface_git/sync_planner.dart` (top of file, around line 100)
- Test: `test/sync/subsurface_git/sync_planner_test.dart`

- [ ] **Step 1: Write the failing test** (append to sync_planner_test.dart's `group('SyncPlanner.plan', ...)`)

```dart
test('SyncPlan exposes empty abortedDives by default', () {
  final planner = SyncPlanner();
  final plan = planner.plan(
    ccrlogDives: const [],
    existingDivesBySerialAndStart: const {},
    existingMaxDiveNumber: 0,
    existingTopLevel: const [],
    existingSites: const {},
  );
  expect(plan.abortedDives, isEmpty);
  expect(plan.stats.abortedDives, 0);
});
```

- [ ] **Step 2: Run test to verify it fails**

```bash
flutter test test/sync/subsurface_git/sync_planner_test.dart -p vm
```
Expected: FAIL — `abortedDives` getter not defined.

- [ ] **Step 3: Add the types and fields**

In `lib/sync/subsurface_git/sync_planner.dart`, immediately after the `SyncPlanStats` class (line 116 area), add:

```dart
/// Why a per-dive plan was aborted. Surfaced to the user in the UI's
/// "Skipped" status block; not an error condition.
enum AbortReason {
  /// CCRLog's planned write would change the Divecomputer file for a
  /// dive Subsurface already has. The Divecomputer file is sacred to
  /// the DC that recorded it — we never overwrite it in Phase 1.
  divecomputerProtected,

  /// The existing Dive-NNN file on disk has differences in lines
  /// CCRLog doesn't own (e.g. user-edited cylinder, a Subsurface-only
  /// scalar key we don't recognise, a manually-tuned duration). We
  /// decline to overwrite rather than risk losing the user's edits.
  foreignEditConflict,
}

/// One dive that the planner declined to write. Aborts are not
/// exceptions: sync still succeeds for the other dives in the same
/// run.
class AbortedDive {
  AbortedDive({
    required this.dive,
    required this.reason,
    required this.conflictingLines,
  });

  final Dive dive;
  final AbortReason reason;

  /// The line keys (e.g. `cylinder`, `duration`) that triggered a
  /// `foreignEditConflict`. Empty for other reasons. Surfaced to the
  /// user verbatim so they can find the offending field.
  final List<String> conflictingLines;
}
```

Then modify `SyncPlanStats` (around line 101):

```dart
class SyncPlanStats {
  SyncPlanStats({
    required this.newDives,
    required this.updatedDives,
    required this.skippedDives,
    required this.abortedDives,
  });

  final int newDives;
  final int updatedDives;
  final int skippedDives;

  /// Dives the planner declined to write because of a foreign edit on
  /// the Subsurface side. Surfaced to the user as "Skipped".
  final int abortedDives;
}
```

And `SyncPlan` (around line 118):

```dart
class SyncPlan {
  SyncPlan({
    required this.filesToWrite,
    required this.diveIdsPlanned,
    required this.stats,
    required this.abortedDives,
  });

  final Map<String, String> filesToWrite;
  final List<String> diveIdsPlanned;
  final SyncPlanStats stats;
  final List<AbortedDive> abortedDives;
}
```

Then update the existing `SyncPlanner.plan()` return at the bottom of the method (around line 281) to populate the new fields:

```dart
    return SyncPlan(
      filesToWrite: filesToWrite,
      diveIdsPlanned: diveIdsPlanned,
      stats: SyncPlanStats(
        newDives: newDives.length,
        updatedDives: updatedDives.length,
        skippedDives: skipped,
        abortedDives: 0,  // populated when Task 4 wires the merge branch
      ),
      abortedDives: const [],  // populated when Task 4 wires the merge branch
    );
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
flutter test test/sync/subsurface_git/sync_planner_test.dart -p vm
```
Expected: all tests PASS. Existing tests that constructed `SyncPlanStats` directly will fail to compile if any do — search the test file for `SyncPlanStats(` and add `abortedDives: 0,` to each constructor call (likely zero or one place).

- [ ] **Step 5: Commit**

```bash
git add lib/sync/subsurface_git/sync_planner.dart test/sync/subsurface_git/sync_planner_test.dart
git commit -m "feat(subsurface): SyncPlan tracks abortedDives as a first-class outcome

Adds AbortReason enum (divecomputerProtected, foreignEditConflict),
AbortedDive data class (dive + reason + conflictingLines), and
abortedDives fields on SyncPlanStats + SyncPlan. Currently always
empty; Task 4 populates them when the merge branch lands.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Carry parsed Dive-NNN lines on `ExistingRemoteDive`; populate from `RemoteSnapshot.scan()`

The merge needs the existing file's parsed lines. `ExistingRemoteDive` already represents a remote dive's metadata; we add `diveLines` to it. `RemoteSnapshot.scan()` reads each existing Dive-NNN at scan time and parses it.

**Files:**
- Modify: `lib/sync/subsurface_git/sync_planner.dart` — `ExistingRemoteDive` (line 75)
- Modify: `lib/sync/subsurface_git/remote_snapshot.dart` — the scan function
- Test: `test/sync/subsurface_git/remote_snapshot_test.dart`

- [ ] **Step 1: Write the failing test** (append to remote_snapshot_test.dart)

```dart
test('scan parses existing Dive-NNN files and attaches diveLines', () async {
  // Use the existing fixtures dir.
  final repoRoot = Directory('test/fixtures/subsurface');
  final snap = await RemoteSnapshot.scan(repoRoot: repoRoot);
  expect(snap.existingDivesBySerialAndStart, isNotEmpty);
  final any = snap.existingDivesBySerialAndStart.values.first;
  expect(any.diveLines, isNotEmpty,
      reason: 'scan should populate diveLines from the on-disk Dive-NNN');
  // A Dive-NNN always carries a `duration` scalar; verify it parsed.
  expect(
    any.diveLines.whereType<ScalarLine>().any((l) => l.key == 'duration'),
    isTrue,
  );
});
```

If the existing test file doesn't already import `ScalarLine` from `subsurface_format.dart`, add it.

- [ ] **Step 2: Run test to verify it fails**

```bash
flutter test test/sync/subsurface_git/remote_snapshot_test.dart -p vm
```
Expected: FAIL — `diveLines` not defined.

- [ ] **Step 3: Add `diveLines` to `ExistingRemoteDive` and populate it**

In `lib/sync/subsurface_git/sync_planner.dart`, modify the `ExistingRemoteDive` constructor + field list (around line 75):

```dart
class ExistingRemoteDive {
  ExistingRemoteDive({
    required this.folderSegments,
    required this.diveNumber,
    required this.serial,
    required this.startTime,
    required this.diveLines,
  });

  final List<String> folderSegments;
  final int diveNumber;
  final int? serial;
  final int? startTime;

  /// The parsed lines of `<folder>/Dive-NNN` at scan time. The merge in
  /// the planner uses these as the existing baseline to substitute
  /// CCRLog-owned lines into. Empty list is valid (a Dive-NNN with no
  /// content); null is not — populate via `RemoteSnapshot.scan()`.
  final List<SsLine> diveLines;
}
```

If `SsLine` isn't already imported in this file, add at the top:
```dart
import 'format/subsurface_format.dart' show SsLine;
```

Then in `lib/sync/subsurface_git/remote_snapshot.dart`, find the section where `ExistingRemoteDive(...)` is constructed (search for `ExistingRemoteDive(`). For each `Dive-NNN` file discovered, parse it and pass the lines:

```dart
// inside the existing loop where the function builds ExistingRemoteDive instances
final divText = diveFile.readAsStringSync();
final divLines = parseSubsurfaceFile(
  divText,
  kind: SubsurfaceFileKind.dive,
).lines;
existingDives[key] = ExistingRemoteDive(
  folderSegments: folderSegs,
  diveNumber: diveNumber,
  serial: serial,
  startTime: startTimeUtc,
  diveLines: divLines,
);
```

(Adjust to match the actual variable names in `remote_snapshot.dart`. The existing code already does similar work for `existingSites`; mirror that pattern.)

- [ ] **Step 4: Run test to verify it passes**

```bash
flutter test test/sync/subsurface_git/remote_snapshot_test.dart -p vm
flutter test test/sync/subsurface_git/sync_planner_test.dart -p vm
```
Expected: both PASS. `sync_planner_test.dart` may need `ExistingRemoteDive(...)` constructor calls to pass `diveLines: const []` — fix any compile errors that way.

- [ ] **Step 5: Commit**

```bash
git add lib/sync/subsurface_git/sync_planner.dart lib/sync/subsurface_git/remote_snapshot.dart test/sync/subsurface_git/sync_planner_test.dart test/sync/subsurface_git/remote_snapshot_test.dart
git commit -m "feat(subsurface): ExistingRemoteDive carries parsed Dive-NNN lines

RemoteSnapshot.scan() now reads each existing Dive-NNN file and parses
it into SsLine list, attached to ExistingRemoteDive.diveLines. The
upcoming merge in SyncPlanner needs these as the on-disk baseline to
substitute CCRLog-owned lines into.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: `_mergeDiveLines` helper — line-by-line owned substitution

Pure function. Takes the existing parsed Dive-NNN lines, the CCRLog-emitted lines for the same dive (built by mapper), and returns a merged line list plus the list of conflicting non-owned line keys. The list of owned line keys is a constant.

**Files:**
- Modify: `lib/sync/subsurface_git/sync_planner.dart` — add helper next to `_mergeSiteLines`
- Test: `test/sync/subsurface_git/sync_planner_test.dart`

- [ ] **Step 1: Write the failing tests** (append to the existing `group('SyncPlanner.plan', ...)`)

```dart
group('_mergeDiveLines (via plan() existing-dive branch)', () {
  test('happy path: only owned fields change, non-owned lines preserved',
      () {
    final existingText = '''duration 57:30 min
rating 3
divemaster ""
buddy "Alice"
suit ""
cylinder vol=3.0l workpressure=232.0bar description="3ℓ" o2=21%
''';
    final existing = parseSubsurfaceFile(
      existingText,
      kind: SubsurfaceFileKind.dive,
    ).lines;

    final planner = SyncPlanner();
    final bundle = _bundle(
      diveId: _diveIdA,
      annotation: _testAnnotation(rating: 5, notes: 'great viz'),
    );
    final plan = planner.plan(
      ccrlogDives: [bundle],
      existingDivesBySerialAndStart: {
        (serial: bundle.dive.dcSerial, startTime: bundle.dive.startTime):
            ExistingRemoteDive(
          folderSegments: ['2026', '04', '19-Sun-15=18=45'],
          diveNumber: 42,
          serial: bundle.dive.dcSerial,
          startTime: bundle.dive.startTime,
          diveLines: existing,
        ),
      },
      existingMaxDiveNumber: 42,
      existingTopLevel: const [],
      existingSites: const {},
    );

    // No Divecomputer file in the plan — Phase 1 never touches it for
    // existing dives.
    expect(
      plan.filesToWrite.keys
          .where((k) => k.endsWith('/Divecomputer'))
          .toList(),
      isEmpty,
    );
    // The Dive-NNN file IS in the plan.
    final divePath = '2026/04/19-Sun-15=18=45/Dive-42';
    expect(plan.filesToWrite.containsKey(divePath), isTrue);
    final out = plan.filesToWrite[divePath]!;
    // Owned lines changed:
    expect(out, contains('rating 5'));
    expect(out, contains('notes "great viz"'));
    // Non-owned line preserved verbatim:
    expect(out, contains(
        'cylinder vol=3.0l workpressure=232.0bar description="3ℓ" o2=21%'));
    expect(plan.stats.updatedDives, 1);
    expect(plan.abortedDives, isEmpty);
  });

  test('foreign edit on a non-owned line aborts that dive', () {
    // Subsurface side has a cylinder line that wouldn't match what
    // CCRLog would emit. Owned lines have no diff. Plan aborts.
    final existingText = '''duration 57:30 min
rating 3
divemaster ""
buddy ""
suit ""
cylinder vol=11.1l workpressure=232.0bar description="user-edited" o2=32%
''';
    final existing = parseSubsurfaceFile(
      existingText,
      kind: SubsurfaceFileKind.dive,
    ).lines;
    final planner = SyncPlanner();
    final bundle = _bundle(
      diveId: _diveIdA,
      annotation: _testAnnotation(rating: 3),  // matches existing
    );
    final plan = planner.plan(
      ccrlogDives: [bundle],
      existingDivesBySerialAndStart: {
        (serial: bundle.dive.dcSerial, startTime: bundle.dive.startTime):
            ExistingRemoteDive(
          folderSegments: ['2026', '04', '19-Sun-15=18=45'],
          diveNumber: 42,
          serial: bundle.dive.dcSerial,
          startTime: bundle.dive.startTime,
          diveLines: existing,
        ),
      },
      existingMaxDiveNumber: 42,
      existingTopLevel: const [],
      existingSites: const {},
    );
    // Nothing written for this dive:
    expect(
      plan.filesToWrite.keys
          .where((k) => k.contains('19-Sun-15=18=45'))
          .toList(),
      isEmpty,
    );
    // Abort surfaced:
    expect(plan.abortedDives, hasLength(1));
    expect(plan.abortedDives.first.reason,
        AbortReason.foreignEditConflict);
    expect(plan.abortedDives.first.conflictingLines, contains('cylinder'));
  });

  test('idempotent: re-plan on already-matching state writes nothing for '
      'existing dives', () {
    final bundle = _bundle(
      diveId: _diveIdA,
      annotation: _testAnnotation(rating: 3, notes: 'x'),
    );
    // Build "existing" by emitting the mapper's output for the same
    // bundle — that's what a freshly-synced state looks like.
    final mapper = CcrlogToSubsurfaceMapper();
    final mapped = mapper.mapDive(
      dive: bundle.dive,
      samples: bundle.samples,
      annotation: bundle.annotation,
      gasMixes: bundle.gasMixes,
      tanks: bundle.tanks,
      cylindersByMixIndex: bundle.cylindersByMixIndex,
      nextSubsurfaceDiveNumber: 42,
    );
    final planner = SyncPlanner();
    final plan = planner.plan(
      ccrlogDives: [bundle],
      existingDivesBySerialAndStart: {
        (serial: bundle.dive.dcSerial, startTime: bundle.dive.startTime):
            ExistingRemoteDive(
          folderSegments: ['2026', '04', '19-Sun-15=18=45'],
          diveNumber: 42,
          serial: bundle.dive.dcSerial,
          startTime: bundle.dive.startTime,
          diveLines: mapped.diveLines,
        ),
      },
      existingMaxDiveNumber: 42,
      existingTopLevel: const [],
      existingSites: const {},
    );
    expect(plan.filesToWrite, isEmpty);
    expect(plan.stats.skippedDives, 1);
    expect(plan.stats.updatedDives, 0);
    expect(plan.abortedDives, isEmpty);
  });
});
```

If `_testAnnotation()` helper doesn't exist, add to the test file's helpers:

```dart
DiveAnnotation _testAnnotation({int? rating, String? notes, ...}) =>
    DiveAnnotation(
      diveId: _diveIdA,
      rating: rating,
      notes: notes,
      createdAt: DateTime.utc(2026, 5, 1),
      updatedAt: DateTime.utc(2026, 5, 1),
    );
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
flutter test test/sync/subsurface_git/sync_planner_test.dart -p vm
```
Expected: all three new tests FAIL.

- [ ] **Step 3: Add `_mergeDiveLines` helper + constant**

In `lib/sync/subsurface_git/sync_planner.dart`, add near the top of the `SyncPlanner` class (after the constructor):

```dart
/// Dive-NNN line keys CCRLog owns. For existing dives the merge only
/// replaces lines matching these keys when CCRLog has a non-empty
/// value; every other key is left verbatim. Spec:
/// docs/superpowers/specs/2026-05-11-subsurface-write-direction-phase-1-design.md
static const _ownedDiveLineKeys = {
  'rating',
  'visibility',
  'wavesize',
  'current',
  'surge',
  'chill',
  'airtemp',
  'watertemp',
  'tags',
  'buddy',
  'suit',
  'notes',
  'divesiteid',
  'weightsystem',
  // divemaster is always emitted by the mapper as empty; treat as
  // owned so we don't trip a foreign-edit conflict on Subsurface's
  // identical empty line.
  'divemaster',
};
```

Then add the merge helper near `_mergeSiteLines` (around line 299):

```dart
/// Merge our CCRLog-emitted Dive-NNN lines into [existing], replacing
/// only lines whose key is in [_ownedDiveLineKeys]. Returns either a
/// merged line list (non-owned lines untouched) OR a non-empty
/// `conflictingKeys` list if any non-owned line would change.
({List<SsLine>? merged, List<String> conflictingKeys}) _mergeDiveLines({
  required List<SsLine> existing,
  required List<SsLine> ours,
}) {
  // Index our emission by key for O(1) lookup. `weightsystem` is the
  // only repeating owned key; bucket those so the merge can swap the
  // group atomically.
  final ourSingleByKey = <String, SsLine>{};
  final ourRepeatingByKey = <String, List<SsLine>>{};
  for (final line in ours) {
    final key = _lineKey(line);
    if (key == null) continue;
    if (key == 'weightsystem' || key == 'cylinder') {
      ourRepeatingByKey.putIfAbsent(key, () => []).add(line);
    } else {
      ourSingleByKey[key] = line;
    }
  }

  // 1) Compute conflicting non-owned lines: any existing line whose key
  // is NOT owned AND whose serialized form differs from what we'd emit
  // for the same key (when we'd emit it).
  final conflictingKeys = <String>{};
  for (final line in existing) {
    final key = _lineKey(line);
    if (key == null) continue;
    if (_ownedDiveLineKeys.contains(key)) continue;
    // Non-owned. Check whether we have anything to say about this key.
    if (ourSingleByKey.containsKey(key)) {
      // We don't actually emit non-owned single-keys, but defensive
      // catch-all: if we somehow did and it differs, flag.
      final ourLine = ourSingleByKey[key]!;
      if (_renderLine(line) != _renderLine(ourLine)) {
        conflictingKeys.add(key);
      }
    }
    // For non-owned repeating keys like `cylinder`, compare the WHOLE
    // group against our emitted group.
    if (ourRepeatingByKey.containsKey(key)) {
      final existingGroup =
          existing.where((l) => _lineKey(l) == key).map(_renderLine).toList();
      final ourGroup = ourRepeatingByKey[key]!.map(_renderLine).toList();
      if (!_listEquals(existingGroup, ourGroup)) {
        conflictingKeys.add(key);
      }
    }
  }
  if (conflictingKeys.isNotEmpty) {
    return (merged: null, conflictingKeys: conflictingKeys.toList()..sort());
  }

  // 2) Build merged output: walk existing lines, swap owned ones for
  // ours when present. Track which owned keys we've placed so we can
  // append the rest at the end.
  final placedOwnedKeys = <String>{};
  final merged = <SsLine>[];
  final placedRepeating = <String>{};
  for (final line in existing) {
    final key = _lineKey(line);
    if (key == null) {
      merged.add(line);
      continue;
    }
    if (!_ownedDiveLineKeys.contains(key)) {
      merged.add(line);
      continue;
    }
    if (ourRepeatingByKey.containsKey(key)) {
      if (!placedRepeating.contains(key)) {
        merged.addAll(ourRepeatingByKey[key]!);
        placedRepeating.add(key);
      }
      // Drop the existing line; its group is replaced by ours en bloc.
      placedOwnedKeys.add(key);
    } else if (ourSingleByKey.containsKey(key)) {
      merged.add(ourSingleByKey[key]!);
      placedOwnedKeys.add(key);
    } else {
      // CCRLog has nothing to say about this owned key. Leave the
      // existing line verbatim (e.g. Subsurface had `rating 3` and
      // CCRLog has no rating set).
      merged.add(line);
      placedOwnedKeys.add(key);
    }
  }
  // 3) Append owned lines we have but the existing file didn't.
  for (final entry in ourSingleByKey.entries) {
    if (!placedOwnedKeys.contains(entry.key)) merged.add(entry.value);
  }
  for (final entry in ourRepeatingByKey.entries) {
    if (entry.key == 'cylinder') continue;  // not owned
    if (!placedRepeating.contains(entry.key)) merged.addAll(entry.value);
  }
  return (merged: merged, conflictingKeys: const []);
}

/// Return the key for any [SsLine] that has one, else null. Used by
/// _mergeDiveLines to bucket lines.
String? _lineKey(SsLine line) {
  if (line is ScalarLine) return line.key;
  if (line is QuotedLine) return line.key;
  if (line is TagsLine) return 'tags';
  if (line is CylinderLine) return 'cylinder';
  if (line is KeyvaluePairLine) return line.key;
  if (line is RawLine) return null;
  return null;
}

/// Render a single line back to text so two lines can be byte-compared.
String _renderLine(SsLine line) =>
    serializeSubsurfaceFile(SubsurfaceFile(lines: [line])).trimRight();

bool _listEquals(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
```

(Inspect the actual SsLine subclasses in `format/subsurface_format.dart`; adjust the `_lineKey()` switch list to cover every concrete subclass that has a `key` property. If a class is missing, return null for safe fall-through.)

- [ ] **Step 4: Wire the merge into `plan()`** — replace the existing-dive branch

In `lib/sync/subsurface_git/sync_planner.dart`, find the loop that processes `ccrlogDives` (around line 183). Replace the body of `if (existing != null) { ... }` and the subsequent file emission with merge logic. Replace the block from line 191 through line 230 with:

```dart
      if (existing != null) {
        diveNumber = existing.diveNumber;
        folderSegments = existing.folderSegments;
        isUpdate = true;

        // Build CCRLog's emission to feed into the merge.
        final ours = _mapper.mapDive(
          dive: dive,
          samples: bundle.samples,
          annotation: bundle.annotation,
          gasMixes: bundle.gasMixes,
          tanks: bundle.tanks,
          cylindersByMixIndex: bundle.cylindersByMixIndex,
          nextSubsurfaceDiveNumber: diveNumber,
        );
        final mergeResult = _mergeDiveLines(
          existing: existing.diveLines,
          ours: ours.diveLines,
        );
        if (mergeResult.merged == null) {
          // Foreign edit on a non-owned line — abort this dive.
          abortedDives.add(AbortedDive(
            dive: dive,
            reason: AbortReason.foreignEditConflict,
            conflictingLines: mergeResult.conflictingKeys,
          ));
          continue;  // skip this dive entirely
        }
        // Idempotent check: if merged == existing, skip the write.
        final mergedText = serializeSubsurfaceFile(
          SubsurfaceFile(lines: mergeResult.merged!),
        );
        final existingText = serializeSubsurfaceFile(
          SubsurfaceFile(lines: existing.diveLines),
        );
        if (mergedText == existingText) {
          skipped += 1;
          // Site / 00-Subsurface side-effects below still need to run,
          // so don't `continue` — fall through.
        } else {
          final folderPath = folderSegments.join('/');
          filesToWrite['$folderPath/Dive-$diveNumber'] = mergedText;
          diveIdsPlanned.add(dive.id);
          updatedDives.add(dive);
        }
        // CRITICAL: never emit the Divecomputer file for an existing
        // dive. The DC's sample stream is sacred.
      } else {
        // New dive — preserve existing full-write behaviour (Dive-NNN
        // + Divecomputer).
        nextDiveNumber += 1;
        diveNumber = nextDiveNumber;
        folderSegments = _utcFolderSegments(dive.startTime);
        isUpdate = false;

        final mapped = _mapper.mapDive(
          dive: dive,
          samples: bundle.samples,
          annotation: bundle.annotation,
          gasMixes: bundle.gasMixes,
          tanks: bundle.tanks,
          cylindersByMixIndex: bundle.cylindersByMixIndex,
          nextSubsurfaceDiveNumber: diveNumber,
        );
        final folderPath = folderSegments.join('/');
        final diveText = serializeSubsurfaceFile(
          SubsurfaceFile(lines: mapped.diveLines),
        );
        final dcText = serializeSubsurfaceFile(
          SubsurfaceFile(lines: mapped.divecomputerLines),
        );
        filesToWrite['$folderPath/Dive-$diveNumber'] = diveText;
        filesToWrite['$folderPath/Divecomputer'] = dcText;
        diveIdsPlanned.add(dive.id);
        newDives.add(dive);
      }
```

Above the `for (final bundle ...)` loop, add the `abortedDives` accumulator:

```dart
    final abortedDives = <AbortedDive>[];
```

And update the final `return SyncPlan(...)` to plug it in:

```dart
    return SyncPlan(
      filesToWrite: filesToWrite,
      diveIdsPlanned: diveIdsPlanned,
      stats: SyncPlanStats(
        newDives: newDives.length,
        updatedDives: updatedDives.length,
        skippedDives: skipped,
        abortedDives: abortedDives.length,
      ),
      abortedDives: abortedDives,
    );
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
flutter test test/sync/subsurface_git/sync_planner_test.dart -p vm
```
Expected: all new tests PASS. The existing `existing dive (matching serial, startTime) reuses folder + NNN` test at line 59 may now fail because it asserts on full-file rewrite behaviour that no longer happens. Update that test's expectations to the new merge semantics (the dive's `Dive-NNN` may still be written if the merge produces different bytes; `Divecomputer` must NOT be in `filesToWrite`).

- [ ] **Step 6: Commit**

```bash
git add lib/sync/subsurface_git/sync_planner.dart test/sync/subsurface_git/sync_planner_test.dart
git commit -m "feat(subsurface): planner merges existing Dive-NNN, never touches Divecomputer

For existing dives, the planner now parses the on-disk Dive-NNN file,
substitutes CCRLog-owned lines (rating, conditions stars, temps, tags,
buddy, suit, notes, divesiteid, weightsystem, divemaster), and emits
the merged result. Lines we don't own (cylinder, duration, watersalinity,
anything new Subsurface adds) are preserved verbatim. If a non-owned
line would change at all, the planner aborts that dive's write and
surfaces it via SyncPlan.abortedDives.

The Divecomputer file is never staged for an existing dive — the DC's
sample stream is sacred. This closes the data-loss class of bug from
the 2026-05-08 incident.

New-dive write path is unchanged (full Dive-NNN + Divecomputer).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: Incident-replica fixture + regression test

Concrete reproduction of the 2026-05-08 failure mode: a Dive-NNN whose existing remote Divecomputer is sparse-`dc_supplied_ppo2` / frequent-`po2` flavour, and a CCRLog bundle that would generate richer output. We don't test the Divecomputer path (it's already protected) — we test that a manually-edited cylinder line on the Dive-NNN aborts cleanly.

**Files:**
- Create: `test/fixtures/subsurface_incident_replica/Dive-697` (Dive-NNN with non-default cylinder)
- Create: `test/fixtures/subsurface_incident_replica/Divecomputer` (any valid Divecomputer header)
- Test: `test/sync/subsurface_git/sync_planner_test.dart`

- [ ] **Step 1: Create the fixture files**

Write `test/fixtures/subsurface_incident_replica/Dive-697`:

```
duration 56:20 min
rating 2
tags "CCR", "X-CCR"
divesiteid 211b8868
divemaster ""
buddy "Alex Marlin"
suit ""
cylinder vol=3.0l workpressure=232.0bar description="user-manually-tuned" o2=18.0% he=23.0% use="diluent" depth=6.249m
```

Write `test/fixtures/subsurface_incident_replica/Divecomputer`:

```
model "Shearwater Petrel 3"
deviceid 18545bf0
diveid 4b4531e5
dctype CCR
numberofoxygensensors 3
maxdepth 13.3m
meandepth 9.648m
watertemp 7.0°C
surfacepressure 1.003bar
salinity 1000g/l
keyvalue "Logversion" "17(PNF)"
keyvalue "Serial" "b89641e4"
event 0:05 type=25 flags=6 name="gaschange" cylinder=5 o2=18.0% he=23.0%
  0:05 0.0m 12.0°C 182.987bar:0 167.956bar:1 sensor1=0.504bar sensor2=0.588bar sensor3=0.567bar dc_supplied_ppo2=0.55bar po2=0.7bar
  0:10 1.0m
  0:15 1.5m
  0:20 2.0m
```

- [ ] **Step 2: Write the failing test**

Append to `test/sync/subsurface_git/sync_planner_test.dart`:

```dart
test('incident replica: cylinder edit on Subsurface side aborts the dive', () {
  final divText = File('test/fixtures/subsurface_incident_replica/Dive-697')
      .readAsStringSync();
  final existingLines =
      parseSubsurfaceFile(divText, kind: SubsurfaceFileKind.dive).lines;
  final planner = SyncPlanner();
  // CCRLog has the same dive but with default-looking cylinders.
  final bundle = _bundle(diveId: _diveIdA);
  final plan = planner.plan(
    ccrlogDives: [bundle],
    existingDivesBySerialAndStart: {
      (serial: bundle.dive.dcSerial, startTime: bundle.dive.startTime):
          ExistingRemoteDive(
        folderSegments: ['2026', '02', '08-Sun-09=43=19'],
        diveNumber: 697,
        serial: bundle.dive.dcSerial,
        startTime: bundle.dive.startTime,
        diveLines: existingLines,
      ),
    },
    existingMaxDiveNumber: 697,
    existingTopLevel: const [],
    existingSites: const {},
  );

  // Nothing written for dive 697:
  expect(
    plan.filesToWrite.keys.where((k) => k.contains('Dive-697')).toList(),
    isEmpty,
  );
  expect(
    plan.filesToWrite.keys.where((k) => k.contains('Divecomputer')).toList(),
    isEmpty,
  );
  expect(plan.abortedDives, hasLength(1));
  expect(plan.abortedDives.first.dive.id, _diveIdA);
  expect(plan.abortedDives.first.reason,
      AbortReason.foreignEditConflict);
  expect(plan.abortedDives.first.conflictingLines, contains('cylinder'));
});
```

If `dart:io` `File` isn't imported in the test file, add `import 'dart:io';` at the top.

- [ ] **Step 3: Run the test to verify it passes**

```bash
flutter test test/sync/subsurface_git/sync_planner_test.dart -p vm
```
Expected: PASS. (If it FAILS, the merge logic in Task 4 has a hole — debug there, not here.)

- [ ] **Step 4: Commit**

```bash
git add test/fixtures/subsurface_incident_replica/ test/sync/subsurface_git/sync_planner_test.dart
git commit -m "test(subsurface): incident-replica fixture proves the merge aborts on foreign edits

A regression test that mirrors the shape of the 2026-05-08 data-loss
incident: a Subsurface-side Dive-NNN with a manually-edited cylinder
line, against a CCRLog bundle whose emission would otherwise have
overwritten it. The new merge aborts the dive instead, surfaces it on
SyncPlan.abortedDives with reason foreignEditConflict, and writes
nothing for that dive. If this test ever regresses, the data-loss bug
is back.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: Remove safety hold in orchestrator; propagate `abortedDives` onto `SubsurfaceSyncResult`

The throw goes away. The result type gains an aborts list. The orchestrator passes through from `SyncPlan`.

**Files:**
- Modify: `lib/sync/subsurface_git/sync_orchestrator.dart`

- [ ] **Step 1: Write the failing test**

Append to `test/sync/subsurface_git/sync_orchestrator_test.dart`:

```dart
test('syncNow surfaces abortedDives on the result', () async {
  // Reuse an existing test rig that sets up a local file:// remote +
  // a bundle. Add one dive to the remote with a foreign edit so the
  // planner aborts, then call syncNow and inspect result.abortedDives.
  // (Use the existing setup helper from this file; insert a fixture
  // dive on the remote BEFORE calling syncNow.)
  final result = await _runOrchestratorWithForeignEdit();
  expect(result.abortedDives, isNotEmpty);
  expect(
    result.abortedDives.first.reason,
    AbortReason.foreignEditConflict,
  );
});
```

(Adapt `_runOrchestratorWithForeignEdit()` to whatever setup helper exists in `sync_orchestrator_test.dart`. The exact wiring depends on the existing test fixtures; the key is to insert a foreign-edited Dive-NNN into the local file:// remote before invoking `syncNow()`.)

- [ ] **Step 2: Run the test to verify it fails**

```bash
flutter test test/sync/subsurface_git/sync_orchestrator_test.dart -p vm
```
Expected: FAIL — `SubsurfaceSyncResult.abortedDives` not defined, plus the safety throw still fires.

- [ ] **Step 3: Remove the safety hold and add `abortedDives` to the result**

In `lib/sync/subsurface_git/sync_orchestrator.dart`:

1. Remove the `// ignore_for_file: dead_code` pragma at line 6.
2. Remove the safety-hold comment block (lines 1–7).
3. Delete the `throw SubsurfaceSyncException(...)` block at lines 198–212 and the trailing "intentionally unreachable" comment at lines 214–219.
4. Modify `SubsurfaceSyncResult`:

```dart
class SubsurfaceSyncResult {
  SubsurfaceSyncResult({
    required this.divesPushed,
    required this.divesSkipped,
    required this.abortedDives,
    required this.commitSha,
    required this.completedAt,
  });

  final int divesPushed;
  final int divesSkipped;

  /// Dives the planner declined to push because of a foreign edit on
  /// the Subsurface side. Surface as "Skipped" in the UI; not errors.
  final List<AbortedDive> abortedDives;

  final String? commitSha;
  final DateTime completedAt;
}
```

5. In `_planAndPush()` (find the function that constructs `SubsurfaceSyncResult`), pass the plan's `abortedDives` through:

```dart
return SubsurfaceSyncResult(
  divesPushed: plan.stats.newDives + plan.stats.updatedDives,
  divesSkipped: plan.stats.skippedDives,
  abortedDives: plan.abortedDives,
  commitSha: commitSha,
  completedAt: DateTime.now(),
);
```

6. Add `AbortedDive` to the imports at the top of `sync_orchestrator.dart`:
```dart
import 'sync_planner.dart' show ..., AbortedDive;
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
flutter test test/sync/subsurface_git/sync_orchestrator_test.dart -p vm
```
Expected: PASS. Other orchestrator tests may now also pass that were `skip:`ed before — that's Task 7.

- [ ] **Step 5: Commit**

```bash
git add lib/sync/subsurface_git/sync_orchestrator.dart test/sync/subsurface_git/sync_orchestrator_test.dart
git commit -m "feat(subsurface): lift safety hold; surface abortedDives on SubsurfaceSyncResult

syncNow() no longer throws the 2026-05-08 safety exception. The
planner's abort path now propagates through the orchestrator so the
caller can render \"Skipped N dives (foreign edits)\" in the UI.

The data-loss class of failure is now blocked by the planner's merge
+ diff-check, not by an unconditional throw.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: Un-skip the orchestrator tests that the safety hold was blocking

The `skip:` clause at line 142 (and any sibling skips with the same message) gated tests that would have failed under the safety hold. With the hold lifted, they should pass against the new merge behaviour. Some may need their expectations updated for the new "merge, don't overwrite" semantics.

**Files:**
- Modify: `test/sync/subsurface_git/sync_orchestrator_test.dart`

- [ ] **Step 1: Find all safety-hold skips**

```bash
grep -n 'Safety hold' test/sync/subsurface_git/sync_orchestrator_test.dart
```

For each match, you'll see something like:
```dart
}, skip: 'Safety hold (2026-05-08): syncNow() throws unconditionally '
       'until the planner is rewritten to merge conservatively rather than '
       'overwrite Subsurface-side fields. Re-enable this group when the '
       'safety throw in sync_orchestrator.dart is removed.');
```

- [ ] **Step 2: Remove each `skip:` clause**

Delete the `skip: '...'` argument (and trailing comma) from each `test(...)` or `group(...)` call you found.

- [ ] **Step 3: Run the tests**

```bash
flutter test test/sync/subsurface_git/sync_orchestrator_test.dart -p vm
```
Expected: most or all PASS. Any test that now FAILS likely asserted on the OLD overwrite behaviour for existing dives (e.g. "Dive-N appears in the push commit"). Update those assertions to match Phase 1 semantics: for existing dives the commit should contain ONLY the merged Dive-NNN (no Divecomputer) and only when the merge changed bytes.

- [ ] **Step 4: Commit**

```bash
git add test/sync/subsurface_git/sync_orchestrator_test.dart
git commit -m "test(subsurface): un-skip orchestrator tests gated by the 2026-05-08 safety hold

Removes the skip: clauses now that syncNow() no longer throws. Any
asserts that depended on the old full-overwrite behaviour are updated
to expect the Phase 1 merge semantics (Dive-NNN written only when
the merge changes bytes; Divecomputer never written for existing
dives).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 8: Settings UX — "Push to Subsurface" button + aborted-dives status block

The user kicks off a sync from Settings and sees a post-sync card.

**Files:**
- Modify: `lib/ui/widgets/subsurface_sync_section.dart`
- Test: `test/ui/widgets/subsurface_sync_section_test.dart`

- [ ] **Step 1: Write the failing widget test**

Append to `subsurface_sync_section_test.dart`:

```dart
testWidgets('Push button calls orchestrator.syncNow and shows aborts', (tester) async {
  final fakeOrchestrator = _FakeOrchestrator(
    result: SubsurfaceSyncResult(
      divesPushed: 3,
      divesSkipped: 0,
      abortedDives: [
        AbortedDive(
          dive: _testDive(id: 'd1', dcDiveNumber: 705),
          reason: AbortReason.foreignEditConflict,
          conflictingLines: ['cylinder'],
        ),
      ],
      commitSha: 'abc1234',
      completedAt: DateTime.utc(2026, 5, 11, 14, 30),
    ),
  );
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SubsurfaceSyncSection(
        orchestrator: fakeOrchestrator,
        credentials: _fakeCredentials(),
        bootstrapImporter: null,
      ),
    ),
  ));
  await tester.tap(find.text('Push to Subsurface'));
  await tester.pumpAndSettle();
  expect(fakeOrchestrator.syncCalls, 1);
  expect(find.text('Pushed 3 dives'), findsOneWidget);
  expect(find.text('Skipped 1 dive'), findsOneWidget);
  expect(find.textContaining('#705'), findsOneWidget);
  expect(find.textContaining('cylinder'), findsOneWidget);
});
```

(Adapt `_FakeOrchestrator`, `_testDive`, `_fakeCredentials` to whatever fakes the existing test file uses. If none exist, add minimal stubs at the bottom of the test file.)

- [ ] **Step 2: Run the test to verify it fails**

```bash
flutter test test/ui/widgets/subsurface_sync_section_test.dart -p vm
```
Expected: FAIL — no "Push to Subsurface" button.

- [ ] **Step 3: Add the Push button + status block**

In `lib/ui/widgets/subsurface_sync_section.dart`, add a "Push" button inside the existing card (below the bootstrap-import controls). Hook it to `widget.orchestrator?.syncNow()` and store the result in state. Render the result below:

```dart
// In the State class, add:
SubsurfaceSyncResult? _lastSyncResult;
String? _syncError;
bool _syncing = false;

Future<void> _onPushPressed() async {
  if (widget.orchestrator == null || _syncing) return;
  setState(() {
    _syncing = true;
    _syncError = null;
  });
  try {
    final result = await widget.orchestrator!.syncNow();
    if (!mounted) return;
    setState(() => _lastSyncResult = result);
  } on SubsurfaceSyncException catch (e) {
    if (!mounted) return;
    setState(() => _syncError = e.message);
  } finally {
    if (mounted) setState(() => _syncing = false);
  }
}

Widget _buildSyncStatusBlock(SubsurfaceSyncResult r) {
  return Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Pushed ${r.divesPushed} dives',
            style: const TextStyle(fontWeight: FontWeight.w600)),
        if (r.abortedDives.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text('Skipped ${r.abortedDives.length} '
              '${r.abortedDives.length == 1 ? 'dive' : 'dives'}',
              style: const TextStyle(color: Color(0xFFE65100))),
          for (final ab in r.abortedDives)
            Padding(
              padding: const EdgeInsets.only(left: 12, top: 2),
              child: Text(
                '• #${ab.dive.dcDiveNumber} — ${_reasonText(ab)}',
                style: const TextStyle(fontSize: 12, color: Color(0xFFB0BEC5)),
              ),
            ),
        ],
      ],
    ),
  );
}

String _reasonText(AbortedDive ab) {
  switch (ab.reason) {
    case AbortReason.foreignEditConflict:
      return 'edits in Subsurface (${ab.conflictingLines.join(', ')})';
    case AbortReason.divecomputerProtected:
      return 'Divecomputer recording protected';
  }
}
```

And add the button + status to the existing `build()` method, near the bootstrap-import button:

```dart
ElevatedButton.icon(
  onPressed: widget.orchestrator == null ? null : _onPushPressed,
  icon: _syncing
      ? const SizedBox(
          width: 16, height: 16,
          child: CircularProgressIndicator(strokeWidth: 2))
      : const Icon(Icons.cloud_upload_outlined),
  label: const Text('Push to Subsurface'),
),
if (_lastSyncResult != null) _buildSyncStatusBlock(_lastSyncResult!),
if (_syncError != null)
  Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Text('Sync failed: $_syncError',
        style: const TextStyle(color: Color(0xFFE53935))),
  ),
```

Import the types at the top:
```dart
import '../../sync/subsurface_git/sync_orchestrator.dart';
import '../../sync/subsurface_git/sync_planner.dart' show AbortedDive, AbortReason;
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
flutter test test/ui/widgets/subsurface_sync_section_test.dart -p vm
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/widgets/subsurface_sync_section.dart test/ui/widgets/subsurface_sync_section_test.dart
git commit -m "feat(ui): Push to Subsurface button + aborted-dives status

Settings → Subsurface sync card now has a 'Push to Subsurface' button
that triggers the orchestrator's syncNow(). After the sync the card
shows pushed/skipped counts and lists every aborted dive with its
reason (e.g. '#705 — edits in Subsurface (cylinder)').

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 9: Full-suite verification + manual smoke + push

- [ ] **Step 1: Full analyze + test sweep**

```bash
flutter analyze
flutter test test/ -p vm
```
Expected: 0 issues, all tests pass.

- [ ] **Step 2: Manual smoke against a throwaway clone (NOT the live ss_git)**

```bash
# Copy the user's repo to a throwaway path so we can't damage the real one.
cp -R /Users/egbert/Dev/CCRLog/ss_git /tmp/ss_git_smoke_$(date +%s)
```

In the app on macOS:
1. Reset Everything (Settings → Reset everything).
2. Sign in.
3. Bootstrap-import from the throwaway clone (override the clone path if the app supports it; otherwise temporarily edit `AppShell._initSubsurfaceSync` to point at the throwaway). Skip this step if no override is exposed and rely on the unit-test coverage instead.
4. Edit an annotation on one dive (rating, notes).
5. Hit "Push to Subsurface".
6. Verify: status card shows "Pushed 1 dive" and zero aborts.
7. Inspect the throwaway clone's git log + diff: the only changed file should be the one Dive-NNN; the change should be on the annotation lines you edited.

Document what you saw in the commit message of Step 4.

- [ ] **Step 3: Push the whole chain**

```bash
git push origin main
```

- [ ] **Step 4: Update memory**

Edit `/Users/egbert/.claude/projects/-Users-egbert-Dev-CCRLog-ccrlogger/memory/project_next_session_priority.md` — replace the body with a note that the write-direction Phase 1 is shipped, link the spec + plan paths, and list the Phase 2 / 3 / 4 deferred items so the next session has clean breadcrumbs.

- [ ] **Step 5: Final commit (memory update is private, not committed)**

No code commit here — the memory file lives outside the repo.

---

## Self-Review

**Spec coverage:**
- Goal 1 (push new dives) → preserved by Task 4's `else` branch (new dives).
- Goal 2 (push annotation edits) → Tasks 1–4.
- Goal 3 (never modify Divecomputer for existing) → Task 4's existing-dive branch never adds Divecomputer to `filesToWrite`; Task 5's regression test verifies.
- Goal 4 (surface conflicts) → Tasks 2 (types) + 4 (planner populates) + 6 (orchestrator propagates) + 8 (UI renders).
- Tests 1–8 from spec → Task 4 covers Tests 2/3/4/5/7; Task 5 covers Test 1; Task 6/7 cover Test 8; "Divecomputer-protected" (Test 6) is implicit in Task 4's merge tests and verified explicitly in Task 5.

**Placeholder scan:** no "TODO/TBD"; all code blocks present.

**Type consistency:** `AbortedDive` / `AbortReason` defined in Task 2, referenced in Tasks 4/6/8 with the same field names. `_mergeDiveLines` signature matches between definition (Task 4) and call sites (Task 4 same task). `_ownedDiveLineKeys` constant defined once.

**Ambiguity check:** "non-empty value" for owned-line replacement is clearly resolved in Task 4's `_mergeDiveLines` — emission decisions are made by the existing mapper, which already only emits owned lines when CCRLog has them. The merge just uses what the mapper produces.
