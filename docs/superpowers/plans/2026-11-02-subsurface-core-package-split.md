# `packages/subsurface_core` Package Split Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the Subsurface format, both mappers, the sync planner, the snapshot builder, the domain models, the sample codec and the parser data types out of the app into a pure-Dart package `packages/subsurface_core`, with no behaviour change, so the app and the future server share one implementation.

**Architecture:** The package mirrors the app's directory layout under `lib/` (so `git mv` keeps history and every import becomes a prefix swap from `package:ccrlogger/…` to `package:subsurface_core/…`). The two Drift-row-typed seams (`mapper.dart`, `sync_planner.dart`) switch to three plain input classes defined in the package; the app builds them from Drift rows in one adapter file next to the orchestrator. The one `dart:io` consumer that must move (`remote_snapshot.dart`) is split into a pure "parse these files" builder in the package and a directory walker that stays in the app. A purity test in the package fails on any Flutter, Drift, PowerSync, or I/O import.

**Tech Stack:** Dart 3.11+ (the repo pins Flutter 3.44.0 / Dart 3.12.0), `package:test`, `package:lints`, `crypto`. Path dependency from the app; no pub workspace.

**Spec:** `docs/superpowers/specs/2026-11-02-subsurface-sync-service-design.md`, sections 6 (the split), 10 (rollout step 1), 11 (testing), 12 (left to the builder). Until branch `spec/subsurface-sync-service` (commit `7ab7b59`) is merged, read it with `git show spec/subsurface-sync-service:docs/superpowers/specs/2026-11-02-subsurface-sync-service-design.md`.

## Global Constraints

- **Pure refactor.** App behaviour is unchanged. Every existing test keeps its assertions; only import lines, test-framework imports and the row-type helpers change. (Spec §10 step 1.)
- **The package has no Flutter, Drift, PowerSync or I/O imports** in `lib/`. (Spec §6.) One allow-listed exception: `lib/data/sample_codec/column_packer.dart` keeps `import 'dart:io'` for `ZLibEncoder`/`ZLibDecoder`, the only zlib in the Dart SDK. See "Where the spec and the code differ".
- **The package must not depend on the generated database.** Mapper and planner take plain input classes; the app builds them from Drift rows, the server (later) from Postgres rows. (Spec §6.)
- **Moved tests move with the code and keep passing; the real-repo fixtures are the contract.** (Spec §6.) The fixtures move with the tests.
- **Keep in the app:** `repo.dart`, `ssl_certs.dart`, `credentials.dart`, `sync_orchestrator.dart`, `bootstrap_importer.dart`, `dao_subsurface_sync_data_source.dart` and their tests. (Spec §6, deleted in rollout step 5.)
- **Project conventions (CLAUDE.md):** never run `dart format` on a whole file (main is not format-clean; match the surrounding style by hand); every dependency is a liability, add none beyond `crypto`, `test`, `lints`; everything in git is English; CI is `flutter analyze` + `flutter test` and must stay green per task.
- **`flutter analyze` is fatal on infos and warnings.** Remove imports that the refactor makes unused (`package:drift/drift.dart show Value` in two files, `package:path/path.dart` in the moved snapshot).
- **History:** move files with `git mv`, never delete-and-recreate.
- **Commits:** one per task, conventional prefix (`refactor:`, `test:`, `chore:`), body in English, ending with `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.

## Review Focus

Inputs the spec implies but no existing test exercises; each line names the task whose tests pin it.

1. **A dive without gradient factors** (`gfLow`/`gfHigh` null: VPM-B dives, old imports). The adapter must pass the nulls through unchanged so the mapper keeps omitting the `Deco model` keyvalue; a default of 0 would emit `GF 0/0`. Pinned in Task 4 (`drift_sync_inputs_test.dart`).
2. **A repo checked out on Windows.** `Directory.listSync` returns backslash paths; the snapshot keys must be POSIX (`2026/04/04-Sat-13=30=15/Dive-705`) or every dive looks new and gets re-emitted. Pinned in Task 5 (`remote_repo_reader_test.dart`).
3. **A non-UTF-8 file inside the repo** (a stray binary, a Latin-1 note from 2004). Today's reader catches the decode error per file and skips it; the walker must keep that or one bad file blocks the whole sync. Pinned in Task 5 (`remote_repo_reader_test.dart`).
4. **A dive folder with both `Divecomputer` and `Divecomputer-001`.** The bare file must win, deterministically, whatever order the walker listed them in. Pinned in Task 5 (`remote_snapshot_test.dart`).
5. **Clearing an annotation field** (`copyWith(notes: Patch(null))`) versus leaving it alone (`copyWith()`). The Drift `Value` replacement must keep both meanings or "remove site" in the UI silently stops working. Pinned in Task 2 (`annotation_test.dart`).

---

## File map

### Created

| Path | Responsibility |
|---|---|
| `packages/subsurface_core/pubspec.yaml` | Package manifest (Task 1) |
| `packages/subsurface_core/analysis_options.yaml` | `package:lints/recommended.yaml` (Task 1) |
| `packages/subsurface_core/README.md` | Four lines: what is here, the purity rule, how to run tests (Task 1) |
| `packages/subsurface_core/lib/subsurface_core.dart` | Barrel exporting every public library (Task 1, extended in Tasks 3 and 6) |
| `packages/subsurface_core/test/purity_test.dart` | Fails on forbidden imports in `lib/` (Task 1) |
| `packages/subsurface_core/lib/sync/subsurface_git/sync_inputs.dart` | `SubsurfaceDiveInput`, `SubsurfaceCylinderInput`, `SubsurfaceDiveComputerInput` (written in the app in Task 4, moved in Task 6) |
| `lib/sync/subsurface_git/drift_sync_inputs.dart` | App-side builders from Drift rows (Task 4) |
| `test/sync/subsurface_git/drift_sync_inputs_test.dart` | (Task 4) |
| `lib/sync/subsurface_git/remote_repo_reader.dart` | `readRemoteRepoFiles(Directory)`: the `dart:io` walk (Task 5) |
| `test/sync/subsurface_git/remote_repo_reader_test.dart` | (Task 5) |
| `test/data/models/annotation_test.dart` | `Patch` semantics (Task 2, moved to the package in Task 3) |

### Moved with `git mv` (app path → package path; the path under `lib/` is identical)

Task 3:

```
lib/data/models/annotation.dart                 → packages/subsurface_core/lib/data/models/annotation.dart
lib/data/models/dive.dart                       → packages/subsurface_core/lib/data/models/dive.dart
lib/data/models/sample_set.dart                 → packages/subsurface_core/lib/data/models/sample_set.dart
lib/data/sample_codec/active_per_mix.dart       → packages/subsurface_core/lib/data/sample_codec/active_per_mix.dart
lib/data/sample_codec/column_packer.dart        → packages/subsurface_core/lib/data/sample_codec/column_packer.dart
lib/data/sample_codec/dive_stats.dart           → packages/subsurface_core/lib/data/sample_codec/dive_stats.dart
lib/data/sample_codec/sample_codec.dart         → packages/subsurface_core/lib/data/sample_codec/sample_codec.dart
lib/shearwater/parser/constants.dart            → packages/subsurface_core/lib/shearwater/parser/constants.dart
lib/shearwater/parser/hardware.dart             → packages/subsurface_core/lib/shearwater/parser/hardware.dart
lib/shearwater/parser/parsed_dive.dart          → packages/subsurface_core/lib/shearwater/parser/parsed_dive.dart
lib/shearwater/parser/dive_converter.dart       → packages/subsurface_core/lib/shearwater/parser/dive_converter.dart
test/data/models/annotation_test.dart           → packages/subsurface_core/test/data/models/annotation_test.dart
test/data/sample_codec/active_per_mix_test.dart → packages/subsurface_core/test/data/sample_codec/active_per_mix_test.dart
test/data/sample_codec/column_packer_test.dart  → packages/subsurface_core/test/data/sample_codec/column_packer_test.dart
test/data/sample_codec/dive_stats_test.dart     → packages/subsurface_core/test/data/sample_codec/dive_stats_test.dart
```

Task 6:

```
lib/sync/subsurface_git/format/subsurface_format.dart          → packages/subsurface_core/lib/sync/subsurface_git/format/subsurface_format.dart
lib/sync/subsurface_git/format/subsurface_parser.dart          → packages/subsurface_core/lib/sync/subsurface_git/format/subsurface_parser.dart
lib/sync/subsurface_git/format/subsurface_serializer.dart      → packages/subsurface_core/lib/sync/subsurface_git/format/subsurface_serializer.dart
lib/sync/subsurface_git/format/subsurface_unit_parsing.dart    → packages/subsurface_core/lib/sync/subsurface_git/format/subsurface_unit_parsing.dart
lib/sync/subsurface_git/sync_inputs.dart                       → packages/subsurface_core/lib/sync/subsurface_git/sync_inputs.dart
lib/sync/subsurface_git/mapper.dart                            → packages/subsurface_core/lib/sync/subsurface_git/mapper.dart
lib/sync/subsurface_git/sync_planner.dart                      → packages/subsurface_core/lib/sync/subsurface_git/sync_planner.dart
lib/sync/subsurface_git/remote_snapshot.dart                   → packages/subsurface_core/lib/sync/subsurface_git/remote_snapshot.dart
lib/sync/subsurface_git/subsurface_to_ccrlog_mapper.dart       → packages/subsurface_core/lib/sync/subsurface_git/subsurface_to_ccrlog_mapper.dart
test/fixtures/subsurface/                                      → packages/subsurface_core/test/fixtures/subsurface/
test/fixtures/subsurface_incident_replica/                     → packages/subsurface_core/test/fixtures/subsurface_incident_replica/
test/sync/subsurface_git/mapper_test.dart                      → packages/subsurface_core/test/sync/subsurface_git/mapper_test.dart
test/sync/subsurface_git/mapper_divemaster_test.dart           → packages/subsurface_core/test/sync/subsurface_git/mapper_divemaster_test.dart
test/sync/subsurface_git/sync_planner_test.dart                → packages/subsurface_core/test/sync/subsurface_git/sync_planner_test.dart
test/sync/subsurface_git/remote_snapshot_test.dart             → packages/subsurface_core/test/sync/subsurface_git/remote_snapshot_test.dart
test/sync/subsurface_git/subsurface_format_test.dart           → packages/subsurface_core/test/sync/subsurface_git/subsurface_format_test.dart
test/sync/subsurface_git/subsurface_to_ccrlog_mapper_test.dart → packages/subsurface_core/test/sync/subsurface_git/subsurface_to_ccrlog_mapper_test.dart
test/sync/subsurface_git/subsurface_to_ccrlog_divemaster_test.dart → packages/subsurface_core/test/sync/subsurface_git/subsurface_to_ccrlog_divemaster_test.dart
```

### Stay in the app (imports rewritten only)

`lib/sync/subsurface_git/{bootstrap_importer,credentials,dao_subsurface_sync_data_source,repo,ssl_certs,sync_orchestrator}.dart` and their six tests; `lib/shearwater/parser/{byte_reader,decompressor,dive_parser,manifest_parser,slip_decoder}.dart` and `test/shearwater/parser/*`; `test/data/sample_codec/sample_codec_test.dart` (needs the binary parser and `test/fixtures/dives/*.bin`); `lib/data/models/{dive_attachment,dive_plan,equipment,gas_analysis,gas_analysis_csv}.dart`; every UI, DAO and analysis file that imports a moved file. `test/fixtures/dives/` stays (it is also a Flutter asset).

---

## The import rewriter

Tasks 3 and 6 rewrite imports with the same script. Save it outside the repo (for example in the session scratchpad as `rewrite_imports.dart`); it is not committed. It needs no pubspec: only `dart:io`.

For every `.dart` file under `lib/` and `test/` of the app it resolves each `import`/`export` URI; when the target is a file that now exists under `packages/subsurface_core/lib/`, the URI becomes `package:subsurface_core/<same path>`. Everything after the URI (`show`, `hide`, `as`) is untouched. Files already moved into the package are not touched.

```dart
import 'dart:io';

void main(List<String> args) {
  // resolveSymbolicLinksSync normalises `.` and trailing slashes; `.absolute`
  // alone leaves `/repo/.`, which never prefix-matches a resolved import.
  final root = Directory(args.single).resolveSymbolicLinksSync();
  final libRoot = '$root/lib/';
  final pkgLib = '$root/packages/subsurface_core/lib/';
  final re = RegExp(r"^(\s*(?:import|export)\s+)'([^']+)'", multiLine: true);
  for (final dir in ['lib', 'test']) {
    final files = Directory('$root/$dir')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));
    for (final f in files) {
      final src = f.readAsStringSync();
      final out = src.replaceAllMapped(re, (m) {
        final uri = m[2]!;
        String? rel;
        if (uri.startsWith('package:ccrlogger/')) {
          rel = uri.substring('package:ccrlogger/'.length);
        } else if (!uri.contains(':')) {
          final resolved = Uri.file(f.path).resolve(uri).toFilePath();
          if (resolved.startsWith(libRoot)) rel = resolved.substring(libRoot.length);
        }
        if (rel == null || !File('$pkgLib$rel').existsSync()) return m[0]!;
        return "${m[1]}'package:subsurface_core/$rel'";
      });
      if (out != src) f.writeAsStringSync(out);
    }
  }
}
```

Run: `dart <scratchpad>/rewrite_imports.dart <repo root>`. Then `git diff --stat` to confirm only import lines changed.

For tests that move into the package, a plain substitution does the job instead, because every `package:ccrlogger/` import they have targets a moved file (the one exception, `database.dart`, is removed by hand in Task 4):

```bash
sed -i '' -e 's#package:ccrlogger/#package:subsurface_core/#g' -e 's#package:flutter_test/flutter_test.dart#package:test/test.dart#g' <moved test files>
```

---

### Task 1: Package scaffold, app dependency, CI

**Files:**
- Create: `packages/subsurface_core/pubspec.yaml`, `packages/subsurface_core/analysis_options.yaml`, `packages/subsurface_core/README.md`, `packages/subsurface_core/lib/subsurface_core.dart`, `packages/subsurface_core/test/purity_test.dart`
- Modify: `pubspec.yaml` (app), `analysis_options.yaml` (app), `.github/workflows/check.yml`, `.gitignore`

**Interfaces:**
- Produces: the package `subsurface_core`, importable from the app as `package:subsurface_core/...`; the purity test that Tasks 3, 5 and 6 must keep green.

- [ ] **Step 1: Write the package manifest and analysis options**

`packages/subsurface_core/pubspec.yaml`:

```yaml
name: subsurface_core
description: >-
  Subsurface git-format parser and serializer, the Anchorline <-> Subsurface
  mappers, the sync planner, and the domain types they need. Pure Dart,
  shared by the Anchorline app and the Anchorline server.
publish_to: none

environment:
  sdk: ^3.11.5

dependencies:
  # sha256 for dive ids, site ids and the Subsurface deviceid derivative.
  crypto: ^3.0.6

dev_dependencies:
  lints: ^6.0.0
  test: ^1.26.0
```

`packages/subsurface_core/analysis_options.yaml`:

```yaml
include: package:lints/recommended.yaml
```

`packages/subsurface_core/README.md`: four lines stating that this package holds the Subsurface format code shared by app and server, that `lib/` may import no Flutter, Drift, PowerSync or I/O (`test/purity_test.dart` enforces it; `column_packer.dart`'s `dart:io` zlib import is the one allowed exception), that the layout mirrors the app's `lib/` on purpose, and that tests run with `dart test` from this directory.

`packages/subsurface_core/lib/subsurface_core.dart`: a `library;` directive with a doc comment ("Barrel for subsurface_core. Server code imports this; the app imports the individual libraries it needs.") and no exports yet. Tasks 3 and 6 add the `export` lines.

- [ ] **Step 2: Write the failing purity test**

`packages/subsurface_core/test/purity_test.dart`:

```dart
import 'dart:io';

import 'package:test/test.dart';

/// Import lines that would tie the package to the app or to a platform.
/// `package:path` is listed because the only user was the snapshot's
/// directory walk, which belongs in the app.
final _forbidden = RegExp(
  r"""^\s*(import|export)\s+'(package:flutter|package:drift|package:powersync|package:path/|dart:io|dart:ui|dart:ffi)""",
);

/// `ZLibEncoder`/`ZLibDecoder` live in dart:io and have no pure-Dart
/// equivalent in the SDK. The column packer is the only file allowed to
/// import dart:io, and only for that.
const _allowed = {
  'lib/data/sample_codec/column_packer.dart': "import 'dart:io';",
};

void main() {
  test('lib/ has no Flutter, Drift, PowerSync, path or I/O imports', () {
    final offenders = <String>[];
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));
    for (final f in files) {
      for (final line in f.readAsLinesSync()) {
        if (!_forbidden.hasMatch(line)) continue;
        if (_allowed[f.path] == line.trim()) continue;
        offenders.add('${f.path}: ${line.trim()}');
      }
    }
    expect(offenders, isEmpty);
  });

  test('every lib/ file is exported by the barrel', () {
    final barrel = File('lib/subsurface_core.dart').readAsStringSync();
    final missing = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .map((f) => f.path.substring('lib/'.length))
        .where((p) => p.endsWith('.dart') && p != 'subsurface_core.dart')
        .where((p) => !barrel.contains("export '$p';"))
        .toList();
    expect(missing, isEmpty);
  });
}
```

- [ ] **Step 3: Run the package tests**

Run: `cd packages/subsurface_core && dart pub get && dart test`
Expected: both tests PASS (an empty `lib/` has no offenders and nothing missing from the barrel).

- [ ] **Step 4: Add the path dependency to the app**

In the app's `pubspec.yaml`, under `dependencies:` after `ffi: 2.2.0`:

```yaml
  # Subsurface format, mappers, planner and the domain types they need.
  # Pure Dart, shared with the server (spec 2026-11-02, section 6).
  subsurface_core:
    path: packages/subsurface_core
```

- [ ] **Step 5: Keep the root analyzer out of the package**

`flutter analyze` at the repo root descends into nested packages (that is why `macos/**` and the other platform folders are excluded today). The package has its own dev dependencies that the app's package config does not know, so analyze it on its own. In the app's `analysis_options.yaml`, add to `analyzer: exclude:`:

```yaml
    # The pure-Dart package has its own pubspec, dev deps and analysis
    # options; CI analyzes and tests it with `dart` from its own directory.
    - packages/**
```

- [ ] **Step 6: Ignore the package lockfile**

Append to `.gitignore`:

```
# Library packages inside the repo resolve their own dev deps; their
# lockfiles are not committed (the app's pubspec.lock is).
packages/*/pubspec.lock
```

- [ ] **Step 7: Add the package to CI**

In `.github/workflows/check.yml`, after the `Set up Flutter` step and before `flutter pub get`:

```yaml
      # The pure-Dart package is analyzed and tested on its own: it has
      # dev dependencies the app does not resolve, and the root analyzer
      # excludes packages/** for that reason.
      - name: subsurface_core pub get
        run: dart pub get
        working-directory: packages/subsurface_core

      - name: subsurface_core analyze
        run: dart analyze --fatal-infos
        working-directory: packages/subsurface_core

      - name: subsurface_core test
        run: dart test --reporter expanded
        working-directory: packages/subsurface_core
```

`--fatal-infos` matches `flutter analyze`'s default strictness.

- [ ] **Step 8: Verify both sides**

Run: `cd packages/subsurface_core && dart analyze --fatal-infos && dart test`
Expected: `No issues found!`, `All tests passed!`

Run (repo root): `flutter pub get && flutter analyze && flutter test`
Expected: `No issues found!`, all tests pass (nothing has moved yet).

- [ ] **Step 9: Commit**

```bash
git add packages/subsurface_core pubspec.yaml pubspec.lock analysis_options.yaml .github/workflows/check.yml .gitignore
git commit -m "chore: scaffold packages/subsurface_core and wire it into the app and CI"
```

---

### Task 2: Replace Drift's `Value` in `annotation.dart` with a local sentinel

**Files:**
- Modify: `lib/data/models/annotation.dart`, `lib/ui/notifiers/dive_annotations_notifier.dart`, `lib/data/db/dive_annotations_dao.dart:552-580`, `test/data/db/dive_annotations_dao_test.dart:168-172`, `test/data/db/dive_annotations_user_number_test.dart:65`
- Test: `test/data/models/annotation_test.dart` (new; moves to the package in Task 3)

**Interfaces:**
- Produces: `final class Patch<T> { const Patch(this.value); final T value; }` in `annotation.dart`. `DiveAnnotation.copyWith` takes `Patch<X?>?` for every parameter that took `Value<X?>?`. Semantics unchanged: `null` keeps the field, `Patch(v)` sets it to `v`, which may be null.

- [ ] **Step 1: Write the failing test**

`test/data/models/annotation_test.dart` (uses `flutter_test` for now; Task 3 moves it and swaps the import):

```dart
import 'package:ccrlogger/data/models/annotation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final t = DateTime.utc(2026, 11, 2);
  final a = DiveAnnotation(
    diveId: 'd',
    notes: 'hello',
    rating: 3,
    siteName: 'Om Sid',
    createdAt: t,
    updatedAt: t,
  );

  test('copyWith() keeps every field', () {
    final b = a.copyWith();
    expect(b.notes, 'hello');
    expect(b.rating, 3);
    expect(b.siteName, 'Om Sid');
  });

  test('Patch(null) clears a field', () {
    expect(a.copyWith(notes: const Patch(null)).notes, isNull);
    expect(a.copyWith(siteName: const Patch(null)).siteName, isNull);
  });

  test('Patch(value) sets a field and leaves the others alone', () {
    final b = a.copyWith(rating: const Patch(5));
    expect(b.rating, 5);
    expect(b.notes, 'hello');
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/data/models/annotation_test.dart`
Expected: compile error, `Patch` is not defined.

- [ ] **Step 3: Define `Patch<T>` and drop the Drift import**

In `lib/data/models/annotation.dart`: remove `import 'package:drift/drift.dart' show Value;`; add, above `enum SyncStatus`:

```dart
/// Marks a nullable field as "set to [value]" in [DiveAnnotation.copyWith].
/// Passing `null` for the parameter itself leaves the field unchanged.
/// Stands in for Drift's `Value<T>` so this file has no Drift import
/// (it is shared with the server through `subsurface_core`).
final class Patch<T> {
  const Patch(this.value);
  final T value;
}
```

In `copyWith`, replace every `Value<` with `Patch<` (every nullable parameter, from `siteName` to `deletedAt`). The body (`x == null ? this.x : x.value`) is unchanged.

- [ ] **Step 4: Update the callers**

- `lib/ui/notifiers/dive_annotations_notifier.dart`: replace every `Value(` with `Patch(` (every occurrence in that file is a `copyWith` argument); delete `import 'package:drift/drift.dart' show Value;` (it becomes unused).
- `lib/data/db/dive_annotations_dao.dart`: line 552 `Value(toName)` → `Patch(toName)`; lines 578–580 `const Value(null)` → `const Patch(null)`. Keep the Drift import: the file still uses `Value` for companions elsewhere; if `flutter analyze` reports it unused, remove it.
- `test/data/db/dive_annotations_dao_test.dart` lines 168 and 172, `test/data/db/dive_annotations_user_number_test.dart` line 65: `const Value('…')` → `const Patch('…')`; remove each file's `import 'package:drift/drift.dart' show Value;` if it is now unused.

- [ ] **Step 5: Run the tests**

Run: `flutter analyze && flutter test test/data/models test/data/db/dive_annotations_dao_test.dart test/data/db/dive_annotations_user_number_test.dart test/ui`
Expected: `No issues found!`, all pass.

- [ ] **Step 6: Commit**

```bash
git add lib/data/models/annotation.dart lib/ui/notifiers/dive_annotations_notifier.dart lib/data/db/dive_annotations_dao.dart test/data
git commit -m "refactor(models): replace Drift Value in DiveAnnotation.copyWith with a local Patch sentinel"
```

---

### Task 3: Move the domain models, sample codec and parser data types

**Files:**
- Move: the Task 3 block of the file map (11 library files, 4 test files)
- Modify: `packages/subsurface_core/lib/subsurface_core.dart` (exports); every app file whose import the rewriter touches (expect roughly 100 files; the exact list is `git diff --name-only`)

**Interfaces:**
- Consumes: Task 1's package; Task 2's Drift-free `annotation.dart`.
- Produces: `package:subsurface_core/data/models/{annotation,dive,sample_set}.dart`, `package:subsurface_core/data/sample_codec/{active_per_mix,column_packer,dive_stats,sample_codec}.dart`, `package:subsurface_core/shearwater/parser/{constants,hardware,parsed_dive,dive_converter}.dart`, identical contents.

- [ ] **Step 1: Move the files**

```bash
mkdir -p packages/subsurface_core/lib/data/models packages/subsurface_core/lib/data/sample_codec packages/subsurface_core/lib/shearwater/parser
git mv lib/data/models/annotation.dart lib/data/models/dive.dart lib/data/models/sample_set.dart packages/subsurface_core/lib/data/models/
git mv lib/data/sample_codec/active_per_mix.dart lib/data/sample_codec/column_packer.dart lib/data/sample_codec/dive_stats.dart lib/data/sample_codec/sample_codec.dart packages/subsurface_core/lib/data/sample_codec/
git mv lib/shearwater/parser/constants.dart lib/shearwater/parser/hardware.dart lib/shearwater/parser/parsed_dive.dart lib/shearwater/parser/dive_converter.dart packages/subsurface_core/lib/shearwater/parser/
```

The relative imports among these eleven files resolve exactly as before because the layout is mirrored; the only non-moved target any of them imported was Drift, removed in Task 2. `lib/data/sample_codec/` is now empty and disappears from git.

- [ ] **Step 2: Export them from the barrel**

Add to `packages/subsurface_core/lib/subsurface_core.dart`, one line per moved file, in the file-map order: `export 'data/models/annotation.dart';` … `export 'shearwater/parser/dive_converter.dart';`.

- [ ] **Step 3: Verify the package**

Run: `cd packages/subsurface_core && dart analyze --fatal-infos && dart test`
Expected: `No issues found!`; the purity test passes (the only `dart:io` is the allow-listed one); the barrel test passes.

- [ ] **Step 4: Rewrite the app's imports**

Run the rewriter: `dart <scratchpad>/rewrite_imports.dart .`

Then `flutter analyze`. Expected: `No issues found!`. If an import was missed, the analyzer names it; fix it by hand with the same `package:subsurface_core/<path>` form. Spot-check these four, which use unusual forms:
- `lib/shearwater/parser/dive_parser.dart`: `import 'constants.dart'`, `'hardware.dart'`, `'parsed_dive.dart'` and `export 'parsed_dive.dart';` all now point at the package.
- `lib/data/models/dive_attachment.dart`: `import 'annotation.dart' show SyncStatus;` and `export 'annotation.dart' show SyncStatus;` likewise.
- `lib/data/db/dive_dao.dart`: `'../models/sample_set.dart'`, `'../sample_codec/sample_codec.dart'`, `'../../shearwater/parser/dive_converter.dart'`.
- `lib/data/db/equipment_dao.dart`: `'../sample_codec/column_packer.dart'`.

- [ ] **Step 5: Move the four pure tests and switch their framework import**

```bash
mkdir -p packages/subsurface_core/test/data/models packages/subsurface_core/test/data/sample_codec
git mv test/data/models/annotation_test.dart packages/subsurface_core/test/data/models/
git mv test/data/sample_codec/active_per_mix_test.dart test/data/sample_codec/column_packer_test.dart test/data/sample_codec/dive_stats_test.dart packages/subsurface_core/test/data/sample_codec/
sed -i '' -e 's#package:ccrlogger/#package:subsurface_core/#g' -e 's#package:flutter_test/flutter_test.dart#package:test/test.dart#g' packages/subsurface_core/test/data/models/annotation_test.dart packages/subsurface_core/test/data/sample_codec/*.dart
```

`test/data/sample_codec/sample_codec_test.dart` stays in the app (it drives the binary parser over `test/fixtures/dives/*.bin`); the rewriter already pointed its imports at the package.

- [ ] **Step 6: Verify both sides**

Run: `cd packages/subsurface_core && dart analyze --fatal-infos && dart test`
Expected: `No issues found!`, all tests pass (purity, barrel, annotation, three codec tests).

Run (root): `flutter analyze && flutter test`
Expected: `No issues found!`, all tests pass. The test count drops by the four moved files' tests and by nothing else.

- [ ] **Step 7: Commit**

```bash
git add -A lib test packages
git commit -m "refactor: move domain models, sample codec and parser data types into subsurface_core"
```

---

### Task 4: Plain input records for the mapper and planner

Done inside the app, before the files move, so the type swap is reviewable on its own and `sync_orchestrator_test.dart` (the end-to-end guard against a local bare git remote) proves behaviour is unchanged.

**Files:**
- Create: `lib/sync/subsurface_git/sync_inputs.dart`, `lib/sync/subsurface_git/drift_sync_inputs.dart`, `test/sync/subsurface_git/drift_sync_inputs_test.dart`
- Modify: `lib/sync/subsurface_git/mapper.dart`, `lib/sync/subsurface_git/sync_planner.dart`, `lib/sync/subsurface_git/sync_orchestrator.dart:296-320`, `test/sync/subsurface_git/mapper_test.dart`, `test/sync/subsurface_git/mapper_divemaster_test.dart`, `test/sync/subsurface_git/sync_planner_test.dart`, `test/sync/subsurface_git/subsurface_to_ccrlog_mapper_test.dart:536-566`, `test/ui/widgets/subsurface_sync_section_test.dart:562-590`

**Interfaces:**
- Produces, in `sync_inputs.dart`:

```dart
/// The dive fields the write mapper and the planner read. The app builds
/// it from the Drift `Dive` row, the server from the `dives` Postgres row.
/// Encodings are the row's: epoch seconds, millimetres, raw enum codes
/// (`DiveMode.value`, `ShearwaterModel.index`), JSON text.
final class SubsurfaceDiveInput {
  const SubsurfaceDiveInput({
    required this.id,
    required this.dcSerial,
    required this.dcDiveNumber,
    required this.startTime,
    required this.durationSeconds,
    required this.maxDepthMm,
    required this.diveMode,
    required this.dcModel,
    required this.logVersion,
    required this.atmosphericPressureMbar,
    required this.waterDensity,
    this.dcFirmware,
    this.gfLow,
    this.gfHigh,
    this.sensorCalibrationJson,
    this.configuredStackSeconds,
    this.stackRemainingAtStartSeconds,
    this.stackRemainingAtEndSeconds,
  });
  final String id;
  final int dcSerial;
  final int dcDiveNumber;
  final int startTime;            // unix seconds, as stored
  final int durationSeconds;
  final int maxDepthMm;
  final int diveMode;             // DiveMode.value
  final int dcModel;              // ShearwaterModel.index
  final int logVersion;
  final int atmosphericPressureMbar;
  final int waterDensity;         // kg/m³
  final int? dcFirmware;
  final int? gfLow;
  final int? gfHigh;
  final String? sensorCalibrationJson;
  final int? configuredStackSeconds;
  final int? stackRemainingAtStartSeconds;
  final int? stackRemainingAtEndSeconds;
}

/// The cylinder fields the mapper reads for a `cylinder` line.
final class SubsurfaceCylinderInput {
  const SubsurfaceCylinderInput({
    required this.label,
    required this.volumeLiters,
    required this.workingPressureBar,
  });
  final String label;
  final double volumeLiters;
  final int workingPressureBar;
}

/// The dive-computer fields the mapper reads for a `divecomputerid` line.
final class SubsurfaceDiveComputerInput {
  const SubsurfaceDiveComputerInput({
    required this.serial,
    required this.model,            // ShearwaterModel.index
    this.nickname,
  });
  final int serial;
  final int model;
  final String? nickname;
}
```

- Produces, in `drift_sync_inputs.dart` (imports `../../data/db/database.dart show Cylinder, Dive, DiveComputer` and `sync_inputs.dart`):

```dart
SubsurfaceDiveInput diveInputFromRow(Dive row);
SubsurfaceCylinderInput cylinderInputFromRow(Cylinder row);
SubsurfaceDiveComputerInput diveComputerInputFromRow(DiveComputer row);
```

Each copies the same-named fields, nothing else.

- Changes: in `mapper.dart` and `sync_planner.dart`, every `Dive` becomes `SubsurfaceDiveInput`, every `Cylinder` becomes `SubsurfaceCylinderInput`, every `DiveComputer` becomes `SubsurfaceDiveComputerInput`; the `database.dart` import becomes `import 'sync_inputs.dart';`. Public surface affected: `CcrlogToSubsurfaceMapper.mapDive({required SubsurfaceDiveInput dive, …, required Map<int, SubsurfaceCylinderInput> cylindersByMixIndex, …})`, `topLevelDelta({required Iterable<SubsurfaceDiveInput> dives, required Iterable<SubsurfaceDiveComputerInput> diveComputers})`, `CcrlogDiveBundle.dive`, `CcrlogDiveBundle.cylindersByMixIndex`, `CcrlogDiveBundle.userDiveComputers`, `AbortedDive.dive`. `SubsurfaceSyncDataSource` (the orchestrator's seam) keeps returning Drift rows; `dao_subsurface_sync_data_source.dart` and its test do not change.

- [ ] **Step 1: Write the failing adapter test**

`test/sync/subsurface_git/drift_sync_inputs_test.dart`:

```dart
import 'dart:typed_data';

import 'package:ccrlogger/data/db/database.dart' hide DiveAnnotation;
import 'package:ccrlogger/sync/subsurface_git/drift_sync_inputs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('diveInputFromRow copies every field the mapper reads', () {
    final row = Dive(
      id: 'dive-id-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      dcSerial: 0xb89641e4,
      dcDiveNumber: 705,
      startTime: 1776591525,
      endTime: 1776591525 + 3450,
      durationSeconds: 3450,
      maxDepthMm: 18000,
      diveMode: 0,
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
      sensorCalibrationJson: '[0.021,0.022,0.023]',
      configuredStackSeconds: 25200,
      stackRemainingAtStartSeconds: 10847,
      stackRemainingAtEndSeconds: 7347,
      rawBlob: Uint8List(0),
      parserVersion: 1,
      importedAt: 1776591525,
    );
    final i = diveInputFromRow(row);
    expect(i.id, row.id);
    expect(i.dcSerial, 0xb89641e4);
    expect(i.dcDiveNumber, 705);
    expect(i.startTime, 1776591525);
    expect(i.durationSeconds, 3450);
    expect(i.maxDepthMm, 18000);
    expect(i.diveMode, 0);
    expect(i.dcModel, 3);
    expect(i.dcFirmware, 0xa3);
    expect(i.logVersion, 17);
    expect(i.atmosphericPressureMbar, 1013);
    expect(i.waterDensity, 1025);
    expect(i.gfLow, 50);
    expect(i.gfHigh, 95);
    expect(i.sensorCalibrationJson, '[0.021,0.022,0.023]');
    expect(i.configuredStackSeconds, 25200);
    expect(i.stackRemainingAtStartSeconds, 10847);
    expect(i.stackRemainingAtEndSeconds, 7347);
  });

  test('nullable row fields stay null (VPM-B dive, OC dive, old import)', () {
    final row = Dive(
      id: 'x', dcSerial: 1, dcDiveNumber: 2, startTime: 3, endTime: 4,
      durationSeconds: 1, maxDepthMm: 1, diveMode: 8, decoModel: 1,
      atmosphericPressureMbar: 1013, waterDensity: 1000, logVersion: 17,
      dcModel: 3, sampleIntervalMs: 10000, gasMixesJson: '',
      rawBlob: Uint8List(0), parserVersion: 1, importedAt: 0,
    );
    final i = diveInputFromRow(row);
    expect(i.gfLow, isNull);
    expect(i.gfHigh, isNull);
    expect(i.dcFirmware, isNull);
    expect(i.sensorCalibrationJson, isNull);
    expect(i.configuredStackSeconds, isNull);
    expect(i.stackRemainingAtStartSeconds, isNull);
    expect(i.stackRemainingAtEndSeconds, isNull);
  });

  test('cylinderInputFromRow and diveComputerInputFromRow copy their fields', () {
    final cyl = Cylinder(
      id: 'c', label: 'AL40 stage', role: 'bailout', volumeLiters: 5.7,
      workingPressureBar: 207, createdAt: 0, updatedAt: 0, version: 1, syncStatus: 0,
    );
    final c = cylinderInputFromRow(cyl);
    expect(c.label, 'AL40 stage');
    expect(c.volumeLiters, 5.7);
    expect(c.workingPressureBar, 207);

    final dc = DiveComputer(
      id: 'dc', serial: 0xb89641e4, model: 3, nickname: 'Petrel 3',
      createdAt: 0, updatedAt: 0, version: 1, syncStatus: 0,
    );
    final d = diveComputerInputFromRow(dc);
    expect(d.serial, 0xb89641e4);
    expect(d.model, 3);
    expect(d.nickname, 'Petrel 3');
    expect(diveComputerInputFromRow(DiveComputer(
      id: 'dc2', serial: 7, model: 3, createdAt: 0, updatedAt: 0, version: 1, syncStatus: 0,
    )).nickname, isNull);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/sync/subsurface_git/drift_sync_inputs_test.dart`
Expected: compile error, `drift_sync_inputs.dart` does not exist.

- [ ] **Step 3: Write `sync_inputs.dart` and `drift_sync_inputs.dart`**

Exactly the Interfaces block above. `drift_sync_inputs.dart` carries a doc comment: "Builds the subsurface_core input records from Drift rows. This is the only place the app translates between the two; the server has its own builder from Postgres rows."

- [ ] **Step 4: Run the adapter test**

Run: `flutter test test/sync/subsurface_git/drift_sync_inputs_test.dart`
Expected: PASS.

- [ ] **Step 5: Switch `mapper.dart` and `sync_planner.dart` to the records**

In both files replace `import '../../data/db/database.dart' show Cylinder, Dive, DiveComputer;` with `import 'sync_inputs.dart';`, then rename the three types in every signature, field, local and generic (`<Dive>[]`, `<int, DiveComputer>{}`, `Map<int, Cylinder>`, `Iterable<Dive>`). Field reads are unchanged: every field the code reads (`dive.dcSerial`, `dive.maxDepthMm`, `dive.sensorCalibrationJson`, `cylinder?.label`, `dc.nickname`, …) exists on the record with the same name and type. Update the two doc comments that say "Drift `Dive` row" to say "`SubsurfaceDiveInput`".

Run: `flutter analyze lib/sync/subsurface_git/mapper.dart lib/sync/subsurface_git/sync_planner.dart`
Expected: errors only in callers (orchestrator, tests), none in these two files.

- [ ] **Step 6: Build the records in the orchestrator**

In `sync_orchestrator.dart` `_planAndPush`, after `final allComputers = await _data.listAllDiveComputers();`, add `final computerInputs = allComputers.map(diveComputerInputFromRow).toList();`. In the bundle loop, pass `dive: diveInputFromRow(dive)`, `cylindersByMixIndex: {for (final e in cylinders.entries) e.key: cylinderInputFromRow(e.value)}`, `userDiveComputers: computerInputs`. Add `import 'drift_sync_inputs.dart';`. The `database.dart` import stays (the `SubsurfaceSyncDataSource` seam still returns rows).

- [ ] **Step 7: Update the tests that built Drift rows**

- `mapper_test.dart`: `_ccrPetrelDive(...)` returns `SubsurfaceDiveInput` with the same values (drop `endTime`, `utcOffsetMinutes`, `decoModel`, `sampleIntervalMs`, `gasMixesJson`, `tanksJson`, `rawBlob`, `parserVersion`, `importedAt`); the inline OC `Dive(...)` at line 421 likewise (keep `diveMode: 8`); `_diveComputer()` returns `SubsurfaceDiveComputerInput(serial: 0xb89641e4, model: 3, nickname: 'Petrel 3')`. Replace `import 'package:ccrlogger/data/db/database.dart' hide DiveAnnotation;` with `import 'package:ccrlogger/sync/subsurface_git/sync_inputs.dart';`. Drop `dart:typed_data` only if it becomes unused (the sample-set helpers still need it).
- `mapper_divemaster_test.dart`: same for `_testDive()`.
- `sync_planner_test.dart`: same for `_ccrPetrelDive` and `_diveComputer({required int serial})` (`SubsurfaceDiveComputerInput(serial: serial, model: 3, nickname: 'Petrel 3')`).
- `subsurface_to_ccrlog_mapper_test.dart`: `_domainDiveToDbDive` becomes `SubsurfaceDiveInput _domainDiveToInput(Dive d)` mapping `d.startTime.millisecondsSinceEpoch ~/ 1000`, `d.duration.inSeconds`, `(d.maxDepthMeters * 1000).round()`, `d.diveMode.value`, `d.dcModel.index`, `d.waterDensityKgM3` → `waterDensity`, the rest by name. Replace the `database.dart as db` import with `sync_inputs.dart`.
- `test/ui/widgets/subsurface_sync_section_test.dart`: `_testDive({int diveNumber = 700})` returns `SubsurfaceDiveInput(id: 'test-$diveNumber', dcSerial: 123456, dcDiveNumber: diveNumber, startTime: 1747000000, durationSeconds: 3600, maxDepthMm: 30000, diveMode: 0, dcModel: 3, logVersion: 17, atmosphericPressureMbar: 1013, waterDensity: 1025)`; add the `sync_inputs.dart` import; drop `database.dart` and `dart:typed_data` if unused. The widget reads only `ab.dive.dcDiveNumber`.

- [ ] **Step 8: Run everything**

Run: `flutter analyze && flutter test`
Expected: `No issues found!`, all tests pass. `sync_orchestrator_test.dart` and `bootstrap_importer_test.dart` pass with no edits: that is the behaviour-unchanged evidence for this task.

- [ ] **Step 9: Commit**

```bash
git add lib/sync/subsurface_git test/sync/subsurface_git test/ui/widgets/subsurface_sync_section_test.dart
git commit -m "refactor(subsurface): mapper and planner take plain input records instead of Drift rows"
```

---

### Task 5: Split `remote_snapshot.dart` into a pure builder and an app-side walker

Also done in the app before the move.

**Files:**
- Modify: `lib/sync/subsurface_git/remote_snapshot.dart`, `lib/sync/subsurface_git/sync_orchestrator.dart:296`, `test/sync/subsurface_git/remote_snapshot_test.dart`
- Create: `lib/sync/subsurface_git/remote_repo_reader.dart`, `test/sync/subsurface_git/remote_repo_reader_test.dart`

**Interfaces:**
- Produces, in `remote_snapshot.dart` (no `dart:io`, no `path`): `RemoteSnapshotData` unchanged; `RemoteSnapshot.read(Directory)` is replaced by

```dart
class RemoteSnapshot {
  /// [filesByPath]: every regular file of the checked-out Subsurface repo,
  /// keyed by POSIX path relative to the repo root, value = file text.
  /// Paths outside the Subsurface layout (`.git/…`, anything else) are
  /// ignored. Per-file parse failures are skipped, as before.
  static RemoteSnapshotData fromFiles(Map<String, String> filesByPath);
}
```

Classification by path: `00-Subsurface` → top level; `01-Divesites/Site-<hex>` (exactly two segments) → sites keyed by `<hex>`; `<YYYY>/<MM>/<DD-Day-HH=MM=SS>/<name>` (exactly four segments, the three folder checks from today's `_isFourDigit`, `_isTwoDigit`, `_isDayFolderName`) → grouped per folder. Per folder, as today: the highest `Dive-NNN` wins; the bare `Divecomputer` wins over `Divecomputer-NNN`; absent a bare one, the first `Divecomputer-NNN` **in sorted key order** (today it was filesystem order). `_startTimeFromFolderName` and `_serialFromDivecomputer` are unchanged.

- Produces, in `remote_repo_reader.dart` (app, `dart:io` + `package:path`):

```dart
/// Reads every regular file under [repoRoot] into the map
/// [RemoteSnapshot.fromFiles] takes: keys are POSIX paths relative to
/// [repoRoot]. `.git/` is skipped. A missing root gives an empty map.
/// A file that is not valid UTF-8 is skipped, as the old reader did.
Future<Map<String, String>> readRemoteRepoFiles(Directory repoRoot);
```

- Changes: the orchestrator calls `RemoteSnapshot.fromFiles(await readRemoteRepoFiles(repoDir))`.

- [ ] **Step 1: Write the failing reader test**

`test/sync/subsurface_git/remote_repo_reader_test.dart` (`@TestOn('mac-os || linux || windows')`, temp dir per test):

```dart
test('reads every file keyed by POSIX relative path and skips .git', () async {
  File(p.join(tmp.path, '00-Subsurface')).writeAsStringSync('version 3\n');
  File(p.join(tmp.path, '2026', '04', '04-Sat-13=30=15', 'Dive-705'))
    ..createSync(recursive: true)
    ..writeAsStringSync('duration 57:30 min\n');
  File(p.join(tmp.path, '.git', 'HEAD'))
    ..createSync(recursive: true)
    ..writeAsStringSync('ref: refs/heads/x\n');
  final files = await readRemoteRepoFiles(tmp);
  expect(files.keys.toSet(), {'00-Subsurface', '2026/04/04-Sat-13=30=15/Dive-705'});
  expect(files['2026/04/04-Sat-13=30=15/Dive-705'], 'duration 57:30 min\n');
});

test('missing root gives an empty map', () async {
  expect(await readRemoteRepoFiles(Directory('${tmp.path}/nope')), isEmpty);
});

test('a file that is not valid UTF-8 is skipped', () async {
  File(p.join(tmp.path, 'ok')).writeAsStringSync('x\n');
  File(p.join(tmp.path, 'bad')).writeAsBytesSync([0xff, 0xfe, 0x00, 0xc3]);
  final files = await readRemoteRepoFiles(tmp);
  expect(files.keys, ['ok']);
});
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/sync/subsurface_git/remote_repo_reader_test.dart`
Expected: compile error, file missing.

- [ ] **Step 3: Write `readRemoteRepoFiles`**

`Directory.listSync(recursive: true, followLinks: false)`, keep `File`s, skip any whose relative path's first segment is `.git`, key = `p.posix.joinAll(p.split(p.relative(f.path, from: repoRoot.path)))`, value = `f.readAsStringSync()` inside a `try` that drops the entry on `FormatException`/`FileSystemException`.

- [ ] **Step 4: Run the reader test**

Run: `flutter test test/sync/subsurface_git/remote_repo_reader_test.dart`
Expected: PASS (three tests).

- [ ] **Step 5: Rewrite the snapshot tests against `fromFiles`**

In `remote_snapshot_test.dart` replace the temp-dir `setUp` with a helper that builds the map straight from the fixture tree in canonical layout:

```dart
Map<String, String> _fixtureFiles() => {
  '00-Subsurface': File('$_fixturesRoot/00-Subsurface').readAsStringSync(),
  for (final f in Directory('$_fixturesRoot/sites').listSync().whereType<File>())
    '01-Divesites/${p.basename(f.path)}': f.readAsStringSync(),
  for (final f in Directory('$_fixturesRoot/dives').listSync(recursive: true).whereType<File>())
    p.posix.joinAll(p.split(p.relative(f.path, from: '$_fixturesRoot/dives'))): f.readAsStringSync(),
};
```

Each existing test calls `RemoteSnapshot.fromFiles(_fixtureFiles())` and keeps its assertions (max 710; the two Petrel keys; `version 3`; the three site hexes and `Om Sid - Dahab`; `diveLines` populated). Replace the two disk-shaped tests:

- "returns empty snapshot when repoRoot does not exist" → `fromFiles(const {})` gives empty lists, empty maps, `existingMaxDiveNumber` 0.
- "skips folders whose names do not match the date format" → add `'.git/HEAD': 'ref: refs/heads/x\n'` and `'junk/Dive-999': 'duration 1:00 min\n'` to the map; `existingMaxDiveNumber` stays 710 and the keyed map size is unchanged.

Add one test for Review Focus item 4:

```dart
test('bare Divecomputer wins over Divecomputer-NNN whatever the map order', () {
  final folder = '2026/04/04-Sat-13=30=15';
  final bare = File('$_fixturesRoot/dives/$folder/Divecomputer').readAsStringSync();
  final files = {
    '$folder/Divecomputer-001': 'model "Other"\nkeyvalue "Serial" "00000001"\n',
    '$folder/Divecomputer': bare,
    '$folder/Dive-705': File('$_fixturesRoot/dives/$folder/Dive-705').readAsStringSync(),
  };
  final snap = RemoteSnapshot.fromFiles(files);
  final t = DateTime.utc(2026, 4, 4, 13, 30, 15).millisecondsSinceEpoch ~/ 1000;
  expect(snap.existingDivesBySerialAndStart.keys.single, (serial: 0xb89641e4, startTime: t));
});
```

- [ ] **Step 6: Run the snapshot tests to verify they fail**

Run: `flutter test test/sync/subsurface_git/remote_snapshot_test.dart`
Expected: compile error, `fromFiles` undefined.

- [ ] **Step 7: Rewrite `remote_snapshot.dart`**

Remove `dart:io` and `package:path` imports. Implement `fromFiles` per the Interfaces block, reusing the existing private helpers; iterate `filesByPath.keys.toList()..sort()` so the `Divecomputer-NNN` fallback is deterministic. Keep the class doc comment's tolerance paragraph, reworded for a map input.

- [ ] **Step 8: Point the orchestrator at the new seam**

`sync_orchestrator.dart`: `final snapshot = RemoteSnapshot.fromFiles(await readRemoteRepoFiles(repoDir));` plus `import 'remote_repo_reader.dart';`.

- [ ] **Step 9: Run everything**

Run: `flutter analyze && flutter test`
Expected: `No issues found!`, all pass, `sync_orchestrator_test.dart` unmodified.

- [ ] **Step 10: Commit**

```bash
git add lib/sync/subsurface_git test/sync/subsurface_git
git commit -m "refactor(subsurface): snapshot builder takes files by path; directory walk moves to the app"
```

---

### Task 6: Move the format layer, mappers, planner, snapshot, fixtures and tests

**Files:**
- Move: the Task 6 block of the file map
- Modify: `packages/subsurface_core/lib/subsurface_core.dart` (exports); app files the rewriter touches (`sync_orchestrator.dart`, `bootstrap_importer.dart`, `drift_sync_inputs.dart`, `remote_repo_reader.dart` if it imports the snapshot, `lib/ui/widgets/subsurface_sync_section.dart`, the six app-side tests under `test/sync/subsurface_git/`, `test/ui/widgets/subsurface_sync_section_test.dart`); `test/sync/subsurface_git/bootstrap_importer_test.dart:119` (fixture path)

**Interfaces:**
- Consumes: Tasks 3, 4, 5.
- Produces: `package:subsurface_core/sync/subsurface_git/{format/subsurface_format,format/subsurface_parser,format/subsurface_serializer,format/subsurface_unit_parsing,sync_inputs,mapper,sync_planner,remote_snapshot,subsurface_to_ccrlog_mapper}.dart`, identical contents to the app versions after Tasks 4 and 5.

- [ ] **Step 1: Move the libraries and fixtures**

```bash
mkdir -p packages/subsurface_core/lib/sync/subsurface_git packages/subsurface_core/test/sync/subsurface_git packages/subsurface_core/test/fixtures
git mv lib/sync/subsurface_git/format packages/subsurface_core/lib/sync/subsurface_git/format
git mv lib/sync/subsurface_git/sync_inputs.dart lib/sync/subsurface_git/mapper.dart lib/sync/subsurface_git/sync_planner.dart lib/sync/subsurface_git/remote_snapshot.dart lib/sync/subsurface_git/subsurface_to_ccrlog_mapper.dart packages/subsurface_core/lib/sync/subsurface_git/
git mv test/fixtures/subsurface test/fixtures/subsurface_incident_replica packages/subsurface_core/test/fixtures/
```

- [ ] **Step 2: Export them from the barrel**

Append nine `export 'sync/subsurface_git/…';` lines (the four `format/` files first, then `sync_inputs`, `mapper`, `sync_planner`, `remote_snapshot`, `subsurface_to_ccrlog_mapper`).

- [ ] **Step 3: Verify the package compiles and is pure**

Run: `cd packages/subsurface_core && dart analyze --fatal-infos && dart test`
Expected: `No issues found!`; purity and barrel tests pass. If the purity test names `remote_snapshot.dart`, Task 5 left an import behind.

- [ ] **Step 4: Move the seven tests**

```bash
git mv test/sync/subsurface_git/mapper_test.dart test/sync/subsurface_git/mapper_divemaster_test.dart test/sync/subsurface_git/sync_planner_test.dart test/sync/subsurface_git/remote_snapshot_test.dart test/sync/subsurface_git/subsurface_format_test.dart test/sync/subsurface_git/subsurface_to_ccrlog_mapper_test.dart test/sync/subsurface_git/subsurface_to_ccrlog_divemaster_test.dart packages/subsurface_core/test/sync/subsurface_git/
sed -i '' -e 's#package:ccrlogger/#package:subsurface_core/#g' -e 's#package:flutter_test/flutter_test.dart#package:test/test.dart#g' packages/subsurface_core/test/sync/subsurface_git/*.dart
```

`remote_snapshot_test.dart` uses `package:path` in test code; add `path: ^1.9.1` under `dev_dependencies` in the package pubspec (dev only; the purity test covers `lib/`, not `test/`). The `_fixturesRoot = 'test/fixtures/subsurface'` constants and the `test/fixtures/subsurface_incident_replica/Dive-697` literal in `sync_planner_test.dart` are now correct relative to the package directory, so they stay as they are.

- [ ] **Step 5: Run the package tests**

Run: `cd packages/subsurface_core && dart analyze --fatal-infos && dart test`
Expected: `No issues found!`; all tests pass, including every byte-exact round trip in `subsurface_format_test.dart` and the incident-replica abort in `sync_planner_test.dart`.

- [ ] **Step 6: Rewrite the app's imports and the one fixture path**

Run the rewriter: `dart <scratchpad>/rewrite_imports.dart .`

Then edit `test/sync/subsurface_git/bootstrap_importer_test.dart:119`: `const _fixturesRoot = 'packages/subsurface_core/test/fixtures/subsurface';` (that test copies fixture folders into a temp git repo and stays in the app because it drives `repo.dart`).

Run: `flutter analyze && flutter test`
Expected: `No issues found!`; all pass. Expect the rewriter to have touched: `sync_orchestrator.dart`, `bootstrap_importer.dart`, `drift_sync_inputs.dart`, `remote_repo_reader.dart` (if it imports `remote_snapshot.dart`), `lib/ui/widgets/subsurface_sync_section.dart`, `test/sync/subsurface_git/{bootstrap_importer,sync_orchestrator,dao_subsurface_sync_data_source,drift_sync_inputs,remote_repo_reader}_test.dart`, `test/ui/widgets/subsurface_sync_section_test.dart`. `git diff --stat` must show only import-line changes plus the fixture path.

- [ ] **Step 7: Commit**

```bash
git add -A lib test packages
git commit -m "refactor: move Subsurface format, mappers, planner and snapshot builder into subsurface_core"
```

---

### Task 7: Docs, full verification, hand-over

**Files:**
- Modify: `CLAUDE.md` (one bullet under "Working in this project"), `docs/subsurface_git_library.md` (no change: superseded in rollout step 5)

- [ ] **Step 1: Tell future readers where the code went**

Add to CLAUDE.md "Working in this project", after the "Pure-Dart Shearwater parser is sacred" bullet:

```markdown
- **`packages/subsurface_core` is pure Dart and shared with the server.** The Subsurface git format (parser, serializer), both mappers, the sync planner, the snapshot builder, the domain models (`Dive`, `SampleSet`, `DiveAnnotation`), the sample codec and the parser's data types (`constants`, `hardware`, `parsed_dive`, `dive_converter`) live there, laid out exactly as they were under the app's `lib/`. No Flutter, Drift, PowerSync or I/O imports; `packages/subsurface_core/test/purity_test.dart` enforces it. Mapper and planner take `SubsurfaceDiveInput` / `SubsurfaceCylinderInput` / `SubsurfaceDiveComputerInput`; the app builds those from Drift rows in `lib/sync/subsurface_git/drift_sync_inputs.dart`. Run its tests with `dart test` from that directory; CI does.
```

- [ ] **Step 2: Clean-tree verification, both sides**

```bash
cd packages/subsurface_core && rm -rf .dart_tool && dart pub get && dart analyze --fatal-infos && dart test --reporter expanded
```
Expected: `No issues found!`, every test passes: purity and barrel (2), annotation (3), the three codec tests, and the seven moved Subsurface tests including the new bare-`Divecomputer` case.

```bash
cd <repo root> && flutter clean && flutter pub get && flutter analyze && flutter test --reporter expanded && ./supabase/lint_migrations.sh
```
Expected: `No issues found!`, every test passes. `sync_orchestrator_test.dart`, `bootstrap_importer_test.dart`, `dao_subsurface_sync_data_source_test.dart`, `repo_test.dart`, `ssl_certs_test.dart`, `credentials_test.dart` show no diff from `main` except import lines and the one fixture path (`git diff main -- test/sync/subsurface_git/`).

- [ ] **Step 3: App behaviour unchanged, in the running app**

Build and run the macOS app (`flutter run -d macos`); open a dive's detail, the Equipment tab and Settings → Subsurface. The profile renders (sample codec), annotations edit and save (`Patch`), the Subsurface section shows the same state as before. Do **not** press "Push to Subsurface" against the real account; `sync_orchestrator_test.dart` covers the push path against a local bare remote. Report what was checked.

- [ ] **Step 4: Commit and open the PR**

```bash
git add CLAUDE.md
git commit -m "docs: point CLAUDE.md at packages/subsurface_core"
```

PR title: `refactor: split Subsurface format code into packages/subsurface_core (rollout step 1)`. Body: link the spec, list the file map, quote the "Where the spec and the code differ" section below, end with `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.

---

## Where the spec and the code differ

Found while writing this plan; each is settled above, listed here so the spec can be amended.

1. **`column_packer.dart` imports `dart:io`.** Spec §6 calls the sample codec "already pure Dart". It has no Flutter or Drift, but it uses `ZLibEncoder`/`ZLibDecoder` from `dart:io`, the SDK's only zlib. Replacing it would mean a new dependency (`archive`) or a hand-written inflate. Kept, allow-listed in the purity test, documented in the package README. The server runs on the Dart VM, where `dart:io` is available, so sharing is unaffected.
2. **`equipment.dart` is not needed by anything that moves.** Spec §6 lists it among the domain models to move. It holds `CylinderRole` constants and `SlotInUseException`, used only by DAOs and UI; the read mapper carries the raw `use="…"` string instead. It stays in the app. If the server later needs `CylinderRole`, move it then.
3. **Six of the thirteen tests in `test/sync/subsurface_git/` stay in the app.** Spec §6 says "the existing tests move with the code". The tests of `repo.dart`, `ssl_certs.dart`, `credentials.dart`, `sync_orchestrator.dart`, `bootstrap_importer.dart` and `dao_subsurface_sync_data_source.dart` test code that stays, so they stay. Likewise `test/data/sample_codec/sample_codec_test.dart` and `test/shearwater/parser/dive_converter_test.dart` stay: they drive the binary parser (`dive_parser.dart`, still in the app) over `test/fixtures/dives/*.bin`, which is also a Flutter asset.
4. **The Subsurface fixtures move into the package.** Spec §11 places the future anonymised corpus at `test/fixtures/subsurface/corpus/` (app root). Package tests run with the package directory as working directory, so the contract fixtures must live under `packages/subsurface_core/test/fixtures/`. Suggested amendment: `packages/subsurface_core/test/fixtures/subsurface/corpus/`. The corpus itself, and the anonymising script in `tool/`, are not part of this step.
5. **The Drift-row coupling is wider than `mapper.dart` and `sync_planner.dart`.** `CcrlogDiveBundle`, `AbortedDive`, the orchestrator's bundle loop, the Settings widget (`ab.dive.dcDiveNumber`) and five test files construct or read the rows. All covered in Task 4; the data-source seam (`SubsurfaceSyncDataSource`) deliberately keeps returning rows so the DAO adapter and its test are untouched.
6. **`remote_snapshot.dart` becomes a map-in builder, not a "directory walk injected" callback.** Spec §6 suggests injecting the walk. Passing `Map<String, String>` of path → text is simpler to test and lets the server later feed it from `git ls-tree` + `git cat-file` without a checkout. One deterministic tie-break is new: with no bare `Divecomputer`, the first `Divecomputer-NNN` in sorted path order is used instead of filesystem order.
7. **The root `flutter analyze` descends into nested packages**, so `packages/**` is excluded at the root and CI analyzes and tests the package with `dart` from its own directory (three extra steps in `check.yml`).
8. **Spec §7.5 notes `AbortReason.divecomputerProtected` is declared but never raised**, and §10 notes CLAUDE.md's "safety hold" paragraph is stale. Both are true; neither changes in this step (pure refactor; the CLAUDE.md fix is rollout step 5).
9. **Layout.** The spec does not prescribe one. The package mirrors the app's `lib/` paths so that `git mv` keeps history, intra-package relative imports need no edits, and every app import is a prefix swap. Flattening (`lib/format/`, `lib/mapping/`, …) can be done later in one rename commit once the server consumes the barrel.
