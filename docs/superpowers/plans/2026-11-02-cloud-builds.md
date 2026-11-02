# Cloud Builds Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every Anchorline build that reaches a user (store releases, hotfixes, nightlies) is built, signed and delivered by GitHub Actions instead of on Egbert's Mac.

**Architecture:** One workflow, `build.yml`, so that all runs share one `run_number` (the build counter). It calls reusable per-platform workflows. Versioning, release-tag rules, signing-expiry checks, TestFlight group assignment and website publishing are small stdlib-only Dart CLIs under `tool/`, with pure logic tested by `flutter test`. Desktop nightlies get their own app identity through one environment variable read by the native build files, and their own data folder via the Documents-folder work.

**Tech Stack:** GitHub Actions (hosted `macos-26`, `ubuntu-24.04`/`ubuntu-22.04`, `windows-2025`), Flutter 3.44.0, Dart CLIs (`dart:io` plus existing deps `http`, `crypto`), Xcode 26.6 (`xcodebuild`, `altool`, `notarytool`), Gradle (existing), Inno Setup 6, appimagetool, AWS CLI against Cloudflare R2, `gh`.

**Spec:** `docs/superpowers/specs/2026-11-02-cloud-builds-design.md`. It lives on branch `spec/cloud-builds` until merged; read it first. The website spec `docs/superpowers/specs/2026-10-07-website-design.md` defines the bucket, the manifest and the publish command that Task 6 builds.

## Global Constraints

- Everything in git is written in English: code, comments, commit messages, PR texts, docs.
- Project flow: one GitHub issue per PR, then a branch, a PR and a squash-merge. Label each issue with a priority P0–P3.
- Never print a secret. Check presence with `${VAR:+SET}` only, never `${VAR:-…}`. Decode base64 secrets into `$RUNNER_TEMP`, never into the repo.
- Don't run `dart format` on whole existing files. Match the surrounding style by hand. New files may be formatted.
- No new pub dependencies. The tool scripts use `dart:io`, `dart:convert` and the existing `http` and `crypto` packages.
- Flutter **3.44.0**, pinned in exactly one place, which both `check.yml` and `build.yml` read.
- Runners are pinned:
  - `macos-26` with Xcode **26.6** (`/Applications/Xcode_26.6.app`; must be ≥ 26.1);
  - `ubuntu-24.04` for Android and the Linux-only jobs;
  - Linux app builds on the oldest Ubuntu LTS image GitHub still offers (`ubuntu-22.04` if listed, else `ubuntu-24.04`);
  - `windows-2025`.
- JDK: Temurin **21** via `actions/setup-java` on Android, Windows and Linux.
- Build number = `BUILD_NUMBER_BASE` (repository variable, initially **100**) + `github.run_number` of `build.yml`. Never rename `build.yml`.
- Release tags match `^v(\d+)\.(\d+)\.(\d+)$` and must be annotated:
  - `vX.Y.0` must be on `main`;
  - `vX.Y.Z` with Z > 0 must be on `release/X.Y`;
  - tags never move or get reused.
- Nightly version = the highest valid release tag with its middle digit +1 and its last digit 0. With no tags: `0.1.0`.
- `--dart-define`s that CI passes:
  - `BUILD_CHANNEL` = `release` | `nightly`; local builds default to `dev`;
  - `DISTRIBUTION_CHANNEL` = `app_store` | `play_store` | `website`;
  - `APP_VERSION`, `APP_BUILD`.
- Desktop nightly identity: id `nl.despaankamer.ccrlogger.nightly`, display name `Anchorline Nightly`. The release id stays `nl.despaankamer.ccrlogger`, display name `Anchorline`.
- Bucket layout:
  - `releases/manifest.json` and `nightly/manifest.json`, both format `1`;
  - platform keys `windows-x64`, `linux-x64`, `macos`;
  - nightlies kept **14 days**.
- File names:
  - release: `Anchorline-<V>-windows-x64.exe`, `Anchorline-<V>-linux-x64.AppImage`;
  - nightly: `Anchorline-Nightly-<V>-<N>-<platform>.<ext>`.
- Third-party actions pinned to full commit SHAs. Each job declares least-privilege `permissions`.
- No workflow uses `pull_request_target`. `check.yml` and anything a pull request triggers never read secrets.
- Workflow artifacts kept 2 days (`retention-days: 2`).

## Review Focus

1. **"Re-run all jobs" after a partial delivery** re-uploads a build number Apple or Google already has. Expected: the duplicate is reported as a warning and the job passes, rather than failing the release. Pinned in Task 16, `classifyAltoolOutput`.
2. **A tag pushed for a version that's already published** (in the releases manifest or as a GitHub Release). Expected: the run stops in prepare before building. Pinned in Task 1, `planRelease` with `publishedVersions`.
3. **A desktop nightly's first start while the release app's data still sits in Documents.** Expected: the nightly never moves or opens the release's files. Pinned by PR #136's tests (`appDataLocationFor(..., nightly: true)` returns `movesFromDocuments == false`) and by Task 17's machine check.
4. **Apple processing never finishes, or ends `INVALID`.** Expected: the TestFlight step fails with a clear message within its timeout and doesn't hang. Pinned in Task 15, `waitForProcessedBuild`.
5. **A publish interrupted after some files were uploaded.** Expected: a re-run completes. Files of an unlisted version may be overwritten, and the manifest is still written last. Pinned in Task 6, publish orchestration tests.

---

## Phase A: build info and versioning (PR 1, spec rollout step 1)

### Task 1: Version rules

**Files:**
- Create: `tool/ci/lib/version_rules.dart`
- Test: `test/tool/ci/version_rules_test.dart` (import with a relative path: `../../../tool/ci/lib/version_rules.dart`)

**Interfaces:**
- Produces:
  - `class SemVer implements Comparable<SemVer> { final int major, minor, patch; static SemVer? parseTag(String tag); String get name; /* "1.2.0" */ }`
  - `enum Channel { release, nightly, dryRun }`
  - `class TagFacts { final String name; final bool annotated; final bool onMain; final bool onReleaseBranch; }`. `onReleaseBranch` means the tagged commit is on `origin/release/X.Y` for the tag's own X.Y.
  - `class BuildPlan { final Channel channel; final String version; final int buildNumber; final bool build; final String reason; }`
  - `class VersionRuleError implements Exception { final String message; }`
  - `int buildNumberFor(int base, int runNumber)`
  - `SemVer nextNightlyVersion(Iterable<String> tags)`
  - `BuildPlan planRelease({required TagFacts tag, required Iterable<String> allTags, required Set<String> publishedVersions, required int base, required int runNumber})`
  - `BuildPlan planNightly({required Iterable<String> allTags, required int base, required int runNumber, required bool scheduled, required String headSha, String? lastDeliveredSha})`
  - `BuildPlan planDryRun({required Iterable<String> allTags, required int base, required int runNumber})`

- [ ] **Step 1: Write the failing tests**

```dart
test('nightly version is the next minor of the highest tag', () {
  expect(nextNightlyVersion(['v1.1.0']).name, '1.2.0');
  expect(nextNightlyVersion(['v1.1.0', 'v1.2.0', 'v1.2.1']).name, '1.3.0');
  expect(nextNightlyVersion(['v1.2.0', 'v1.2.3', 'v1.10.0', 'v1.9.0']).name, '1.11.0');
  expect(nextNightlyVersion(['v1.4', 'v2.0.0-beta', 'release-1', 'v1.1.0']).name, '1.2.0');
  expect(nextNightlyVersion(<String>[]).name, '0.1.0');
});
test('build number is base plus run number', () => expect(buildNumberFor(100, 57), 157));
test('minor release on main', () {
  final p = planRelease(tag: TagFacts('v1.2.0', annotated: true, onMain: true, onReleaseBranch: false),
      allTags: ['v1.1.0', 'v1.2.0'], publishedVersions: {'1.1.0'}, base: 100, runNumber: 54);
  expect((p.channel, p.version, p.buildNumber, p.build), (Channel.release, '1.2.0', 154, true));
});
test('hotfix on its release branch', () {
  final p = planRelease(tag: TagFacts('v1.2.1', annotated: true, onMain: false, onReleaseBranch: true),
      allTags: ['v1.2.0', 'v1.2.1'], publishedVersions: {'1.2.0'}, base: 100, runNumber: 58);
  expect(p.version, '1.2.1');
});
test('release tag errors', () {
  void bad(TagFacts t, String msg, {Set<String> published = const {}}) => expect(
      () => planRelease(tag: t, allTags: [t.name], publishedVersions: published, base: 100, runNumber: 1),
      throwsA(isA<VersionRuleError>().having((e) => e.message, 'message', contains(msg))));
  bad(TagFacts('v1.2', annotated: true, onMain: true, onReleaseBranch: false), 'vX.Y.Z');
  bad(TagFacts('v1.2.0', annotated: false, onMain: true, onReleaseBranch: false), 'annotated');
  bad(TagFacts('v1.2.0', annotated: true, onMain: false, onReleaseBranch: false), 'must be on main');
  bad(TagFacts('v1.2.1', annotated: true, onMain: true, onReleaseBranch: false), 'release/1.2');
  bad(TagFacts('v1.2.0', annotated: true, onMain: true, onReleaseBranch: false), 'already released',
      published: {'1.2.0'});
});
test('scheduled nightly skips when main is unchanged; button always builds', () {
  final skip = planNightly(allTags: ['v1.2.0'], base: 100, runNumber: 60, scheduled: true,
      headSha: 'abc', lastDeliveredSha: 'abc');
  expect((skip.build, skip.reason), (false, contains('unchanged')));
  final run = planNightly(allTags: ['v1.2.0'], base: 100, runNumber: 61, scheduled: false,
      headSha: 'abc', lastDeliveredSha: 'abc');
  expect((run.build, run.version, run.buildNumber), (true, '1.3.0', 161));
});
test('dry run carries the nightly version', () {
  expect(planDryRun(allTags: ['v1.2.0'], base: 100, runNumber: 9).version, '1.3.0');
});
```

`TagFacts` uses a positional name and named booleans, as above.

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `flutter test test/tool/ci/version_rules_test.dart`
Expected: FAIL, because the import doesn't resolve.

- [ ] **Step 3: Implement `tool/ci/lib/version_rules.dart` with the interfaces above**

Comparison is numeric per component. Invalid tag names are ignored when looking for the highest version. `planRelease` checks in this order: shape, annotated, branch, already published.

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `flutter test test/tool/ci/version_rules_test.dart`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add tool/ci/lib/version_rules.dart test/tool/ci/version_rules_test.dart
git commit -m "feat(ci): version and release-tag rules for cloud builds"
```

### Task 2: Version CLI

**Files:**
- Create: `tool/ci/version.dart`
- Test: `test/tool/ci/version_cli_test.dart`

**Interfaces:**
- Consumes: Task 1, all of it.
- Produces: the command `dart tool/ci/version.dart` with these flags:
  - `--event <push|schedule|workflow_dispatch>`
  - `--ref <github.ref>`
  - `--run-number <n>`
  - `--base <n>`
  - `[--dry-run]`
  - `[--last-delivered-sha <sha>]`
  - `[--published <comma-separated versions>]`
  - `[--notes-out <path>]`

  It prints and appends to `$GITHUB_OUTPUT` (when set) the lines `channel=release|nightly|dry-run`, `version=…`, `build_number=…`, `build=true|false`, `reason=…`. It exits 1 with a line `::error::<message>` on a `VersionRuleError`.

  Run it as `dart <file>`, not `dart run <file>`: `dart run` runs the package's build hooks and writes to stdout.

  `--notes-out` writes the release notes:
  - for a release, the annotated tag's message (`git tag -l --format='%(contents:body)'` plus its subject), with any signature block removed;
  - for a nightly or dry run, the subjects of `git log --format=%s <last-delivered-sha>..HEAD`, or of the last 20 commits when there's no SHA.

- Git facts it gathers:
  - tags: `git tag --list 'v*'`;
  - annotated: `git cat-file -t <tag>` is `tag`;
  - on `main`: `git merge-base --is-ancestor <tag>^{commit} origin/main`;
  - on the release branch: the same against `origin/release/X.Y`, where a missing ref means `false`;
  - head: `git rev-parse HEAD`.
- `--event push` with `refs/tags/…` → release. `schedule` → nightly with `scheduled: true`. `workflow_dispatch` → nightly with `scheduled: false`, or a dry run when `--dry-run` is given or the ref isn't `refs/heads/main`.

- [ ] **Step 1: Write the failing integration test**

The test builds a temporary repository: `git init`, three commits on `main`, then `git update-ref refs/remotes/origin/main HEAD`. It adds an annotated tag `v1.1.0` on the first commit with message `v1.1.0 — first`, and a lightweight tag `v1.1.9`. On a side commit it creates `refs/remotes/origin/release/1.1`, with the annotated tag `v1.1.1` on that commit. It runs the CLI with `Process.run('dart', ['run', '<abs repo root>/tool/ci/version.dart', ...], workingDirectory: tmp)`.

```dart
test('push of an annotated tag on main → release outputs', () async {
  final r = await runCli(['--event', 'push', '--ref', 'refs/tags/v1.1.0', '--run-number', '5', '--base', '100',
      '--notes-out', notesPath]);
  expect(r.exitCode, 0);
  expect(r.stdout, allOf(contains('channel=release'), contains('version=1.1.0'), contains('build_number=105')));
  expect(File(notesPath).readAsStringSync(), contains('first'));
});
test('lightweight tag → exit 1 with ::error::', () async {
  final r = await runCli(['--event', 'push', '--ref', 'refs/tags/v1.1.9', '--run-number', '6', '--base', '100']);
  expect((r.exitCode, r.stdout), (1, contains('::error::')));
});
test('hotfix tag on origin/release/1.1 → release 1.1.1', () async { /* expect version=1.1.1 */ });
test('dispatch from a non-main branch → dry-run', () async { /* --ref refs/heads/feature → channel=dry-run */ });
test('schedule with last-delivered == HEAD → build=false', () async { /* … */ });
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `flutter test test/tool/ci/version_cli_test.dart`
Expected: FAIL, because `tool/ci/version.dart` doesn't exist.

- [ ] **Step 3: Implement `tool/ci/version.dart`**

Keep it thin: gather the facts, call the rules, write the outputs. Use `Process.run('git', …)` in the current directory.

- [ ] **Step 4: Run it and confirm it passes**

Run: `flutter test test/tool/ci/`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add tool/ci/version.dart test/tool/ci/version_cli_test.dart
git commit -m "feat(ci): version CLI that reads git facts and writes job outputs"
```

### Task 3: Build info in the app, Sentry release and environment, version label

**Files:**
- Create: `lib/build_info.dart`
- Modify: `lib/main.dart`, the `SentryFlutter.init` options (around lines 126–160)
- Modify: `lib/ui/screens/settings_screen.dart`, appending one `ListTile` at the end of the settings list
- Test: `test/build_info_test.dart`, plus one case in the existing settings screen test if there is one

**Interfaces:**
- Produces:
  - `class BuildInfo` with:
    - `static const channel = String.fromEnvironment('BUILD_CHANNEL', defaultValue: 'dev')`
    - `static const distribution = String.fromEnvironment('DISTRIBUTION_CHANNEL', defaultValue: 'none')`
    - `static const version = String.fromEnvironment('APP_VERSION')`
    - `static const build = String.fromEnvironment('APP_BUILD')`
    - `static bool get isNightly`
    - `static String get label`
    - `static String? get sentryRelease`
  - Top-level pure functions `String buildLabel({required String channel, required String version, required String build})` and `String? sentryReleaseName({required String version, required String build})`.

- [ ] **Step 1: Write the failing tests**

```dart
expect(buildLabel(channel: 'release', version: '1.2.0', build: '154'), 'Anchorline 1.2.0 (154)');
expect(buildLabel(channel: 'nightly', version: '1.3.0', build: '157'), 'Anchorline Nightly 1.3.0 (157)');
expect(buildLabel(channel: 'dev', version: '', build: ''), 'Development build');
expect(buildLabel(channel: 'nightly', version: '', build: ''), 'Development build');
expect(sentryReleaseName(version: '1.2.0', build: '154'), 'nl.despaankamer.ccrlogger@1.2.0+154');
expect(sentryReleaseName(version: '', build: ''), isNull);
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `flutter test test/build_info_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement `lib/build_info.dart` and wire it in**

- In `SentryFlutter.init`, set `options.environment = BuildInfo.channel`. Set `options.release` when `BuildInfo.sentryRelease` is non-null.
- In Settings, add a last, non-interactive `ListTile(title: Text('Version'), subtitle: Text(BuildInfo.label))`.

- [ ] **Step 4: Run the tests and analysis**

Run: `flutter analyze && flutter test`
Expected: no analyzer issues; all tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/build_info.dart lib/main.dart lib/ui/screens/settings_screen.dart test/build_info_test.dart
git commit -m "feat(app): build channel, version label and Sentry environment from CI defines"
```

### Task 4: Desktop app identity switch

**Files:**
- Modify: `linux/CMakeLists.txt`:
  - `BINARY_NAME` becomes `"anchorline"`;
  - `APPLICATION_ID` becomes `"nl.despaankamer.ccrlogger"`;
  - add the channel switch.
- Modify: `linux/runner/my_application.cc`, lines 48 and 52: replace the literal `"Anchorline"` with `APP_DISPLAY_NAME`.
- Modify: `windows/CMakeLists.txt` and `windows/runner/CMakeLists.txt`: add the channel switch and pass `APP_DISPLAY_NAME` to the compiler and the resource compiler.
- Modify: `windows/runner/main.cpp`, line 30: use `APP_DISPLAY_NAME`.
- Modify: `windows/runner/Runner.rc`: use `APP_DISPLAY_NAME` for `FileDescription` and `ProductName`.
- Modify: `windows/installer/anchorline.iss`:
  - add a `Channel` define (default `release`), a `MyAppBuild` define, nightly values, and output names that follow the spec.
  - Don't touch its data-location comment: the Documents-folder PR owns it.

**Interfaces:**
- Produces:
  - The environment variable `ANCHORLINE_CHANNEL=nightly`, set when running `flutter build linux|windows`, switches the identity. Unset (or empty) and `release` mean release, `nightly` means nightly, and any other value stops the configure step with an error, so a typo can't silently build the release identity.
  - Inno defines: `/DMyAppVersion=<V> /DMyAppBuild=<N> /DChannel=<release|nightly>`.
- Values:

| | Release | Nightly |
|---|---|---|
| Linux `APPLICATION_ID` | `nl.despaankamer.ccrlogger` | `nl.despaankamer.ccrlogger.nightly` |
| `APP_DISPLAY_NAME` | `Anchorline` | `Anchorline Nightly` |
| Inno `AppId` | unchanged `{{8C5A1F90-2B4E-4A6A-9D3F-7B1C2E8A0F65}` | `{{077F972D-571A-4826-A633-D89426861B47}` |
| Inno `AppName`, install folder | `Anchorline` | `Anchorline Nightly` |
| Inno `OutputBaseFilename` | `Anchorline-{#MyAppVersion}-windows-x64` | `Anchorline-Nightly-{#MyAppVersion}-{#MyAppBuild}-windows-x64` |
| Inno `VersionInfoVersion` | `{#MyAppVersion}.{#MyAppBuild}` | same |

- [ ] **Step 1: Make the edits above.** `CompanyName` stays `De Spaankamer`; Windows' application-support path is `%APPDATA%\De Spaankamer\<ProductName>`.
- [ ] **Step 2: Verify locally where possible**

Run: `flutter analyze && flutter test`
Expected: unchanged and green.

Real verification of the Linux and Windows output happens in the Task 14 dry run, which checks the window title, the installed program name and the support folder.

- [ ] **Step 3: Commit, then open PR 1 for Tasks 1–4**

```bash
git add linux windows
git commit -m "build(desktop): Linux app id fix and a nightly identity switch for Linux, Windows and the installer"
```

---

## Phase B: publish command (PR 2)

### Task 5: Manifest logic

**Files:**
- Create: `tool/publish/lib/manifest.dart`
- Test: `test/tool/publish/manifest_test.dart`

**Interfaces:**
- Produces:
  - `class FileEntry { final String url; final int size; final String sha256; }`
  - `class ReleaseEntry { final String version; final int build; final String date; /* YYYY-MM-DD */ final String notes; final Map<String, FileEntry> files; }`
  - `class Manifest { final ReleaseEntry? latest; final List<ReleaseEntry> previous; static Manifest empty(); static Manifest parse(String json); String encode(); }`. `parse` throws `PublishError` when `format != 1`. Unknown keys under `files` survive a round trip.
  - `enum Lane { releases, nightly }`
  - `Manifest addRelease(Manifest m, ReleaseEntry e, {bool force = false})`
  - `Manifest addNightly(Manifest m, ReleaseEntry e, {required DateTime now, Duration keep = const Duration(days: 14)})`
  - `Manifest rollback(Manifest m, String toVersion)`
  - `String objectKey({required Lane lane, required String version, required int build, required String platformKey, required String extension})`
  - `class PublishError implements Exception { final String message; }`

- [ ] **Step 1: Write the failing tests**

```dart
expect(objectKey(lane: Lane.releases, version: '1.2.0', build: 154, platformKey: 'windows-x64', extension: 'exe'),
    'releases/1.2.0/Anchorline-1.2.0-windows-x64.exe');
expect(objectKey(lane: Lane.nightly, version: '1.3.0', build: 157, platformKey: 'linux-x64', extension: 'AppImage'),
    'nightly/1.3.0-157/Anchorline-Nightly-1.3.0-157-linux-x64.AppImage');
// addRelease: empty → latest set, previous empty; second → previous == [old]
// addRelease of a version present in latest or previous → PublishError('already published'); force → replaced in place
// addNightly with the same build twice → PublishError
// addNightly prunes: now = 2026-11-20; previous dated 2026-11-05 dropped, 2026-11-06 kept (keep if date >= now - 14 days)
// rollback('1.1.0'): latest becomes 1.1.0, the old latest is first in previous, no entry lost; unknown version → PublishError
// parse('{"format":2}') → PublishError; encode(parse(x)) keeps an unknown files key "macos-universal"
```

Write each commented case as its own `test(...)` with these exact values.

- [ ] **Step 2: Run them and confirm they fail.** Run: `flutter test test/tool/publish/manifest_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement `tool/publish/lib/manifest.dart`.** Entries are immutable. Every operation returns a new `Manifest`.
- [ ] **Step 4: Run them and confirm they pass.** Run: `flutter test test/tool/publish/`. Expected: PASS.
- [ ] **Step 5: Commit**

```bash
git add tool/publish/lib/manifest.dart test/tool/publish/manifest_test.dart
git commit -m "feat(publish): releases and nightly manifest logic (format 1)"
```

### Task 6: Publish CLI and website spec amendments

**Files:**
- Create: `tool/publish/lib/bucket.dart`, `tool/publish/lib/publisher.dart`, `tool/publish/publish.dart`
- Test: `test/tool/publish/publisher_test.dart`
- Modify: `docs/superpowers/specs/2026-10-07-website-design.md`, the sections "Published content" and "Security"

**Interfaces:**
- Consumes: Task 5.
- Produces:
  - `abstract class Bucket` with:
    - `Future<String?> getText(String key)`
    - `Future<void> putFile(String key, String path, {required String contentType})`
    - `Future<void> putText(String key, String text, {required String contentType, String? cacheControl})`
    - `Future<String?> sha256Of(String key)`, which downloads the object and hashes it; `null` if absent.
  - `class AwsCliBucket implements Bucket`. It shells out to `aws s3 cp` and `aws s3api` with `--endpoint-url https://$R2_ACCOUNT_ID.r2.cloudflarestorage.com`, bucket `$R2_BUCKET`, and credentials from `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`, which CI maps from the R2 secrets.
  - `class Publisher { Publisher(Bucket b, {required String baseUrl, required DateTime Function() now, bool dryRun = false}); Future<Manifest> publish({required Lane lane, required String version, required int build, required String notes, required Map<String, String> files /* platformKey → local path */, bool force = false}); Future<Manifest> rollback(String toVersion); }`
  - The CLI: `dart tool/publish/publish.dart <release|nightly|rollback> --version V [--build N] [--notes-file F] [--file windows-x64=PATH ...] [--dry-run] [--force]`. The base URL comes from `DOWNLOADS_BASE_URL`. Content types:
    - `.exe` → `application/vnd.microsoft.portable-executable`
    - `.AppImage` → `application/vnd.appimage`
    - `.dmg` → `application/x-apple-diskimage`
    - manifest → `application/json` with `Cache-Control: no-cache`

- [ ] **Step 1: Write the failing tests against a `FakeBucket`** (in the test file; it records the order of calls)

```dart
// publish(lane: releases, …): every putFile happens before the single putText('releases/manifest.json')
// a refused version (already in the manifest): no put of any kind
// verification: FakeBucket.sha256Of returns a different hash for one file → PublishError, manifest NOT written
// interrupted re-run: objects for 1.2.0 already exist but 1.2.0 isn't in the manifest → overwritten, manifest written
// dryRun: no put calls; returns the manifest that would be written
// rollback: only the manifest is written
// nightly lane writes nightly/manifest.json, and entry urls start with '$baseUrl/nightly/1.3.0-157/'
```

- [ ] **Step 2: Run them and confirm they fail.** Run: `flutter test test/tool/publish/publisher_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement the bucket, the publisher and the CLI.** Order: read the manifest (absent means empty) → refuse early → upload the files → verify each sha256 → write the manifest.
- [ ] **Step 4: Run the tests and analysis.** Run: `flutter analyze && flutter test`. Expected: green.
- [ ] **Step 5: Amend the website spec**
  - "Only the owner's machine" becomes "only the build pipeline, with a bucket-scoped R2 key".
  - Add `nightly/manifest.json`, the 14-day retention, the `macos` key and the `rollback` action.
  - Note that the command lives at `tool/publish/` and uses the AWS CLI against R2. That replaces the earlier `wrangler` idea, because the AWS CLI is preinstalled on GitHub's runners.
- [ ] **Step 6: Commit, then open PR 2 for Tasks 5–6**

```bash
git add tool/publish test/tool/publish docs/superpowers/specs/2026-10-07-website-design.md
git commit -m "feat(publish): publish command for the downloads bucket (releases, nightly, rollback)"
```

---

## Phase C: accounts and secrets (Egbert, spec rollout step 2)

### Task 7: Set up accounts, secrets and variables

Egbert does this; an agent can't. Nothing is printed, and each secret goes in with `gh secret set NAME < file` or `base64 -i FILE | gh secret set NAME`.

- [ ] **Step 1: Look up the starting build number.**
  - Find the highest build number already used in Play Console (all tracks) and in App Store Connect (iOS and macOS).
  - Set the variable `BUILD_NUMBER_BASE` so that `BUILD_NUMBER_BASE + 1` is above all of them. 100 works if nothing is above 100.
- [ ] **Step 2: App Store Connect.**
  - Create a **Team** API key with the App Manager role.
  - Note the numeric app ids of the iOS and macOS app records.
  - Create the internal TestFlight group `Nightly` with **automatic distribution off**, add yourself, and note its id. The id is the last part of the group's URL, or comes from `GET /v1/betaGroups`.
- [ ] **Step 3: Apple developer portal.**
  - Register the App ID `nl.despaankamer.ccrlogger.nightly` with the same capabilities as the release macOS App ID.
  - Create a **Developer ID** provisioning profile for it.
  - Export Apple Distribution, Mac Installer Distribution and Developer ID Application, each as a `.p12` with a password.
- [ ] **Step 4: Google Play.**
  - Create a service account in Google Cloud and invite it in Play Console with release rights on Anchorline only. Download its JSON key.
  - Check whether the account has production access. If not, note the closed-testing track name to use instead.
  - Note the upload certificate's SHA-256: `keytool -list -v -keystore android/upload-keystore.jks -alias upload`.
- [ ] **Step 5: Cloudflare R2.**
  - Use or create the bucket `anchorline-downloads`, with public access, in the default (automatic) location and jurisdiction, not the EU jurisdiction: the publish command's endpoint is `https://<R2_ACCOUNT_ID>.r2.cloudflarestorage.com`, and a bucket in the EU jurisdiction is not served there (it has its own `.eu.` endpoint).
  - Add a lifecycle rule that deletes objects under `nightly/` after 15 days.
  - Create an R2 API token with Object Read & Write on that bucket only, and note its S3 access key pair.
- [ ] **Step 6: GitHub secrets**

| Secret | Content |
|---|---|
| `ASC_KEY_ID`, `ASC_ISSUER_ID` | API key id and issuer |
| `ASC_KEY_P8_BASE64` | base64 of `AuthKey_<id>.p8` |
| `APPLE_DISTRIBUTION_P12_BASE64` / `_PASSWORD` | Apple Distribution |
| `MAC_INSTALLER_P12_BASE64` / `_PASSWORD` | Mac Installer Distribution |
| `DEVELOPER_ID_P12_BASE64` / `_PASSWORD` | Developer ID Application |
| `PROFILE_MACOS_DEVID_NIGHTLY_BASE64` | Developer ID profile for the nightly id |
| `PROFILE_IOS_APPSTORE_BASE64`, `PROFILE_MACOS_APPSTORE_BASE64` | **Only if Task 12 or 13 falls back to manual signing** |
| `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_PASSWORD`, `ANDROID_KEY_ALIAS` | Existing upload keystore (alias `upload`) |
| `PLAY_SERVICE_ACCOUNT_JSON` | Service-account JSON |
| `SENTRY_AUTH_TOKEN` | The token in `macos/scripts/sentry.env.local` |
| `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY` | R2 S3 key pair |

- [ ] **Step 7: GitHub variables**

| Variable | Value |
|---|---|
| `BUILD_NUMBER_BASE` | from Step 1 |
| `NIGHTLY_SCHEDULE` | `off` |
| `DESKTOP_NIGHTLIES` | `off` (Task 17 turns it on) |
| `APPLE_TEAM_ID` | `U8945M3R9X` |
| `ASC_APP_ID_IOS`, `ASC_APP_ID_MACOS` | from Step 2 |
| `TESTFLIGHT_NIGHTLY_GROUP_ID` | from Step 2 |
| `PLAY_PACKAGE_NAME` | `nl.despaankamer.ccrlogger` |
| `PLAY_RELEASE_TRACK` | `production`, or the closed track from Step 4 |
| `ANDROID_UPLOAD_CERT_SHA256` | from Step 4 |
| `R2_ACCOUNT_ID`, `R2_BUCKET` (`anchorline-downloads`), `DOWNLOADS_BASE_URL` | from Step 5 |

- [ ] **Step 8: Confirm the names, without values:** `gh secret list && gh variable list`. Expected: every name above is present.
- [ ] **Step 9: Make sure nothing is billed while the repo is private.** Either keep no payment method on the GitHub account, or set an Actions budget of $0 with "stop usage when the budget is reached". GitHub then stops runs once the included amount ($12 a month on Free, $18 on Pro) is used, instead of charging.

---

## Phase D: build workflow, dry run (PR 3, spec rollout step 3)

Every platform job:
- receives `version`, `build_number`, `channel` and `simulate` from prepare;
- passes `--build-name`, `--build-number` and the four `--dart-define`s from the Global Constraints, with `BUILD_CHANNEL=<simulate>`, so a dry run is labelled as the packaging it simulates;
- uploads its output as a workflow artifact named `<platform>-<channel>` with `retention-days: 2`;
- has a `timeout-minutes` (Apple 60, others 45).

In this phase nothing is uploaded to a store or the bucket.

**Mac minutes are the budget while the repo is private.** About 190 a month are included on GitHub Free, enough for roughly four full iOS+macOS dry runs.
- Iterate on `tool/ci/apple_setup.sh`, the `xcodebuild` commands and `make_dmg.sh` on Egbert's Mac first, with a throwaway keychain. Spend runner minutes only to confirm.
- Dry-run single platforms (`-f platforms=…`) rather than `all`.
- Linux, Android and Windows runs cost little: about $0.35 together.

When signing secrets are absent (forks, or branch dry runs after Task 20), a job builds **unsigned** and says so in its summary:
- iOS: `--no-codesign`;
- Android: debug signing, which happens automatically when `key.properties` is absent;
- macOS: skip export and notarisation.

### Task 8: Shared setup, the prepare stage and the signing-expiry check

**Files:**
- Create:
  - `.github/actions/setup-flutter/action.yml`: composite action, Flutter `3.44.0` via `subosito/flutter-action` (SHA-pinned) with cache, then `flutter pub get`
  - `.github/actions/analyze-test/action.yml`: `flutter analyze`, `flutter test --reporter expanded`, `./supabase/lint_migrations.sh`
  - `.github/workflows/build.yml`
  - `.github/dependabot.yml`: the `github-actions` ecosystem, weekly
  - `tool/ci/lib/signing_expiry.dart`, `tool/ci/signing_expiry.dart`
- Test: `test/tool/ci/signing_expiry_test.dart`
- Modify: `.github/workflows/check.yml`, to use the two composite actions with the same behaviour as today

**Interfaces:**
- Consumes: Task 2's CLI.
- Produces:
  - `build.yml` triggers:
    - `push: tags: ['v*']`;
    - `schedule: - cron: '0 2 * * *'`;
    - `workflow_dispatch` with inputs `platforms` (choice: `all`, `ios`, `android`, `macos`, `windows`, `linux`; default `all`), `dry_run` (boolean, default false) and `simulate` (choice: `nightly`, `release`; only used in dry runs to exercise the release packaging).
  - `run-name`:
    - `Release ${{ github.ref_name }}` for tags;
    - `Nightly main` for a schedule or a dispatch on `main` without `dry_run`;
    - otherwise `Dry run ${{ github.ref_name }}`.

    (`run-name` may use only the `github` and `inputs` contexts.)
  - `concurrency: group: build-${{ github.ref }}`, `cancel-in-progress: false`.
  - Job `prepare` (`ubuntu-24.04`):
    - checks out with `fetch-depth: 0`;
    - exits early, without failing, for a scheduled run when `vars.NIGHTLY_SCHEDULE != 'on'`;
    - gets the last delivered nightly SHA with `gh run list --workflow build.yml --branch main --status success --json displayTitle,headSha` and the first `displayTitle == 'Nightly main'`;
    - gets the published versions from `gh release list --json tagName` plus the releases manifest's versions (from `DOWNLOADS_BASE_URL`; skipped if unreachable);
    - runs Task 2's CLI with `--notes-out notes.md`;
    - uploads `notes.md` as artifact `release-notes`;
    - runs the signing-expiry check when `ASC_KEY_ID` is set;
    - runs `./.github/actions/analyze-test`.

    Its outputs are `channel`, `version`, `build_number`, `build`, `platforms`, and `simulate`, the effective packaging channel (`release` or `nightly`). For real release and nightly runs, `simulate` equals `channel`; only dry runs take it from the input.
  - `tool/ci/lib/signing_expiry.dart`:
    - `enum Severity { warn, error }`
    - `class Finding { final String name; final DateTime notAfter; final Severity severity; }`
    - `List<Finding> checkExpiry(Map<String, DateTime> notAfter, DateTime now, {Duration warnWithin = const Duration(days: 30)})`
  - The CLI reads the `*_P12_BASE64`/`*_PASSWORD` and `PROFILE_*_BASE64` env vars that are present.
    - Certificate dates: `openssl pkcs12 -nokeys -passin env:… [-legacy]`, then `openssl x509 -noout -enddate`. Retry with `-legacy` on failure.
    - Profile dates: `openssl smime -inform der -verify -noverify`, then the plist's `ExpirationDate`.
    - It prints `::warning::` for each warn and `::error::` for each error, and exits 1 if there's any error.

- [ ] **Step 1: Write the failing expiry tests**

```dart
final now = DateTime.utc(2026, 11, 2);
expect(checkExpiry({'Apple Distribution': DateTime.utc(2026, 12, 17)}, now), isEmpty);          // 45 days
expect(checkExpiry({'Apple Distribution': DateTime.utc(2026, 11, 22)}, now).single.severity, Severity.warn); // 20 days
expect(checkExpiry({'Apple Distribution': DateTime.utc(2026, 12, 2)}, now).single.severity, Severity.warn);  // exactly 30
expect(checkExpiry({'Developer ID': DateTime.utc(2026, 11, 1)}, now).single.severity, Severity.error);      // expired
```

- [ ] **Step 2: Run them and confirm they fail.** Run: `flutter test test/tool/ci/signing_expiry_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement the expiry logic and CLI, the composite actions, `build.yml` with only `prepare`, `dependabot.yml`, and the `check.yml` refactor.**
- [ ] **Step 4: Verify.**
  - Run `flutter analyze && flutter test`: green.
  - Push the branch: `check.yml` stays green on the PR.
  - Run `gh workflow run build.yml --ref <branch> -f dry_run=true`: `prepare` succeeds, with outputs `channel=dry-run` and `version=1.2.0`.
- [ ] **Step 5: Commit**

```bash
git add .github tool/ci test/tool/ci
git commit -m "ci: build workflow skeleton with prepare stage, shared Flutter setup and signing-expiry check"
```

### Task 9: Android job

**Files:**
- Create: `.github/workflows/_android.yml` (reusable, `workflow_call`)
- Modify: `.github/workflows/build.yml`, to call it when `platforms` is `all` or `android`

**Interfaces:**
- Consumes: prepare's outputs.
- Produces: artifact `android-<channel>` containing `app-release.aab`.

- [ ] **Step 1: Write the job.** Each step:
  - `ubuntu-24.04`; set up Temurin 21 and Flutter.
  - If `ANDROID_KEYSTORE_BASE64` is set:
    - decode it to `android/upload-keystore.jks`;
    - write `android/key.properties` with `storeFile=upload-keystore.jks`, `storePassword`, `keyAlias` and `keyPassword` from secrets.
  - Run `flutter build appbundle --release …` with `DISTRIBUTION_CHANNEL=play_store`.
  - Check the signature: when signed, the SHA-256 from `keytool -printcert -jarfile build/app/outputs/bundle/release/app-release.aab` must equal `vars.ANDROID_UPLOAD_CERT_SHA256`, otherwise the job fails.
- [ ] **Step 2: Verify:** `gh workflow run build.yml --ref <branch> -f dry_run=true -f platforms=android`. Expected: green, with an artifact of about 40–80 MB and the fingerprint check passing.
- [ ] **Step 3: Commit**

```bash
git add .github/workflows/_android.yml .github/workflows/build.yml
git commit -m "ci(android): signed app bundle build"
```

### Task 10: Linux job and AppImage

**Files:**
- Create: `.github/workflows/_linux.yml`, `linux/packaging/anchorline.desktop.in`, `linux/packaging/AppRun`, `tool/ci/make_appimage.sh`
- Modify: `.github/workflows/build.yml`

**Interfaces:**
- Consumes: Task 4's `ANCHORLINE_CHANNEL` switch.
- Produces: artifact `linux-<channel>` containing the AppImage, named per the Global Constraints.

- [ ] **Step 1: Write the job and packaging.** Each step:
  - The runner image follows the Global Constraints.
  - Install packages with `apt-get install -y clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libstdc++-12-dev libsecret-1-dev libjsoncpp-dev`; add what the build reports missing.
  - Set up Temurin 21 and Flutter.
  - Run `ANCHORLINE_CHANNEL=<simulate> flutter build linux --release …` with `DISTRIBUTION_CHANNEL=website`.
  - `make_appimage.sh <bundle dir> <channel> <version> <build> <out path>`:
    - builds an AppDir: the bundle; `AppRun` exec'ing `$APPDIR/anchorline`; the `.desktop` file with `Name` set to the display name, `Exec=anchorline`, `Icon` and `Categories=Utility;`; a 256 px icon resized from `assets/brand/launcher-1024.png`;
    - runs `appimagetool` (a pinned release, downloaded and checked against a SHA-256 written in the script) with `ARCH=x86_64`.
- [ ] **Step 2: Add a dependency check to the job.** `ldd` on `anchorline` and every `.so` in `lib/` must report no `not found`, and the job prints the list of required system libraries (the `libgit2`/`libssh2` OpenSSL dependency shows up here).
- [ ] **Step 3: Verify:** `gh workflow run build.yml --ref <branch> -f dry_run=true -f platforms=linux`. Expected: green, with the AppImage artifact. Then, on a clean Ubuntu LTS VM, the AppImage starts with the window title `Anchorline Nightly`, and `~/.local/share/nl.despaankamer.ccrlogger.nightly` is the support folder.
- [ ] **Step 4: Commit**

```bash
git add .github/workflows/_linux.yml .github/workflows/build.yml linux/packaging tool/ci/make_appimage.sh
git commit -m "ci(linux): release build and AppImage packaging"
```

### Task 11: Windows job and installer

**Files:**
- Create: `.github/workflows/_windows.yml`
- Modify: `.github/workflows/build.yml`

**Interfaces:**
- Consumes: Task 4's switch and Inno defines.
- Produces: artifact `windows-<channel>` containing the installer, named per the Global Constraints.

- [ ] **Step 1: Write the job.** Each step:
  - `windows-2025`; set up Temurin 21 and Flutter.
  - Run `$env:ANCHORLINE_CHANNEL='<simulate>'; flutter build windows --release …` with `DISTRIBUTION_CHANNEL=website`.
  - Check that `libgit2.dll`, `libssh2.dll`, `libcrypto-3-x64.dll` and `libssl-3-x64.dll` are next to `Anchorline.exe`.
  - Find `ISCC.exe`. If it's missing, run `choco install innosetup -y --no-progress`.
  - Run `ISCC /DMyAppVersion=<V> /DMyAppBuild=<N> /DChannel=<simulate> windows\installer\anchorline.iss`.
  - Leave a disabled signing step, `if: false`, with a comment pointing at spec §7.
- [ ] **Step 2: Verify:** `gh workflow run build.yml --ref <branch> -f dry_run=true -f platforms=windows`. Expected: green, with the installer artifact. Then, on an x64 Windows VM:
  - the nightly installer installs next to a release install, as a separate Start-menu entry "Anchorline Nightly";
  - the nightly's data lands in `%LOCALAPPDATA%\De Spaankamer\Anchorline Nightly` (from PR #136; before that PR merges, it still lands in Documents), and its preferences in `%APPDATA%\De Spaankamer\Anchorline Nightly`;
  - both uninstall cleanly.
- [ ] **Step 3: Commit**

```bash
git add .github/workflows/_windows.yml .github/workflows/build.yml
git commit -m "ci(windows): release build and Inno Setup installer"
```

### Task 12: iOS job

**Files:**
- Create: `.github/workflows/_ios.yml`, `ios/export_options_appstore.plist` (`method` `app-store-connect`, `destination` `export`, `teamID` `U8945M3R9X`, `signingStyle` `automatic`, `uploadSymbols` true), `tool/ci/apple_setup.sh`
- Modify: `.github/workflows/build.yml`

**Interfaces:**
- Produces:
  - `tool/ci/apple_setup.sh`, shared with Task 13, which:
    - runs `sudo xcode-select -s /Applications/Xcode_26.6.app`;
    - runs `unset LIBRARY_PATH SDKROOT` and writes the same into `$GITHUB_ENV`;
    - creates a temporary keychain, imports the `.p12` files that are present, and sets the key partition list;
    - writes `~/.appstoreconnect/private_keys/AuthKey_$ASC_KEY_ID.p8`;
    - installs any `PROFILE_*_BASE64` into `~/Library/MobileDevice/Provisioning Profiles/<UUID>.mobileprovision`.
  - Artifact `ios-<channel>` containing the `.ipa` and the zipped dSYMs.

- [ ] **Step 1: Write the job.** Each step:
  - `macos-26`, then `apple_setup.sh`, then Flutter setup.
  - `flutter build ios --release --config-only …` with `DISTRIBUTION_CHANNEL=app_store`.
  - `xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner -configuration Release -archivePath build/ios/Runner.xcarchive -destination 'generic/platform=iOS' archive`, then `xcodebuild -exportArchive -exportOptionsPlist ios/export_options_appstore.plist …`. Both run with `-allowProvisioningUpdates -authenticationKeyPath … -authenticationKeyID … -authenticationKeyIssuerID …`.
  - **Fallback:** if automatic signing needs a development certificate or fails on the runner, switch to manual signing:
    - Egbert adds `PROFILE_IOS_APPSTORE_BASE64`;
    - the Runner target's Release signing comes from a CI-only xcconfig applied to the Runner target, not to the Pods;
    - record the reason in the job's comments.
- [ ] **Step 2: Verify:** `gh workflow run build.yml --ref <branch> -f dry_run=true -f platforms=ios`. Expected: green, with the `.ipa` artifact. `codesign -dv` on the extracted app shows `Authority=Apple Distribution: …` and `TeamIdentifier=U8945M3R9X`.
- [ ] **Step 3: Commit**

```bash
git add .github/workflows/_ios.yml .github/workflows/build.yml ios/export_options_appstore.plist tool/ci/apple_setup.sh
git commit -m "ci(ios): App Store archive and export"
```

### Task 13: macOS job (Mac App Store `.pkg` and Developer ID `.dmg`)

**Files:**
- Create: `.github/workflows/_macos.yml`, `macos/export_options_devid_ci.plist` (`method` `developer-id`, `signingStyle` `manual`, `signingCertificate` `Developer ID Application`, `provisioningProfiles` mapping `nl.despaankamer.ccrlogger.nightly` → the nightly profile's name, `teamID`), `tool/ci/make_dmg.sh`
- Modify: `.github/workflows/build.yml`

**Interfaces:**
- Consumes: `tool/ci/apple_setup.sh` from Task 12.
- Produces: artifact `macos-<channel>`, containing the `.pkg` for release packaging, or `Anchorline-Nightly-<V>-<N>-macos.dmg` for nightly packaging, plus the zipped dSYMs.

- [ ] **Step 1: Write the job.** Each step:
  - `apple_setup.sh`, then Flutter.
  - `flutter build macos --release --config-only …`. If `--config-only` isn't supported for macOS, run a full `flutter build macos --release`, as `docs/MACOS_DISTRIBUTION.md` does. `DISTRIBUTION_CHANNEL` is `app_store` for release packaging and `website` for nightly packaging.
  - **Release packaging:** archive (`-destination "generic/platform=macOS"`), then export with `macos/export_options_mas.plist`. Both use `-allowProvisioningUpdates` with the API key, with Task 12's fallback rule; the manual fallback needs `PROFILE_MACOS_APPSTORE_BASE64`.
  - **Nightly packaging:**
    - archive with the build-setting overrides `PRODUCT_BUNDLE_IDENTIFIER=nl.despaankamer.ccrlogger.nightly 'PRODUCT_NAME=Anchorline Nightly'`;
    - export with `macos/export_options_devid_ci.plist`;
    - `ditto -c -k --keepParent` the app, then `xcrun notarytool submit … --key … --key-id … --issuer … --wait --timeout 30m`, then `xcrun stapler staple` the app;
    - `make_dmg.sh` runs `hdiutil create -format UDZO` with an `/Applications` symlink, then `codesign --sign "Developer ID Application" --timestamp` on the dmg, notarises it and staples it.
  - Notarisation runs in dry runs too. It publishes nothing and proves the artifact is correct.
- [ ] **Step 2: Verify (two runs):**
  - `-f dry_run=true -f platforms=macos -f simulate=nightly`: `spctl -a -vv -t open --context context:primary-signature <dmg>` reports `accepted, source=Notarized Developer ID`, and `xcrun stapler validate <dmg>` passes.
  - `-f simulate=release`: `pkgutil --check-signature <pkg>` shows `3rd Party Mac Developer Installer` or `Mac Installer Distribution`.
- [ ] **Step 3: Commit**

```bash
git add .github/workflows/_macos.yml .github/workflows/build.yml macos/export_options_devid_ci.plist tool/ci/make_dmg.sh
git commit -m "ci(macos): Mac App Store package and notarised Developer ID dmg"
```

### Task 14: Dry-run verification of the whole workflow

- [ ] **Step 1:** Run `gh workflow run build.yml --ref <branch> -f dry_run=true -f simulate=nightly`, then again with `-f simulate=release`. Expected: all five platform jobs green in both runs, and nothing uploaded anywhere. Check this: the run has no upload steps yet, and the stores and the bucket are unchanged.
- [ ] **Step 2:** Record the measured minutes per job in the PR description. That replaces the estimates in the spec's cost table.
- [ ] **Step 3:** Open PR 3 for Tasks 8–14. In the description, include the desktop identity check results from Tasks 10 and 11.

---

## Phase E: delivery (PR 4, spec rollout step 4)

### Task 15: TestFlight tool (wait for processing, assign to the Nightly group)

**Files:**
- Create: `tool/ci/lib/asc_api.dart`, `tool/ci/testflight.dart`
- Test: `test/tool/ci/asc_api_test.dart`

**Interfaces:**
- Produces:
  - `Uint8List derEcdsaToJose(Uint8List der)`, which converts a DER ECDSA signature into 64 bytes `r‖s`, each left-padded to 32 bytes;
  - `String ascJwt({required String keyId, required String issuerId, required DateTime now, required Uint8List Function(List<int> signingInput) sign})`, an ES256 JWT with `aud: appstoreconnect-v1` and `exp` 20 minutes after `now`. In the CLI, `sign` runs `openssl dgst -sha256 -sign AuthKey.p8` and passes the result through `derEcdsaToJose`;
  - `abstract class AscClient { Future<({String id, String state})?> findBuild({required String appId, required String version, required int build}); Future<void> addBuildToGroup({required String groupId, required String buildId}); }`, with `HttpAscClient` (package `http`) for `/v1/builds` and `/v1/betaGroups/{id}/relationships/builds`;
  - `Future<String> waitForProcessedBuild(AscClient c, {required String appId, required String version, required int build, required Duration timeout, required Duration interval, required Future<void> Function(Duration) sleep, required DateTime Function() now})`. It returns the build id when the state is `VALID`. It throws `StateError` naming the state when that is `INVALID` or `FAILED`, and `TimeoutException('build $version ($build) not processed within …')` on timeout;
  - the CLI: `dart tool/ci/testflight.dart assign --app-id … --version … --build … --group-id … [--timeout-minutes 60]`.

- [ ] **Step 1: Write the failing tests**

```dart
// derEcdsaToJose: 30 44 02 20 <32 bytes r> 02 20 <32 bytes s> → r‖s;
//   02 21 00 <32 bytes> (leading zero) → leading zero stripped; 02 1f <31 bytes> → left-padded to 32
// ascJwt: header {"alg":"ES256","kid":"KEY","typ":"JWT"}, payload iss/iat/exp/aud as specified, 3 base64url parts, no '='
// waitForProcessedBuild with a fake client: null, PROCESSING, VALID → returns id after 3 polls
// waitForProcessedBuild: INVALID → StateError containing 'INVALID'
// waitForProcessedBuild: never found, fake clock past timeout → TimeoutException containing 'not processed within'
```

- [ ] **Step 2: Run them and confirm they fail.** Run: `flutter test test/tool/ci/asc_api_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement the library and CLI.**
- [ ] **Step 4: Run them and confirm they pass.** Run: `flutter test test/tool/ci/`. Expected: PASS.
- [ ] **Step 5: Commit**

```bash
git add tool/ci/lib/asc_api.dart tool/ci/testflight.dart test/tool/ci/asc_api_test.dart
git commit -m "feat(ci): TestFlight build processing wait and Nightly group assignment"
```

### Task 16: Turn on delivery

**Files:**
- Create: `tool/ci/lib/altool_result.dart`
- Test: `test/tool/ci/altool_result_test.dart`
- Modify: `build.yml`, `_ios.yml`, `_macos.yml`, `_android.yml`; add `.github/workflows/_deliver.yml`

**Interfaces:**
- Consumes: Tasks 6, 15 and 9–13.
- Produces:
  - `enum UploadOutcome { uploaded, duplicate, failed }`
  - `UploadOutcome classifyAltoolOutput(String output, int exitCode)`. `uploaded` needs `UPLOAD SUCCEEDED` and no `ERROR`. `duplicate` covers output mentioning that the bundle version was already used or is a duplicate, for example `ENTITY_ERROR.ATTRIBUTE.INVALID.DUPLICATE`, or "has already been used". Anything with `ERROR`, or a non-zero exit code otherwise, is `failed`, **even with exit code 0**.

- [ ] **Step 1: Write the failing classifier tests.** Use the representative strings above. After the first real upload, add the actual `altool` outputs captured in the job log as test fixtures.
- [ ] **Step 2: Run them and confirm they fail.** Run: `flutter test test/tool/ci/altool_result_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement the classifier and wire up delivery.** Skip every step below in dry runs.
  - **iOS:**
    - `xcrun altool --upload-package <ipa> --type ios --apple-id $ASC_APP_ID_IOS --bundle-id nl.despaankamer.ccrlogger --bundle-version <N> --bundle-short-version-string <V> --apiKey $ASC_KEY_ID --apiIssuer $ASC_ISSUER_ID`, with output through `classifyAltoolOutput`;
    - then the Sentry dSYM upload: `dart run sentry_dart_plugin --sentry-define=release=nl.despaankamer.ccrlogger@<V>+<N>` with `SENTRY_AUTH_TOKEN`.
  - **macOS, release packaging:** the same `altool` call with `--type macos`, `$ASC_APP_ID_MACOS` and the `.pkg`, then dSYMs to Sentry.
  - **Android:** `r0adkll/upload-google-play` (SHA-pinned).
    - Release: `track: ${{ vars.PLAY_RELEASE_TRACK }}`, `status: draft`.
    - Nightly: `track: internal`, `status: completed`.
  - **`_deliver.yml`** (`ubuntu-24.04`, `needs` the platform jobs, `if: always()` with per-step guards):
    - **TestFlight (nightly only, iOS succeeded):** `dart tool/ci/testflight.dart assign --app-id $ASC_APP_ID_IOS --version <V> --build <N> --group-id $TESTFLIGHT_NIGHTLY_GROUP_ID`.
    - **Website:**
      - release: only when both `windows-release` and `linux-release` artifacts exist, then `publish.dart release`;
      - nightly: only when `vars.DESKTOP_NIGHTLIES == 'on'`, with each desktop artifact that exists, then `publish.dart nightly`;
      - map `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` from the R2 secrets.
    - **GitHub Release (release only):** `gh release create v<V> --verify-tag --title v<V> --notes-file notes.md` with the Windows and Linux files and a `SHA256SUMS` file. Permission `contents: write`.
    - **Hotfix follow-up (release with patch > 0, after the steps above):** `gh workflow run build.yml --ref main`. Permission `actions: write`.
- [ ] **Step 4: Run the tests.** Run: `flutter analyze && flutter test`. Expected: green.
- [ ] **Step 5: Verify after merging PR 4.** Nightlies only deliver from `main`, so this can't run from the PR branch.
  - Run `gh workflow run build.yml --ref main -f platforms=ios`. Expected: the build appears in TestFlight, gets added to the `Nightly` group, and installs on Egbert's iPhone, showing `Anchorline Nightly 1.2.0 (<N>)` in Settings.
  - Run `-f platforms=android`. Expected: the internal-track release installs from Play.
- [ ] **Step 6: Commit and open PR 4 for Tasks 15–16.** After merging, run Step 5.

```bash
git add tool/ci/lib/altool_result.dart test/tool/ci/altool_result_test.dart .github/workflows
git commit -m "ci: deliver builds to TestFlight, Google Play, the downloads bucket and GitHub Releases"
```

### Task 17: Use BuildInfo for the nightly data folder, then enable desktop nightlies

**Depends on:** PR #136 (issue #135, "keep local data in a per-app folder, not Documents") being merged.
- That PR makes `appDataPaths()` in `lib/data/app_data_folder.dart` the only entry point for local data paths.
- Its pure function `appDataLocationFor({operatingSystem, environment, nightly})` already gives nightlies their own folder (`%LOCALAPPDATA%\De Spaankamer\Anchorline Nightly`, `$XDG_DATA_HOME/nl.despaankamer.ccrlogger.nightly`) with `movesFromDocuments == false`, and its tests cover that.
- It reads the channel through its own `const String.fromEnvironment('BUILD_CHANNEL') == 'nightly'` expression.

Until this task is done, `DESKTOP_NIGHTLIES` stays `off`.

**Files:**
- Modify: `lib/data/app_data_folder.dart`, replacing its `BUILD_CHANNEL` expression with `BuildInfo.isNightly` (Task 3), so the channel is read in one place.

- [ ] **Step 1: Make the swap.** Run `flutter analyze && flutter test`. Expected: green, and PR #136's `test/data/app_data_folder_test.dart` passes unchanged.
- [ ] **Step 2: Verify on real machines, with a nightly from `main` that contains PR #136 and this change.** On each of macOS, Windows and Linux:
  - install the release, sign in, import a dive;
  - install the nightly;
  - the nightly starts with an empty local logbook and leaves the release's files untouched (check file timestamps in the release's folder);
  - the release still opens its data afterwards.
- [ ] **Step 3: Set `DESKTOP_NIGHTLIES=on`** with `gh variable set DESKTOP_NIGHTLIES --body on`, run a nightly, and confirm that `nightly/manifest.json` lists three files.
- [ ] **Step 4: Commit and open the PR**

```bash
git add lib/data/app_data_folder.dart
git commit -m "refactor(app): read the nightly channel from BuildInfo in the data-folder choice"
```

---

## Phase F: first cloud release (spec rollout step 5)

### Task 18: Ship the next release from the cloud

Egbert pushes the tag; an agent watches and checks the results.

- [ ] **Step 1:** Check that `main` is green and that PRs 1–4 are merged.
- [ ] **Step 2:** `git tag -a v1.2.0 -m "v1.2.0 — <title>" -m "<bullets>"`, then `git push origin v1.2.0`.
- [ ] **Step 3:** Watch with `gh run watch`. Expected: run `Release v1.2.0` is green.
- [ ] **Step 4:** Check each result.
  - TestFlight has iOS and macOS `1.2.0 (<N>)`, and **not** in the `Nightly` group.
  - Play has a draft on `vars.PLAY_RELEASE_TRACK`.
  - `releases/manifest.json` has `latest.version == "1.2.0"` with `windows-x64` and `linux-x64`, and the sha256s match the GitHub Release's `SHA256SUMS`.
  - Sentry has release `nl.despaankamer.ccrlogger@1.2.0+<N>` with dSYMs, and the first event from a nightly build arrives with environment `nightly`.
  - A nightly run afterwards produces `1.3.0`.
- [ ] **Step 5:** Egbert submits iOS and macOS for review and rolls out the Play draft by hand.

---

## Phase G: documentation (PR 5, spec rollout step 6)

### Task 19: Release docs and project instructions

**Files:**
- Create: `docs/RELEASING.md`
- Modify:
  - `docs/BETA_DISTRIBUTION.md`, `docs/MACOS_DISTRIBUTION.md`, `docs/TESTFLIGHT_QUICKSTART.md`, `docs/WINDOWS_DISTRIBUTION.md`, `docs/APP_STORE_SUBMISSION.md`: add a top banner saying these are the emergency manual route, and point their versioning sections to `docs/RELEASING.md`;
  - `CLAUDE.md`: under "Where the rest lives", add a line about releases;
  - `docs/RELEASE_AND_MONETISATION.md`: work-breakdown item 3 points to the cloud-builds spec;
  - `.claude/skills/toolchain-gotchas/SKILL.md`: a CI note on `unset LIBRARY_PATH SDKROOT` and the pinned Xcode.

- [ ] **Step 1: Write `docs/RELEASING.md`.** It covers:
  - releases are annotated `vX.Y.0` tags on `main`;
  - hotfixes:
    1. `git switch -c release/X.Y vX.Y.0`;
    2. cherry-pick the fix from `main`;
    3. `git tag -a vX.Y.Z`;
    4. push the branch and the tag;
  - tags never move;
  - what lands where, and what Egbert does by hand afterwards;
  - "Re-run failed jobs", never "Re-run all jobs";
  - running a nightly or dry run with the button;
  - yearly certificate renewal: regenerate, re-export, `gh secret set`;
  - the emergency manual route: build with a build number above the last cloud one, then raise `BUILD_NUMBER_BASE`;
  - `BUILD_NUMBER_BASE` after a workflow rename.
- [ ] **Step 2:** Edit the other files as listed above. The CLAUDE.md line: "Releases are tags, built by `.github/workflows/build.yml`; never bump `pubspec.yaml`'s version — see `docs/RELEASING.md`."
- [ ] **Step 3: Commit and open PR 5**

```bash
git add docs CLAUDE.md .claude/skills/toolchain-gotchas/SKILL.md
git commit -m "docs: releasing from the cloud; manual docs become the emergency route"
```

---

## Phase H: when the repository goes public (spec rollout step 7)

### Task 20: Lock down signing and switch on the nightly schedule

Egbert does this in the GitHub settings, or with `gh api`, on the day the repo goes public.

- [ ] **Step 1:** Create environment `signing` with deployment refs `main` and tag pattern `v*`, and no required reviewers. Move every secret from Task 7 into it.
- [ ] **Step 2:** In `_ios.yml`, `_macos.yml`, `_android.yml` and `_deliver.yml`, add `environment: signing` to every job that reads a secret. Run `gh workflow run build.yml --ref main -f platforms=ios`. Expected: green, with the build in TestFlight.
- [ ] **Step 3:** Delete the repository-level copies of the secrets, then run `gh secret list`. Expected: empty at repository level.
- [ ] **Step 4:** Add the rulesets.
  - `main`: a pull request is required, with 1 approving review; bypass is "Repository admin", so Egbert can merge his own PRs.
  - Tags `refs/tags/v*`: only bypass actors (Egbert) may create, update or delete them.
- [ ] **Step 5:** Under Actions → General, require approval for all outside collaborators' fork PR workflows.
- [ ] **Step 6:** Check that a dry run from a branch builds unsigned and green: `gh workflow run build.yml --ref <branch> -f dry_run=true`.
- [ ] **Step 7:** Run `gh variable set NIGHTLY_SCHEDULE --body on`. The next scheduled run at 02:00 UTC delivers a nightly when `main` has changed.
