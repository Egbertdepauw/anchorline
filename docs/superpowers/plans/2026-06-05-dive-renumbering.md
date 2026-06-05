# Dive Renumbering Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user assign persistent, synced dive numbers — renumber all/selected dives from a start number (date order) and reset to the automatic sequence — via the existing dive-merge selection UX.

**Architecture:** A nullable synced `user_dive_number` on `dive_annotations` (Supabase + PowerSync schema + Drift). The displayed number becomes `userDiveNumber ?? auto-date-sequence`. A pure `computeRenumber` assigns numbers by date; `DiveListNotifier` gains `selectAll`/`renumberSelected`/`resetNumberingSelected`; a renumber dialog + two actions sit in the selection-mode app bar next to Merge.

**Tech Stack:** Flutter/Dart, Drift (+ codegen), PowerSync, Supabase SQL, `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-06-05-dive-renumbering-design.md`

## Branch & conventions
- Branch off the **stats** branch (it carries Drift schema v19): `git switch feat/statistics-tab && git switch -c feat/dive-renumbering`. Merge order is #60 → #61 → this.
- `git add` only the files each task lists — NEVER `git add -A`/`.`/`-a`.
- Do NOT run `dart format`. Generous Bash timeout (~600000 ms) for flutter/build_runner.
- Commit trailer: `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.

## File structure
**Create:** `supabase/migrations/0015_dive_user_number.sql`; `lib/ui/notifiers/dive_renumber.dart` (pure `computeRenumber`); `lib/ui/widgets/renumber_dialog.dart`; tests for `computeRenumber` + the notifier.
**Modify:** `lib/sync/cloud/powersync_schema.dart`; `lib/data/db/tables.dart`; `lib/data/db/database.dart` (+ regenerated `database.g.dart`); `test/data/db/migration_test.dart`; `lib/data/models/annotation.dart`; `lib/data/db/dive_annotations_dao.dart`; `lib/ui/notifiers/dive_list_notifier.dart`; `lib/ui/app_shell.dart`.

---

## Task 1: Add the synced `user_dive_number` column (all schema layers)

**Files:** Create `supabase/migrations/0015_dive_user_number.sql`; modify `lib/sync/cloud/powersync_schema.dart`, `lib/data/db/tables.dart`, `lib/data/db/database.dart` (+ codegen), `test/data/db/migration_test.dart`.

- [ ] **Step 1: Supabase migration** — create `supabase/migrations/0015_dive_user_number.sql`:

```sql
ALTER TABLE dive_annotations
ADD COLUMN IF NOT EXISTS user_dive_number INTEGER;
COMMENT ON COLUMN dive_annotations.user_dive_number IS
  'User-assigned dive number (renumbering). NULL = use the app''s automatic '
  'date-order sequence.';
```

(This file must be **deployed** to the live Postgres by the maintainer before cross-device sync works — local/single-device works without it.)

- [ ] **Step 2: PowerSync client schema** — in `lib/sync/cloud/powersync_schema.dart`, in the `Table('dive_annotations', [...])` column list, add after `Column.text('display_deco_algorithm'),`:

```dart
    Column.integer('user_dive_number'),
```

- [ ] **Step 3: Drift column** — in `lib/data/db/tables.dart`, in `class DiveAnnotations`, add after the `displayDecoAlgorithm` getter:

```dart
  /// User-assigned dive number (renumbering). NULL = automatic date sequence.
  IntColumn get userDiveNumber => integer().nullable()();
```

- [ ] **Step 4: Drift schema bump + migration** — in `lib/data/db/database.dart`, change `int get schemaVersion => 19;` to `=> 20;`, and add at the END of the `onUpgrade` chain (after the `if (from < 19)` block):

```dart
      if (from < 20) {
        await m.addColumn(diveAnnotations, diveAnnotations.userDiveNumber);
      }
```

- [ ] **Step 5: Codegen**

Run: `dart run build_runner build --delete-conflicting-outputs`
Expected: success; `database.g.dart` regenerates with `userDiveNumber` on the annotations row/companion. Then `git status --short` should show only `database.dart`, `database.g.dart`, `tables.dart` changed (report if other `.g.dart` changed).

- [ ] **Step 6: Update migration tests** — in `test/data/db/migration_test.dart`:
  1. Replace EVERY `expect(db.schemaVersion, 19);` with `expect(db.schemaVersion, 20);`.
  2. Add a `v19 → v20` test. **Read the existing `'v11 → v12 ... adds ... columns to dive_annotations'` test in this file and mirror its setup** (it seeds `dive_annotations` and applies an addColumn migration). The new test:

```dart
  test('v19 → v20 adds user_dive_number to dive_annotations', () async {
    final raw = sqlite3.openInMemory();
    addTearDown(raw.close);
    _seedV1SyncTables(raw, withOwnerId: true); // creates dive_annotations
    raw.execute('PRAGMA user_version = 19;');

    final db = AppDatabase(NativeDatabase.opened(raw));
    addTearDown(db.close);
    await db.customSelect('SELECT 1').get();
    expect(db.schemaVersion, 20);

    final now = DateTime.now().millisecondsSinceEpoch;
    await db.customStatement(
      'INSERT INTO dive_annotations (dive_id, user_dive_number, created_at, updated_at) '
      'VALUES (?, ?, ?, ?)',
      ['dive_a', 482, now, now],
    );
    final rows = await db
        .customSelect('SELECT user_dive_number FROM dive_annotations')
        .get();
    expect(rows.single.data['user_dive_number'], 482);
  });
```
  Note: opening at `user_version = 19` runs only the `if (from < 20)` block (addColumn), so the v1-seeded `dive_annotations` shape is sufficient — the minimal INSERT above uses only columns present in that seed plus the new one. If anything trips, compare with the v11→v12 test (it also ALTERs `dive_annotations`).

- [ ] **Step 7: Verify**

Run: `flutter test test/data/db/migration_test.dart` → PASS.
Run: `flutter analyze` → clean.
Run: `flutter test` → all green (0 failures).

- [ ] **Step 8: Commit (include spec + plan)**

```bash
git add supabase/migrations/0015_dive_user_number.sql lib/sync/cloud/powersync_schema.dart \
        lib/data/db/tables.dart lib/data/db/database.dart lib/data/db/database.g.dart \
        test/data/db/migration_test.dart \
        docs/superpowers/specs/2026-06-05-dive-renumbering-design.md \
        docs/superpowers/plans/2026-06-05-dive-renumbering.md
git commit -m "feat(renumber): add synced user_dive_number column (schema v20)" \
           -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Model + DAO

**Files:** Modify `lib/data/models/annotation.dart`, `lib/data/db/dive_annotations_dao.dart`.

- [ ] **Step 1: Model field** — in `lib/data/models/annotation.dart`:
  - Add the field near `displayDecoAlgorithm`: `final int? userDiveNumber;`
  - Add to the constructor param list (near `this.displayDecoAlgorithm,`): `this.userDiveNumber,`
  - Add to `copyWith`'s params (near the `displayDecoAlgorithm` param): `Value<int?>? userDiveNumber,`
  - Add to `copyWith`'s body (near the `displayDecoAlgorithm:` line):
    `userDiveNumber: userDiveNumber == null ? this.userDiveNumber : userDiveNumber.value,`

- [ ] **Step 2: DAO read + upsert threading** — in `lib/data/db/dive_annotations_dao.dart`:
  - In `_rowToModel`, add near `displayDecoAlgorithm:`: `userDiveNumber: row['user_dive_number'] as int?,`
  - In `upsert`'s INSERT: add `user_dive_number` to the column list (after `display_deco_algorithm,`), add one `?` to the VALUES list, and add `a.userDiveNumber` to the args array in the matching position.
  - In `upsert`'s UPDATE: add `'user_dive_number = ?, '` (after the `display_deco_algorithm = ?,` line) and `a.userDiveNumber` to the args array in the matching position.
  (Match the existing column→arg ordering exactly; the args arrays are positional.)

- [ ] **Step 3: Batch setter** — add this method to `DiveAnnotationsDao` (it uses the same `_db`/`_session`/`SyncStatus` already imported):

```dart
  /// Bulk-set `user_dive_number` for many dives in one transaction (renumber).
  /// A null value clears the custom number. Creates a minimal annotation row
  /// for dives that don't have one yet. Stamps owner/updated/version/sync like
  /// the single upsert.
  Future<void> setUserDiveNumbers(Map<String, int?> byDiveId) async {
    if (byDiveId.isEmpty) return;
    final ownerId = _session.currentSession?.user.id;
    final now = DateTime.now().millisecondsSinceEpoch;
    final ids = byDiveId.keys.toList();
    final placeholders = List.filled(ids.length, '?').join(',');
    await _db.writeTransaction((tx) async {
      final existing = await tx.getAll(
        'SELECT dive_id, version FROM dive_annotations '
        'WHERE dive_id IN ($placeholders)',
        ids,
      );
      final versions = <String, int>{
        for (final r in existing)
          r['dive_id'] as String: (r['version'] as int? ?? 0),
      };
      for (final entry in byDiveId.entries) {
        final diveId = entry.key;
        final number = entry.value;
        if (versions.containsKey(diveId)) {
          await tx.execute(
            'UPDATE dive_annotations SET user_dive_number = ?, '
            'updated_at = ?, version = ?, sync_status = ? WHERE dive_id = ?',
            [number, now, versions[diveId]! + 1, SyncStatus.pending.index, diveId],
          );
        } else {
          await tx.execute(
            'INSERT INTO dive_annotations '
            '(id, owner_id, dive_id, user_dive_number, '
            'created_at, updated_at, version, sync_status) '
            'VALUES (?, ?, ?, ?, ?, ?, 1, ?)',
            [diveId, ownerId, diveId, number, now, now, SyncStatus.pending.index],
          );
        }
      }
    });
  }
```

- [ ] **Step 4: Test (conditional)** — check `test/data/db/` for an existing PowerSync-backed DAO test (e.g. how `dive_merge_dao_test.dart` or `dive_bailout_carry_dao_test.dart` construct a `PowerSyncDatabase` for tests). If such a harness exists, add `test/data/db/dive_annotations_user_number_test.dart` mirroring it: call `setUserDiveNumbers({'a': 482, 'b': 483})`, then `getAnnotationsForDives(['a','b'])` and assert `userDiveNumber` round-trips; call `setUserDiveNumbers({'a': null})` and assert it clears. If there is **no** PowerSync DAO test harness in the repo, skip this test (note it in your report) — `computeRenumber` (Task 3) carries the logic coverage and the DAO is manually verified.

- [ ] **Step 5: Verify + commit**

Run: `flutter analyze lib/data/models/annotation.dart lib/data/db/dive_annotations_dao.dart` → clean. If you added a test, run it → PASS. Run `flutter test` → green.

```bash
git add lib/data/models/annotation.dart lib/data/db/dive_annotations_dao.dart
# include the test file too if you created one
git commit -m "feat(renumber): userDiveNumber on annotation model + DAO batch setter" \
           -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Pure renumber computation

**Files:** Create `lib/ui/notifiers/dive_renumber.dart`, `test/ui/notifiers/dive_renumber_test.dart`.

- [ ] **Step 1: Write the failing test** — create `test/ui/notifiers/dive_renumber_test.dart`:

```dart
import 'package:ccrlogger/ui/notifiers/dive_renumber.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('assigns start..start+n-1 in date order (oldest = start)', () {
    final targets = [
      (diveId: 'newest', startTime: 300),
      (diveId: 'oldest', startTime: 100),
      (diveId: 'mid', startTime: 200),
    ];
    final r = computeRenumber(targets, 482);
    expect(r['oldest'], 482);
    expect(r['mid'], 483);
    expect(r['newest'], 484);
  });

  test('single target gets the start number', () {
    expect(computeRenumber([(diveId: 'a', startTime: 5)], 1), {'a': 1});
  });

  test('empty targets → empty map', () {
    expect(computeRenumber(const [], 1), isEmpty);
  });
}
```

- [ ] **Step 2: Run → fail**

Run: `flutter test test/ui/notifiers/dive_renumber_test.dart`
Expected: FAIL — `dive_renumber.dart` not found.

- [ ] **Step 3: Implement** — create `lib/ui/notifiers/dive_renumber.dart` (no Flutter imports):

```dart
/// Pure renumber computation: assign sequential dive numbers to [targets] in
/// chronological order, oldest = [start]. Returns diveId → number.
Map<String, int> computeRenumber(
    List<({String diveId, int startTime})> targets, int start) {
  final sorted = [...targets]..sort((a, b) => a.startTime.compareTo(b.startTime));
  final out = <String, int>{};
  for (var i = 0; i < sorted.length; i++) {
    out[sorted[i].diveId] = start + i;
  }
  return out;
}
```

- [ ] **Step 4: Run → pass**

Run: `flutter test test/ui/notifiers/dive_renumber_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/ui/notifiers/dive_renumber.dart test/ui/notifiers/dive_renumber_test.dart
git commit -m "feat(renumber): pure computeRenumber helper" \
           -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Notifier — display override + selection actions

**Files:** Modify `lib/ui/notifiers/dive_list_notifier.dart`. Test: extend/create `test/ui/notifiers/dive_list_notifier_test.dart` if a harness exists (else verify via analyze + the screen).

- [ ] **Step 1: Display override** — in `lib/ui/notifiers/dive_list_notifier.dart`, change `sequenceByDiveId` so a custom number wins over the auto value:

```dart
  Map<String, int> get sequenceByDiveId {
    final n = _dives.length;
    return {
      for (var i = 0; i < n; i++)
        _dives[i].id:
            _annotationsByDiveId[_dives[i].id]?.userDiveNumber ?? (n - i),
    };
  }
```

- [ ] **Step 2: Selection actions** — add to `DiveListNotifier` (imports: `import 'dive_renumber.dart';` and `import '../models/dive_list_item.dart';` if `listItems`/representative ids aren't already in scope — check; the notifier already exposes `listItems`):

```dart
  /// Representative dive id for a list item (a merged group → its earliest
  /// member, which carries the group's annotation/number).
  String _representativeId(DiveListItem item) => switch (item) {
        SingleDive(:final dive) => dive.id,
        MergedGroupItem(:final group) => group.earliest.id,
      };

  /// Select every visible list item (merged groups via their representative id).
  void selectAll() {
    _selectionMode = true;
    _selectedDiveIds
      ..clear()
      ..addAll(listItems.map(_representativeId));
    notifyListeners();
  }

  /// Renumber the current selection from [start] in date order, persisting
  /// `user_dive_number`. No-op when nothing is selected.
  Future<void> renumberSelected(int start) async {
    if (_selectedDiveIds.isEmpty) return;
    final byId = {for (final d in _dives) d.id: d};
    final targets = _selectedDiveIds
        .where(byId.containsKey)
        .map((id) => (diveId: id, startTime: byId[id]!.startTime))
        .toList();
    await _annotationsDao.setUserDiveNumbers(computeRenumber(targets, start));
    exitSelectionMode();
    await loadDives();
  }

  /// Clear custom numbers for the current selection (back to auto sequence).
  Future<void> resetNumberingSelected() async {
    if (_selectedDiveIds.isEmpty) return;
    await _annotationsDao
        .setUserDiveNumbers({for (final id in _selectedDiveIds) id: null});
    exitSelectionMode();
    await loadDives();
  }
```

(If `listItems` returns the *filtered* list vs all dives, that's fine — Select all selects the currently-visible items, matching the spec. Confirm `listItems` is a getter on the notifier; the exploration found `List<DiveListItem> get listItems => buildListItems(_dives, _links);`.)

- [ ] **Step 3: Test the override (if feasible)** — if the notifier can be constructed with fakes in a test (check for an existing `dive_list_notifier_test.dart` or fakeable DAOs), add a test that with a seeded dive + an annotation carrying `userDiveNumber: 900`, `sequenceByDiveId[diveId] == 900`, and without it falls back to the auto value. If the notifier isn't unit-testable without heavy PowerSync setup, skip and note it — `computeRenumber` covers the assignment logic; the override is a one-line `??`.

- [ ] **Step 4: Verify + commit**

Run: `flutter analyze lib/ui/notifiers/dive_list_notifier.dart` → clean. `flutter test` → green.

```bash
git add lib/ui/notifiers/dive_list_notifier.dart
# + the test if created
git commit -m "feat(renumber): sequence override + selectAll/renumber/reset on notifier" \
           -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: UI — renumber dialog + selection-bar actions

**Files:** Create `lib/ui/widgets/renumber_dialog.dart`; modify `lib/ui/app_shell.dart`.

- [ ] **Step 1: Renumber dialog** — create `lib/ui/widgets/renumber_dialog.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Result of the renumber dialog.
sealed class RenumberResult {}
class RenumberApply extends RenumberResult {
  final int start;
  RenumberApply(this.start);
}
class RenumberReset extends RenumberResult {}

/// Dialog to renumber [count] dives. Returns a [RenumberApply] (with the start
/// number), a [RenumberReset], or null if cancelled.
Future<RenumberResult?> showRenumberDialog(
    BuildContext context, int count) {
  return showDialog<RenumberResult>(
    context: context,
    builder: (ctx) => _RenumberDialog(count: count),
  );
}

class _RenumberDialog extends StatefulWidget {
  final int count;
  const _RenumberDialog({required this.count});
  @override
  State<_RenumberDialog> createState() => _RenumberDialogState();
}

class _RenumberDialogState extends State<_RenumberDialog> {
  final _ctrl = TextEditingController(text: '1');

  int get _start => int.tryParse(_ctrl.text.trim()) ?? 1;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final start = _start;
    final end = start + widget.count - 1;
    return AlertDialog(
      title: Text('Renumber ${widget.count} '
          '${widget.count == 1 ? 'dive' : 'dives'}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _ctrl,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Start number'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          Text('#$start → #$end · by date (oldest first)',
              style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(RenumberReset()),
          child: const Text('Reset to automatic'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(RenumberApply(start)),
          child: const Text('Apply'),
        ),
      ],
    );
  }
}
```

- [ ] **Step 2: Selection-bar actions** — in `lib/ui/app_shell.dart`, add an import `import 'widgets/renumber_dialog.dart';`. In `_buildSelectionAppBar`, prepend two actions before the existing Merge `IconButton` in the `actions:` list:

```dart
        IconButton(
          tooltip: 'Select all',
          icon: const Icon(Icons.select_all),
          onPressed: n.selectAll,
        ),
        IconButton(
          tooltip: 'Renumber selected dives',
          icon: const Icon(Icons.format_list_numbered),
          onPressed: n.selectedDiveIds.isEmpty
              ? null
              : () async {
                  final result = await showRenumberDialog(
                      context, n.selectedDiveIds.length);
                  if (result is RenumberApply) {
                    await n.renumberSelected(result.start);
                  } else if (result is RenumberReset) {
                    await n.resetNumberingSelected();
                  }
                },
        ),
```

- [ ] **Step 3: Smoke test** — create `test/ui/widgets/renumber_dialog_test.dart`:

```dart
import 'package:ccrlogger/ui/widgets/renumber_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows preview and returns RenumberApply with the start number',
      (tester) async {
    RenumberResult? result;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async =>
                result = await showRenumberDialog(context, 5),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Renumber 5 dives'), findsOneWidget);
    expect(find.textContaining('#1 → #5'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '482');
    await tester.pump();
    expect(find.textContaining('#482 → #486'), findsOneWidget);

    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(result, isA<RenumberApply>());
    expect((result as RenumberApply).start, 482);
  });
}
```

- [ ] **Step 4: Verify**

Run: `flutter test test/ui/widgets/renumber_dialog_test.dart` → PASS (adjust the dialog if the preview-text finder fails, e.g. the `ctx_or` helper).
Run: `flutter analyze` → clean. `flutter test` → all green.

- [ ] **Step 5: Manual verification**

`flutter run`; on the Dives tab long-press a dive → selection app bar shows **Select all**, **Renumber**, **Merge**. Tap Select all → Renumber → enter 482 → preview "#482 → #1200" → Apply → list + detail numbers update and persist across restart; reopen Renumber → Reset to automatic → back to the date sequence. (Cross-device sync only after the `0015` Supabase migration is deployed.)

- [ ] **Step 6: Commit**

```bash
git add lib/ui/widgets/renumber_dialog.dart lib/ui/app_shell.dart \
        test/ui/widgets/renumber_dialog_test.dart
git commit -m "feat(renumber): renumber dialog + Select-all/Renumber selection actions" \
           -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Done criteria
- `flutter analyze` clean; `flutter test` green (incl. `computeRenumber`, renumber-dialog smoke, migration v19→v20).
- Select all + Renumber + reset work from the selection app bar; numbers persist and override the auto sequence; reset restores it.
- `supabase/migrations/0015_dive_user_number.sql` created (maintainer deploys it for cross-device sync).
- Open a PR (`feat/dive-renumbering` → `feat/statistics-tab`, or `main` after #60/#61 merge); squash-merge per repo workflow; then bump the app version and tag the release.

## Notes for the implementer
- **Migration test seeding** (Task 1 Step 6): the v19→v20 test must open a DB whose `dive_annotations` exists before the addColumn runs — mirror the existing v11→v12 test's `_seedV1SyncTables(... withOwnerId: true)` + `PRAGMA user_version` approach exactly.
- **DAO/notifier tests** are conditional on existing PowerSync test harnesses; the pure `computeRenumber` is the guaranteed logic test. Don't invent a PowerSync harness if none exists — note it and rely on manual verification for the DAO/notifier wiring.
- **Positional SQL args** in the DAO (Task 2): the INSERT/UPDATE arg arrays are positional — when you add `user_dive_number`, put its arg in the exact matching slot. Re-read the method after editing to confirm column/arg alignment.
