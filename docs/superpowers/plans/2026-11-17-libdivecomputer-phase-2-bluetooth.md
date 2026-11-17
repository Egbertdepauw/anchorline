# libdivecomputer phase 2: Bluetooth computers from other brands — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Download dives from every Bluetooth LE dive computer upstream libdivecomputer reads, on iOS, Android, macOS, Windows and Linux. The first milestone is a tester build in which Ratio, OSTC and Divesoft computers scan, connect, download, show their dives and sync, and in which a tester can record a download and share it.

**Architecture:** A new pure-Dart package, `packages/libdivecomputer`, vendors upstream libdivecomputer at a pinned commit and compiles it with a Dart build hook, using each platform's own C toolchain. A small C layer turns libdivecomputer's blocking custom I/O into a packet queue. The main isolate feeds that queue from the app's `BleCentral`, which owns the Bluetooth connection. Each download runs libdivecomputer on its own isolate. That isolate parses every dive with `dc_parser_new2`, maps it to `ConvertedDive` and hands it to the import path phase 1 built. The work ships as five PRs: the native build, the engine (package only), sync readiness, the app (the tester milestone), and hardening after the testers start.

**Tech Stack:** Dart 3.12 / Flutter 3.44. `package:hooks` 1.0.x, `package:code_assets` 1.0.x and `package:native_toolchain_c` 0.17.x, all already in `pubspec.lock` through `sqlite3` 3.3.1. `ffigen` as a dev dependency only. Upstream libdivecomputer master. PowerSync 2.1.0 and Supabase Postgres.

**Spec:** `docs/superpowers/specs/2026-11-15-libdivecomputer-brands-design.md`, sections 1–5 and 7–13. Read it together with the phase 1 plan, `docs/superpowers/plans/2026-11-15-libdivecomputer-phase-1-groundwork.md`, and especially its "Changes made during execution" section: where the spec and that section differ, that section is what was built.

## Before anything is built (Egbert)

1. **Is the Sync Streams config with `libdc_dives` (#224, together with #208) deployed, and did its fake-row check pass?** Until it has, no build may send `dc_engines: 2`, so PR C stays unmerged, and no signed-in device may hold a libdivecomputer dive. There are two reasons. A build that sends `dc_engines: 1` and uploads a libdivecomputer dive never gets that dive back from any stream, so PowerSync drops it from the device after the upload. And if an older config is still live, it hands those dives to installed builds, which would push them to Subsurface Cloud as Shearwater dives.
2. Approve the spec amendments below.
3. Pick the address the share text names. The default is `recordings@anchorline.eu`, which the catch-all routes.

## Spec amendments (for Egbert's OK)

Each of these follows from reading upstream at `0194f09` or from a gap that phase 1 left. Where the spec and this list differ, the list wins once Egbert approves it.

1. **The serial-line callbacks are no-ops over Bluetooth.** Spec section 4 says `set_break`, `set_dtr`, `set_rts`, `get_lines` and `configure` return `DC_STATUS_UNSUPPORTED`. But Divesoft (through `hdlc.c`), OSTC (`hw_ostc3.c:484`) and Ratio (`divesystem_idive.c:185`) all call `dc_iostream_configure` unconditionally and abort on any failure. libdivecomputer treats a missing callback as success, and that is what Subsurface's Bluetooth path gives these backends. So `configure`, `set_dtr`, `set_rts` and `set_break` succeed without doing anything and are noted in the recording. Only `get_lines` returns `UNSUPPORTED`. `flush` also succeeds without doing anything, because every write has already completed before it returns. `purge` clears the inbound queue. The spec had `flush` clear the inbound queue too.
2. **A new synced column, `dives.dc_fingerprint`** (migration 0028), holding the hex of the libdivecomputer fingerprint. Every libdivecomputer dive has `dc_dive_number` 0, so phase 1's `findSameDive` cannot tell apart two dives from one computer that start less than 60 seconds apart. Example: a 30-second "dive" when the diver jumps in, then the real dive. The second dive would be handled as the first and never stored. With the fingerprint, a stored download matches only the same fingerprint. The follow-up Subsurface writer also needs the fingerprint, on devices without the raw blob and on the server, because Subsurface's `diveid` is the SHA-1 of it.
3. **Recording happens in the C layer, and so does replay.** The C layer records what each callback consumed and returned. Replay serves those reads in order, on demand, which is deterministic. A replay driven from Dart would push packets after each write, and backends that sleep and then purge (Ratio, `divesystem_idive.c:883`) would drop them. The stand-ins in section 11 instead run on the live path, through a fake `BlePeripheral`. That way they also test the isolate, the queue and the Bluetooth profiles.
4. **`LibdcBleLink` gains `Future<void> get disconnected`.** The spec's interface has no way to report a dropped connection.
5. **A re-parse looks up the descriptor by vendor and product name first,** and only then by family and model. Family numbers can change between libdivecomputer versions (spec section 7).
6. **The import screen scans through `BleCentral` for both engines.** Two scans at once would fight over `flutter_blue_plus`. Shearwater results still connect through `flutter_blue_plus` exactly as today. On Windows, Shearwater devices stay unlisted, as today.
7. **Fingerprints:** before a download, the app loads every saved fingerprint for the chosen family. In the `DEVINFO` event callback, the download isolate passes the one for that serial to `dc_device_set_fingerprint` (Subsurface's pattern). The fingerprint of the newest dive is saved only after a clean finish in which no dive failed. This settles the phase 1 PR 4 deferral.
8. **The checked-families list starts empty.** No family other than Shearwater has a real recording yet, so every family is "Not yet tested by us", including the first three.
9. **No `config.h`.** The defines are passed as `-D` flags from one table in the hook, the way `contrib/android/Android.mk` does it. Only `version.h` and `revision.h` are committed files in `native/`.

## Global Constraints

- Spec: "`dive_id` for these dives is `sha256('libdc:<vendor>:<serial>:<fingerprint hex>')`, truncated to 32 hex characters like today." `<serial>` is decimal, the hex is lower case, and the result has the same form as `generateDiveId`. "The id is also frozen at first import; nothing recomputes it."
- `dc_dive_number` is 0. `dc_model` stores `ShearwaterModel.unknown` (index 13). `dive_computers.model` stores 0.
- The last fingerprint is saved under the key `libdc:<family>:<serial>`, with the family as its decimal integer. This is device-local state (principle 7b).
- `parser_version` for these dives is `kLibdcParserVersion`, which starts at 1. It is bumped on every pin move and every mapping change. A dive is a libdivecomputer dive exactly when `dc_family` is set. Until the tester build ships, no libdivecomputer dive exists anywhere, so version 1's output and its guard digests may still change. After that, every output change bumps the version.
- The raw blob is the `ALDC` envelope (spec section 7), stored in `dive_raw_blobs`.
- Shearwater devices keep going to the Dart reader. libdivecomputer's Shearwater descriptors are never offered in the app. Tests may use them to replay the Petrel 3 trace.
- Parse with `dc_parser_new2` and the descriptor chosen for the download, both at download time and later.
- Spec: "Every build compiles every family." The leave-out list starts empty.
- No libusb, hidapi, BlueZ or libmtp. There is no prebuilt library and nothing is downloaded at build time.
- The vendored tree always equals "pinned commit + `patches/`". `tool/update_upstream.sh` is the only way it changes. Every patch goes upstream to Jef, with no private fork.
- Anchorline's C layer is licensed LGPL-2.1-or-later.
- Tier copy is exactly "Not yet tested by us". The share text says plainly that the file contains the diver's dives, the computer's serial number and any GPS positions.
- Shearwater dive ids, analysis and import behaviour don't change.
- Imported data changes only through the refresh (spec 7a, as built in phase 1: a refresh never changes `start_time`).
- Sentry never receives libdivecomputer log text, recordings, serials or dive data. Use `redactImportError`.
- Dives and samples live in PowerSync. Read and write them through `_ps`.
- A migration is applied to the live database before the PR containing it is merged.
- Never remove the write-direction safety hold in `sync_orchestrator.dart`. Don't run `dart format` on whole files. Never `git reset --hard`.
- Every PR has `flutter analyze` clean, `flutter test` passing, `dart test` passing in `packages/subsurface_core` and in `packages/libdivecomputer` (with `dart analyze --fatal-infos` in each), and `./supabase/lint_migrations.sh` passing.
- Git text is in English. Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Build agents run on `model: "sonnet"`, except Tasks 4 and 6 (the C layer and the download session, which are concurrency design), which run on `"opus"`. Review agents run on `"opus"`.

## Review Focus

1. **A download that stops halfway:** a Bluetooth drop, the diver walking away, an iOS screen lock, or Cancel. Expected: every dive already committed stays, no dive is half-written, the fingerprint doesn't move, and the next download fetches the rest. Pinned in Tasks 6 and 11.
2. **Two dives from one computer that start less than 60 s apart, and "Download everything again" afterwards.** Expected: both are stored under their own ids, and the second run changes nothing. Pinned in Task 8.
3. **An installed build (1.1.0+48 or older) on the same account as a tester build.** Expected: it never sees libdivecomputer dives, their computers or their bailout rows, and keeps syncing its Shearwater dives. A Subsurface push from either build never includes a libdivecomputer dive. Pinned by Task 9's tests and by Egbert's fake-row check.
4. **A CCR dive with ppO2 cells but no millivolts or calibration (Divesoft, OSTC), and one with a setpoint only (Ratio).** Expected: the cell health and cell screens never count these dives as cells at 0 mV, nothing crashes, and the info tab shows the brand, the product and a decimal serial. Pinned in Task 13.
5. **An advertised name that matches a Shearwater, several families, or nothing.** Expected: a Shearwater always goes to the Dart reader. Several families make the diver pick. A name that matches nothing is reachable through the manual picker. An empty name is never matched. Pinned in Tasks 2 and 12.

---

## PR map

| PR | Branch | Tasks | Base | Ships safely because | Egbert, outside the code |
|---|---|---|---|---|---|
| A Native build | `feat/libdc-p2-native` | 1–3 | `main` | Nothing calls libdivecomputer except the About line and the licence page. | One local release build per platform he builds on his Mac (Task 3, Step 7). |
| B Engine | `feat/libdc-p2-engine` | 4–7 | A | Package only; the app doesn't use it yet. | — |
| C Sync readiness | `feat/libdc-p2-sync` | 8–9 | `main` | 0028 is additive. The writer skip only affects rows with `dc_family` set, and none exist. `dc_engines: 2` only goes out once the streams are live. | Apply 0028 before merging, and confirm the `libdc_dives` deploy before merging. |
| D Downloads in the app (milestone) | `feat/libdc-p2-app` | 10–13 | B + C | The first libdivecomputer dives. Each one is atomic, re-parseable from its envelope, and gated from old builds. | Task 14: the tester build and its checks. |
| E After the testers start | `feat/libdc-p2-standins`, `feat/libdc-p2-reparse`, `feat/libdc-p2-cells`, `feat/libdc-p2-char-read`, `feat/libdc-p2-copies` | 15–19 | `main` after D | Each is independent and touches only its own files. | Cell agreement thresholds (Task 17). |

PR C doesn't depend on A or B, so it can be built in parallel with them. PR D needs both B and C merged. The E PRs only need D, and can run in parallel with each other: their file sets don't overlap.

Pin: take the newest upstream master commit on the day Task 1 runs. At plan time that is `0194f09d91c850b18480e73a9fa7b276c926043c` (2026-11-16, "Shearwater: keep the manifest records behind a deleted dive"). It already contains our Shearwater patch, so `patches/` starts empty. Migration 0028 is the next free number. If another migration took it, use the next one and rename it everywhere.

---

## PR A — The native library builds everywhere

### Task 1: Upstream source at a pinned commit

**Files:**
- Create: `packages/libdivecomputer/pubspec.yaml`, `analysis_options.yaml`, `README.md`
- Create: `packages/libdivecomputer/third_party/libdivecomputer/`: `include/`, `src/` (`*.c`, `*.h`, `libdivecomputer.symbols`), `COPYING`, `NEWS`, `README`, `configure.ac`, plus `contrib/android/Android.mk` and `contrib/msvc/libdivecomputer.vcxproj` as references for the defines
- Create: `packages/libdivecomputer/UPSTREAM`, `patches/README.md`
- Create: `packages/libdivecomputer/native/include/libdivecomputer/version.h`, `native/revision.h` (generated)
- Create: `packages/libdivecomputer/lib/src/upstream.g.dart` (generated)
- Create: `packages/libdivecomputer/tool/update_upstream.sh`, `tool/check_vendor.sh`
- Test: `packages/libdivecomputer/test/upstream_test.dart`

**Interfaces:**
- Produces:
  - `UPSTREAM` has one `key value` pair per line: `commit <40-hex>`, `date <yyyy-mm-dd>`, `url https://github.com/libdivecomputer/libdivecomputer.git`, then one `patch <file name> <upstream status>` line per patch, or a single `patches none` line.
  - `const String kLibdcPinnedCommit = '<40-hex>';` in `upstream.g.dart`.
  - `version.h` is `include/libdivecomputer/version.h.in`, with `DC_VERSION_*` taken from `configure.ac`'s `m4_define`s (0.10.0-devel at plan time). `revision.h` is `#define DC_VERSION_REVISION "<first 7 hex>"`.
  - `tool/update_upstream.sh <commit>`:
    1. Clones upstream into a temporary directory at `<commit>`.
    2. Replaces `third_party/libdivecomputer/` with the listed paths.
    3. Applies each `patches/*.patch` in name order with `git apply`. If one no longer applies, it prints `patch <name> no longer applies: if upstream merged it, delete it in this PR` and exits 1.
    4. Regenerates `version.h`, `revision.h` and `upstream.g.dart`, runs `dart run ffigen`, and rewrites `UPSTREAM`.
    5. Leaves the diff for review.
  - `tool/check_vendor.sh` repeats the update into a temporary copy at the commit in `UPSTREAM` and fails if `third_party/` differs. CI runs it (Task 3).

- [ ] **Step 1: Write the failing test.**

  ```dart
  test('UPSTREAM, upstream.g.dart and revision.h name the same commit', ...);
  test('every patch file is listed in UPSTREAM and in patches/README.md, and nothing else is', ...);
  test('version.h carries the version from the vendored configure.ac', ...);
  ```

- [ ] **Step 2: Run it and check it fails.** Run: `cd packages/libdivecomputer && dart test test/upstream_test.dart`. Expected: FAIL (no package yet).
- [ ] **Step 3: Write the scripts and run `tool/update_upstream.sh <pin>`.** `pubspec.yaml` declares `ffi: 2.2.0`, `hooks`, `code_assets`, `native_toolchain_c`, `crypto` and `subsurface_core: {path: ../subsurface_core}`, at the versions in the app's lock. Dev dependencies are `test` and `ffigen`. `README.md` says what the package is, that the pin moves only through the script, and that every patch goes upstream first. It also says (spec section 3) that a pin move is its own PR: it bumps `kLibdcParserVersion`, keeps every replay test passing, and its description has a "Known changes" part that lists the upstream commits between the two pins that touch a checked family.
- [ ] **Step 4: Run the test.** Same command. Expected: PASS. Then run `tool/check_vendor.sh`. Expected: exit 0.
- [ ] **Step 5: Commit.** `git commit -m "feat(libdc): vendor upstream libdivecomputer at a pinned commit"`

### Task 2: The build hook, the bindings and the descriptor list

**Files:**
- Create: `packages/libdivecomputer/hook/build.dart`
- Create: `packages/libdivecomputer/lib/src/hook/build_config.dart` (sources, defines, the leave-out table; pure Dart, imported by the hook)
- Create: `packages/libdivecomputer/native/anchorline_families.c` and `.h`
- Create: `packages/libdivecomputer/ffigen.yaml`, `lib/src/bindings.g.dart` (generated and committed)
- Create: `packages/libdivecomputer/lib/libdivecomputer.dart`, `lib/src/descriptors.dart`
- Test: `packages/libdivecomputer/test/descriptors_test.dart`, `test/leave_out_test.dart`, `test/purity_test.dart`

**Interfaces:**
- Produces:
  - The hook builds one dynamic library with `CBuilder.library(name: 'divecomputer', assetName: 'src/bindings.g.dart', ...)`. ffigen uses `ffi-native` with `assetId: 'package:libdivecomputer/src/bindings.g.dart'`, so every binding is an `@Native` function resolved through the code asset, with no `DynamicLibrary.open`.
  - Sources: every `src/*.c` of the vendored tree, except `serial_win32.c` on POSIX targets and `serial_posix.c` on Windows, plus `native/*.c`. If another file turns out to be platform-only, add it to the table in `build_config.dart` with a comment.
  - Includes: `native/include` first (for `version.h`), then `third_party/libdivecomputer/include`, `third_party/libdivecomputer/src` and `native`.
  - Defines, taken from `contrib/android/Android.mk` and `contrib/msvc/libdivecomputer.vcxproj` at the pin, passed as `-D` flags (no `config.h`):
    - Every target: `ENABLE_LOGGING`, `HAVE_VERSION_SUFFIX`.
    - POSIX targets (Android, iOS, macOS, Linux): `HAVE_PTHREAD_H`, `HAVE_STRERROR_R`, `HAVE_CLOCK_GETTIME`, `HAVE_LOCALTIME_R`, `HAVE_GMTIME_R`, `HAVE_TIMEGM`, `HAVE_STRUCT_TM_TM_GMTOFF`, `HAVE_UNISTD_H`.
    - iOS and macOS also get `HAVE_MACH_MACH_TIME_H` and `HAVE_MACH_ABSOLUTE_TIME`. macOS also gets `HAVE_IOKIT_SERIAL_IOSS_H`. Linux also gets `HAVE_LINUX_SERIAL_H`.
    - Windows: `_CRT_SECURE_NO_WARNINGS`, `WIN32`, `_WINDOWS`, `_USRDLL`, `LIBDIVECOMPUTER_EXPORTS`. Link `ws2_32`. Pass `/DEF:` with a `.def` file the hook writes into its output directory: `EXPORTS`, then every line of `src/libdivecomputer.symbols`, then every `al_` function of `native/`. The vcxproj does the same.
    - Never: `HAVE_LIBUSB`, `HAVE_HIDAPI`, `HAVE_BLUEZ`, `HAVE_LIBMTP`, `HAVE_WS2BTH_H`, `HAVE_AF_IRDA_H`. Classic Bluetooth waits for phase 3 and IrDA is a non-goal; `bluetooth.c` and `irda.c` compile to their "unsupported" paths.
    - macOS and iOS link with `-Wl,-headerpad_max_install_names`. `flutter test` rewrites install names, and in phase 1 a long worktree path made `install_name_tool` fail.
  - Leave-out list: the hook user-define `leave_out_families` is a list of strings, read from `input.userDefines['leave_out_families']`, and it starts empty. The app's `pubspec.yaml` gets `hooks: user_defines: libdivecomputer: leave_out_families: []`. Valid values are the keys of `kLeaveOutTable`: `suunto_eonsteel`, `deepblu_cosmiq`, `oceans_s1`, `divesoft_freedom`, `hw_ostc3`, `pelagic_i330r`, `deepsix_excursion`, `cochran_commander` and `mclean_extreme`, the families of spec section 10's table. Each entry lists the family's source files, its `DC_FAMILY_*` value, and its entry functions with their exact prototypes from the family's header (the device-open function, plus the parser-create function where the family has its own parser). For each listed family, the hook leaves its files out, writes `leave_out_stubs.c` into its output directory with one stub per entry function that returns `DC_STATUS_UNSUPPORTED`, compiles that instead, and defines `AL_LEFT_OUT_<KEY>`. An unknown value fails the hook with a message listing the valid ones.
  - `int al_family_present(unsigned int family)` in `anchorline_families.c` returns 0 for a left-out family and 1 otherwise.
  - Dart API (`lib/libdivecomputer.dart`):

    ```dart
    class LibdcDescriptor {
      final String vendor, product; final int family, model, transports;
      bool get supportsBle; bool get isShearwater; // vendor == 'Shearwater'
    }
    abstract final class Libdc {
      static String get version;        // dc_version(null)
      static String get pinnedCommit;   // kLibdcPinnedCommit
      static List<LibdcDescriptor> descriptors();          // families present, upstream order
      static List<LibdcDescriptor> matchBle(String name);  // see below
      static bool familyPresent(int family);
    }
    ```

    `matchBle` returns the descriptors that support BLE, whose family is present, that aren't Shearwater, and for which `dc_descriptor_filter(d, DC_TRANSPORT_BLE, name)` is 1. An empty or whitespace name returns `[]`: `dc_descriptor_filter` matches everything when given no name.

- [ ] **Step 1: Write the failing tests.**

  ```dart
  test('version names the pinned revision', ...);  // contains kLibdcPinnedCommit.substring(0, 7)
  test('descriptors include Divesoft Liberty, OSTC 4 and Ratio iX3M 2021 GPS Tech+', ...);
    // Liberty: DC_FAMILY_DIVESOFT_FREEDOM, model 10; OSTC 4: DC_FAMILY_HW_OSTC3, 0x43;
    // iX3M 2021 GPS Tech+: DC_FAMILY_DIVESYSTEM_IDIVE, 0x64. All supportsBle.
  test('matchBle never offers a Shearwater', ...);          // 'Petrel', 'Perdix', 'Teric' → []
  test('matchBle("Liberty 1234") is Divesoft Liberty alone', ...);
  test('matchBle("OSTC4-12345") gives only BLE models of DC_FAMILY_HW_OSTC3', ...);
  test('matchBle("RATIO-123") gives only DC_FAMILY_DIVESYSTEM_IDIVE models with BLE', ...);
  test('matchBle of an empty or blank name is empty', ...);
  // leave_out_test.dart (build the hook with testCodeBuildHook and load its output):
  test('leaving out divesoft_freedom still links; the family reports absent', ...);
    // al_family_present(DC_FAMILY_DIVESOFT_FREEDOM) == 0, al_family_present(DC_FAMILY_HW_OSTC3) == 1
  test('an unknown leave-out name fails the hook and lists the valid names', ...);
  // purity_test.dart
  test('lib/ imports no Flutter, BLE, database or dart:io (except lib/src/hook/)', ...);
  ```

- [ ] **Step 2: Run them and check they fail.** Run: `cd packages/libdivecomputer && dart test`. Expected: FAIL.
- [ ] **Step 3: Implement the interfaces above,** and generate the bindings with `dart run ffigen`. ffigen covers the public headers the package uses (`context.h`, `descriptor.h`, `device.h`, `parser.h`, `iterator.h`, `custom.h`, `ble.h`, `ioctl.h`, `datetime.h`, `version.h`, `common.h`) and `native/*.h`.
- [ ] **Step 4: Run the tests.** Run: `cd packages/libdivecomputer && dart analyze --fatal-infos && dart test`. Expected: PASS on macOS.
- [ ] **Step 5: Commit.** `git commit -m "feat(libdc): build libdivecomputer with a Dart build hook and list its descriptors"`

### Task 3: The app links it; CI builds it on every platform

**Files:**
- Modify: `pubspec.yaml` (the path dependency `libdivecomputer: {path: packages/libdivecomputer}`, the `hooks: user_defines` block, and the asset `packages/libdivecomputer/third_party/libdivecomputer/COPYING`)
- Create: `lib/ui/licences.dart` (`void registerLicences()`, called early in `lib/main.dart`)
- Modify: `lib/main.dart`, `lib/ui/screens/settings/about_tab.dart`
- Modify: `NOTICE.md`, `CONTRIBUTING.md` (spec section 10: the permission covers the linked library; other authors keep their copyright; the families ship in every build; the leave-out list)
- Modify: `.github/workflows/check.yml` (`dart pub get`, `dart analyze --fatal-infos` and `dart test` in `packages/libdivecomputer`)
- Create: `.github/workflows/libdivecomputer-build.yml`
- Modify: `.claude/skills/toolchain-gotchas/SKILL.md`
- Test: `test/ui/screens/settings/about_tab_test.dart`, `test/ui/licences_test.dart`

**Interfaces:**
- Produces:
  - The About tab shows `libdivecomputer <Libdc.version>`. On a real device this line proves the library loaded there.
  - `registerLicences()` adds a `LicenseEntryWithLineBreaks(['libdivecomputer'], <COPYING text>)` through `LicenseRegistry.addLicense`.
  - `libdivecomputer-build.yml` runs on pull requests that touch `packages/libdivecomputer/**`, `pubspec.yaml`, `pubspec.lock` or the workflow itself, and on `workflow_dispatch`. Flutter 3.44.0 on every job. Jobs:
    - `vendor` (ubuntu-latest): `packages/libdivecomputer/tool/check_vendor.sh`.
    - `macos` (macos-15): the package's `dart test`, then `flutter build macos --debug`, then `flutter build ios --simulator --debug --no-codesign`. Each app bundle's `Frameworks/` must contain the libdivecomputer framework (grep its listing for `divecomputer`).
    - `windows` (windows-2025): the package's `dart test`, then `flutter build windows --debug`. `divecomputer.dll` must be next to the executable.
    - `linux-android` (ubuntu-latest): the package's `dart test`, then `flutter build linux --debug` and `flutter build apk --debug`. `unzip -l` must list `libdivecomputer.so` under `lib/arm64-v8a/`, `lib/armeabi-v7a/` and `lib/x86_64/`. Install what the Linux build needs (clang, cmake, ninja, pkg-config, GTK 3 and the libraries the existing plugins need) and Java 17.

- [ ] **Step 1: Write the failing tests.**

  ```dart
  testWidgets('the About tab shows the libdivecomputer version', ...);  // finds 'libdivecomputer 0.10.0'
  test('registerLicences adds a libdivecomputer entry with the LGPL text', ...);
  ```

- [ ] **Step 2: Run them and check they fail.** Run: `flutter test test/ui/screens/settings/about_tab_test.dart test/ui/licences_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement.** In `NOTICE.md`, add a libdivecomputer entry for the linked library (project, URL, licence, the pinned commit, and where the source and patches are), next to the existing entry for the ported Shearwater parser. Widen the #211 wording in `CONTRIBUTING.md` to the whole library, as spec section 10 says.
- [ ] **Step 4: Run all tests.** Run: `flutter analyze && flutter test && (cd packages/libdivecomputer && dart test) && (cd packages/subsurface_core && dart test)`. Expected: clean, all pass.
- [ ] **Step 5: Push and watch the new workflow.** Expected: every job green. If a platform can't be made to build cleanly at Flutter 3.44, stop and tell Egbert before turning to the spec's prebuilt fallback.
- [ ] **Step 6: Local checks on this Mac.** Run a release build for macOS, iOS (`flutter build ipa`, see `toolchain-gotchas` for the SDK note) and Android. Then run `linux/packaging/build_in_docker.sh` if Docker is running, and check with `unzip`/`find` that each bundle contains the library. If the Windows release workflow is available, run it once with `workflow_dispatch`.
- [ ] **Step 7 (Egbert): install one release build per platform.** On each device, About shows `libdivecomputer 0.10.0-devel (<7 hex>)`.
- [ ] **Step 8: Add a "Build hook (libdivecomputer)" section to `toolchain-gotchas`.** It covers what this task found per platform: the header-pad flag, the `.def` file, the Linux CI packages, and anything else that bit.
- [ ] **Step 9: Commit and open PR A.** `git commit -m "feat(libdc): link libdivecomputer in the app and build it in CI on every platform"`

---

## PR B — The engine (package only)

### Task 4: The C layer

**Files:**
- Create: `packages/libdivecomputer/native/anchorline_io.h`, `native/anchorline_io.c`, `native/al_thread.h` (a mutex, condition variable and monotonic clock shim: pthreads on POSIX, `SRWLOCK`/`CONDITION_VARIABLE` on Windows)
- Modify: `packages/libdivecomputer/ffigen.yaml`, `lib/src/bindings.g.dart`
- Test: `packages/libdivecomputer/test/c_layer_test.dart`

**Interfaces:**
- Produces (C, exported, LGPL-2.1-or-later header):

  ```c
  typedef struct al_link al_link_t;
  typedef void (*al_request_fn)(intptr_t link, int32_t kind);   // AL_REQ_WRITE 1, AL_REQ_CHAR_READ 2, AL_REQ_CHAR_WRITE 3
  al_link_t *al_link_new_live(const char *advertised_name, al_request_fn request);
  al_link_t *al_link_new_replay(const char *advertised_name, const uint8_t *events, size_t size);
  void al_link_free(al_link_t *link);
  dc_status_t al_link_iostream(al_link_t *link, dc_context_t *context, dc_iostream_t **out);
  // main isolate → C, thread-safe
  void al_link_push(al_link_t *link, const uint8_t *data, size_t size);
  size_t al_link_pending(al_link_t *link, uint8_t *data, size_t capacity, char *uuid, size_t uuid_capacity);
  void al_link_complete(al_link_t *link, dc_status_t status, const uint8_t *data, size_t size);
  void al_link_disconnected(al_link_t *link);
  void al_link_cancel(al_link_t *link);
  int al_link_cancelled(void *link);                 // for dc_device_set_cancel
  void al_link_set_write_timeout(al_link_t *link, int milliseconds);   // default 10000; tests use less
  // recording
  void al_link_set_recording(al_link_t *link, int enabled);
  size_t al_link_recording(al_link_t *link, uint8_t *data, size_t capacity);  // bytes needed when capacity is too small
  ```

- Callback behaviour. Every one of them is set in `dc_custom_cbs_t`:

  | Callback | Live link | Replay link |
  |---|---|---|
  | `set_timeout(ms)` | Stored. -1 waits until data, cancel or disconnect; 0 doesn't wait. | Stored |
  | `read(size)` | Takes up to `size` bytes from the head packet. A longer packet's remainder stays at the head for the next read. Waits up to the timeout, then returns `TIMEOUT` with `actual` 0. Returns `IO` after a disconnect and `CANCELLED` after a cancel. | The next recorded `R`. Returns `PROTOCOL` if the next recorded event is a `W`. |
  | `write` | Copies the bytes to the pending slot, calls `request(AL_REQ_WRITE)` and waits for `al_link_complete` up to the write timeout, otherwise `TIMEOUT`. Returns the status given; `actual` is `size` on success. | Compares with the next recorded `W`. A mismatch returns `PROTOCOL` and logs the event index. |
  | `poll(ms)` | `SUCCESS` when a packet is queued or arrives in time, otherwise `TIMEOUT` | `SUCCESS` if the next event is an `R` |
  | `get_available` | Queued byte count | The next `R`'s length |
  | `purge(dir)` | Input: clears the queue and records `P` with the dropped byte count. Output: no-op. | No-op |
  | `flush` | `SUCCESS`, no-op | `SUCCESS` |
  | `sleep(ms)` | Sleeps in slices of at most 50 ms; returns `CANCELLED` early after a cancel. Recorded as `S`. | Returns at once |
  | `ioctl` `BLE_GET_NAME` | Copies the advertised name, NUL-terminated; `INVALIDARGS` if it doesn't fit | The same, with the name given |
  | `ioctl` `BLE_CHARACTERISTIC_READ` / `_WRITE` | A request to the main isolate, like a write, with the UUID from the ioctl payload; recorded as `C` | The next recorded `C` |
  | Any other ioctl (PIN code, access code, unknown) | `UNSUPPORTED`, recorded as `I` | `UNSUPPORTED` |
  | `configure`, `set_dtr`, `set_rts`, `set_break` | `SUCCESS`, no-op, recorded as `X` (amendment 1) | `SUCCESS` |
  | `get_lines` | `UNSUPPORTED` | `UNSUPPORTED` |
  | `close` | `SUCCESS`; wakes every waiter with `IO` | `SUCCESS` |

- The inbound queue is capped at 8 MiB. On overflow the link records `X overflow`, and every later read returns `IO`.
- Recording event layout, big-endian, one after another: `u8 kind` (`'W' 'R' 'P' 'C' 'I' 'S' 'T' 'X'`), `u64 microseconds since the link was created`, `u32 length`, then `length` bytes. `C` carries `u8 direction`, `u8 uuid length`, the UUID string and the value. Replay reads only `R`, `W` and `C` and skips the rest.

- [ ] **Step 1: Write the failing tests.** The blocking side runs on a helper isolate that calls `dc_iostream_*` on the iostream from `al_link_iostream`, passed across as an address. The test isolate plays the main isolate through a `NativeCallable.listener`.

  ```dart
  test('read returns one packet per call and keeps the rest of a longer packet', ...);
  test('read waits for a packet pushed later', ...);
  test('read times out after the timeout libdivecomputer set', ...);   // 100 ms → TIMEOUT within 100–600 ms
  test('a write waits for completion and returns the status given', ...);
  test('a write nobody completes times out', ...);                     // al_link_set_write_timeout(200)
  test('cancel wakes a waiting read with CANCELLED and al_link_cancelled turns 1', ...);
  test('a disconnect wakes a waiting read and a waiting write with IO', ...);
  test('purge input drops what is queued; poll sees a queued packet and times out otherwise', ...);
  test('configure, set_dtr, set_rts and set_break succeed; get_lines is unsupported', ...);
  test('GET_NAME copies the advertised name; a buffer too small is INVALIDARGS', ...);
  test('PIN code, access code and an unknown ioctl are unsupported', ...);
  test('the recording lists W, R and P in order with rising timestamps', ...);
  test('replay serves recorded reads on demand and reports a diverging write as PROTOCOL', ...);
  test('overflowing the queue turns into IO, not a crash', ...);
  ```

- [ ] **Step 2: Run them and check they fail.** Run: `cd packages/libdivecomputer && dart test test/c_layer_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement the C layer and regenerate the bindings.**
- [ ] **Step 4: Run the package tests.** Run: `dart analyze --fatal-infos && dart test`. Expected: PASS. Push the branch and check that `libdivecomputer-build.yml` is green: the Windows job proves the thread shim.
- [ ] **Step 5: Commit.** `git commit -m "feat(libdc): the C layer between libdivecomputer's blocking I/O and Dart"`

### Task 5: Envelope, dive id, parsing and mapping

**Files:**
- Create: `packages/libdivecomputer/lib/src/envelope.dart`, `lib/src/dive_id.dart`, `lib/src/parser_version.dart`
- Create: `lib/src/parse/parsed_dive.dart` (plain data), `lib/src/parse/parse_dive.dart` (FFI)
- Create: `lib/src/mapping/map_dive.dart`, `lib/src/mapping/resample.dart`, `lib/src/mapping/events.dart`
- Test: `test/envelope_test.dart`, `test/dive_id_test.dart`, `test/mapping_test.dart`, `test/resample_test.dart`, `test/parse_dive_test.dart`

**Interfaces:**
- Consumes: `ConvertedDive`, `Dive`, `SampleSet`, `DiveEvent`, `DiveEventType`, `DiveGasMix`, `DiveTank`, `TankUsage`, `DiveMode`, `DecoModel`, `ShearwaterModel` from `subsurface_core`.
- Produces:
  - `class LibdcEnvelope`: `pinnedCommit`, `vendor`, `product`, `family`, `descriptorModel`, `int? devinfoModel`, `int? devinfoFirmware`, `int? devinfoSerial`, `int? devtime`, `int? systime`, `Uint8List fingerprint`, `Uint8List data`. It has `Uint8List encode()` and `static LibdcEnvelope decode(Uint8List)`. The layout is big-endian: `'ALDC'`, `u8 1`, then `pinnedCommit`, `vendor` and `product`, each as `u8 length` plus UTF-8. Then `u32 family`, `u32 descriptorModel`, `u8 flags` (bit 0: device info present; bit 1: clock present), `u32 devinfoModel`, `u32 devinfoFirmware`, `u32 devinfoSerial`, `u32 devtime`, `i64 systime`, `u16 length` plus the fingerprint, and `u32 length` plus the data. Absent values are 0, with their flag clear. `decode` throws `FormatException` on a bad magic, a newer version or truncated input.
  - `String libdcDiveId({required String vendor, required int serial, required Uint8List fingerprint})` (Global Constraints).
  - `const int kLibdcParserVersion = 1;`, with a doc comment listing the history, starting with "1 = first mapping (phase 2)".
  - `LibdcParsedDive` holds the parser output as nullable Dart values:
    - `wallClock` (the `dc_datetime_t` fields as a UTC `DateTime`), `timezoneSeconds` (null for `DC_TIMEZONE_NONE`), `diveTimeSeconds`, `maxDepthM`, `atmosphericBar`, `salinity`;
    - `gasMixes` (O2 and He fractions, usage) and `tanks` (gas mix index, volume, work, begin and end pressure, usage);
    - `diveMode` and `decoModel` (type, `gfLow`, `gfHigh`);
    - `rows`: a `List<LibdcSampleRow>`, one per `TIME`. Each row has `timeMs` and nullable `depthM`, `temperatureC`, `ppo2Voted`, `cells` (`Map<int, double>`), `setpoint`, `cns`, `deco` (type, time, depth, TTS), `gasMix`, `pressures` (`Map<int, double>`), plus its `events` (type, flags, value).
  - `LibdcParsedDive parseDive(LibdcEnvelope e)`:
    1. Finds the descriptor by vendor and product, otherwise by family and model (amendment 5).
    2. Calls `dc_parser_new2` and reads each field (`UNSUPPORTED` gives null).
    3. Collects the samples through `dc_parser_samples_foreach` with a `NativeCallable.isolateLocal`.
    4. Throws `LibdcParseException(LibdcStatus)` on any other failure.

    It runs on whichever isolate calls it.
  - `enum LibdcStatus` mirrors `dc_status_t`. It has `static LibdcStatus fromCode(int)`; an unknown code maps to `io`.
  - `ConvertedDive mapLibdcDive(LibdcParsedDive p, LibdcEnvelope e, {required String diveId})`. Sample units follow `DiveConverter.convert`; read it first.
    - **Identity:**
      - `id` = `diveId`; `dcSerial` = `e.devinfoSerial ?? 0`; `dcDiveNumber` = 0; `dcFingerprint` = hex of `e.fingerprint` (Task 8 adds the field; until then leave it out).
      - `dcVendor`/`dcProduct` = the envelope's; `dcFamily` = `e.family`; `dcModelCode` = `e.devinfoModel ?? e.descriptorModel`.
      - `dcModel` = `ShearwaterModel.unknown`; `logVersion` = 0; `sensorCalibration` = `[]`; stack times null.
    - **Time:**
      - `startTime` = `wallClock`; `utcOffsetMinutes` = `timezoneSeconds ~/ 60`.
      - `duration` = `diveTimeSeconds`, or the last row's time when absent; `endTime` = start + duration.
      - A missing `wallClock` throws `LibdcParseException(dataFormat)`.
    - **Header:**
      - `maxDepthMeters` = `maxDepthM`, or the deepest sample.
      - `diveMode`: CCR → `cc`, SCR → `sc`, OC → `ocTec`, GAUGE → `gauge`, FREEDIVE → `freedive`. When absent: `cc` if any row has a setpoint above 0, otherwise `ocTec`.
      - `decoModel`: BUHLMANN → `gf`, with `gfLow`/`gfHigh` when given, otherwise 0/0. VPM → `vpmb`. DCIEM → `dciem`. RGBM, NONE or absent → `gf` with 0/0.
      - `atmosphericPressureMbar` = `round(atmosphericBar × 1000)`, or 1013.
      - `waterDensityKgM3` = the salinity's density when above 0, otherwise 1000 for fresh water and 1030 for salt water; 1020 when absent.
      - `gasMixes`: rounded O2 and He percentages, with `isDiluent` for usage DILUENT. Mixes with usage OXYGEN are left out, and the sample gas index skips over them; a row that points at one keeps the previous index.
      - `tanks`: `DiveTank(slot: i, usage: from the tank usage, name: '', serial: 0, beginPressureBar, endPressureBar, pressureMaxBar: rounded work pressure, pressureReserveBar: 0)`.
    - **Samples:** onto a fixed grid (`resample.dart`).
      - The interval is the most common positive gap between row times, and the grid runs from 0 ms to the last row's time.
      - Depth is interpolated linearly between the nearest rows that have a depth. Every other channel carries its last value forward: temperature, voted ppO2, cells, setpoint, CNS, deco, gas index and tank pressures.
      - `ppo2Bar` = the voted value, otherwise the median of the cells at that point, otherwise 0. `cellPpo2Bar` has one channel per cell index seen, 0 to 3. `cellMv0`–`cellMv2` are zero-filled.
      - Deco: `decoStopDepthMeters` = the depth for DECOSTOP and DEEPSTOP, 0 otherwise; `decoTimeSeconds` = the deco time; `ttsSeconds` = TTS.
      - `statusFlags` are 0, as in the Subsurface mapper.
    - **Events,** at their exact row times (`events.dart`):
      - A change of the `GASMIX` sample becomes `gasSwitch`, with the new index as value.
      - A setpoint change of 0.05 bar or more becomes `setpointChange`, with `round(setpoint × 100)` as value.
      - Event BOOKMARK becomes `bookmark`; CEILING and CEILING_SAFETYSTOP become `ceilingViolation`; ASCENT becomes `ascentWarning`; DECOSTOP, DEEPSTOP and VIOLATION become `decoWarning`; every other event becomes `other`.
      - Every event keeps `rawType` = the libdivecomputer event type. A value outside int32 becomes null.

- [ ] **Step 1: Write the failing tests.**

  ```dart
  // envelope_test.dart
  test('round-trips every field, with and without device info and clock', ...);
  test('golden bytes for one envelope', ...);                 // pins the layout
  test('a bad magic, version 2 or truncated input throws FormatException', ...);
  // dive_id_test.dart
  test('libdcDiveId hashes "libdc:<vendor>:<decimal serial>:<lower hex>" and keeps 32 hex', ...);
    // vendor 'Divesoft', serial 1234567, fingerprint [0xDE,0xAD,0xBE,0xEF]
    // → sha256('libdc:Divesoft:1234567:deadbeef').substring(0, 32)
  // resample_test.dart
  test('rows every 10 s land on a 10 s grid unchanged', ...);
  test('a missing sample is interpolated for depth and carried forward for the rest', ...);
  test('setpoint and gas logged only on change are carried forward', ...);
  test('the interval is the most common gap, not the smallest', ...);     // gaps 4,4,4,1 s → 4 s
  // mapping_test.dart
  test('four cells give four cellPpo2Bar channels and ppO2 is their median when not voted', ...);
  test('voted ppO2 wins over the cells', ...);
  test('no time zone leaves utcOffsetMinutes null; +02:00 gives 120', ...);
  test('wall clock is stored as if UTC whatever the zone', ...);          // 2026-06-01 09:30:00 → DateTime.utc(2026,6,1,9,30)
  test('no serial gives dcSerial 0', ...);
  test('dive modes map as the table says; none with a setpoint is cc, without is ocTec', ...);
  test('an OXYGEN-usage mix is left out and the gas indexes skip it', ...);
  test('diluent and bailout mixes keep their order and isDiluent', ...);
  test('gas and setpoint changes become events at their row times', ...);
  test('a bookmark keeps rawType; an event value beyond int32 becomes null', ...);
  test('Shearwater-only fields stay empty: mV zero-filled, no calibration, no stack times', ...);
  test('a dive without a wall clock is a dataFormat failure', ...);
  // parse_dive_test.dart (native)
  test('parseDive of garbage data throws LibdcParseException, never crashes', ...);
  test('parseDive finds the descriptor by name even when the family number differs', ...);
  ```

- [ ] **Step 2: Run them and check they fail.** Run: `cd packages/libdivecomputer && dart test`. Expected: FAIL.
- [ ] **Step 3: Implement the interfaces above.**
- [ ] **Step 4: Run the package tests.** Run: `dart analyze --fatal-infos && dart test`. Expected: PASS.
- [ ] **Step 5: Commit.** `git commit -m "feat(libdc): envelope, dive id and the mapping into ConvertedDive"`

### Task 6: The download session, recording and replay

**Files:**
- Create: `packages/libdivecomputer/lib/src/download/ble_link.dart` (`LibdcBleLink`), `lib/src/download/download.dart`, `lib/src/download/download_isolate.dart`, `lib/src/download/events.dart`
- Create: `lib/src/recording/recording.dart`
- Move: `/Users/egbert/Dev/CCRLog/extract_libdc_log.py` → `tool/extract_libdc_log.py` (repo root), with a header that points at `LibdcRecording.parse`
- Test: `packages/libdivecomputer/test/download_test.dart`, `test/recording_test.dart`, `test/support/trace_link.dart`

**Interfaces:**
- Consumes: Task 4's C API, Task 5's `LibdcEnvelope`, `parseDive`, `mapLibdcDive` and `libdcDiveId`.
- Produces:

  ```dart
  abstract class LibdcBleLink {
    String get advertisedName;
    Stream<Uint8List> get notifications;
    Future<void> write(Uint8List bytes);
    Future<Uint8List> readCharacteristic(String uuid);
    Future<void> writeCharacteristic(String uuid, Uint8List bytes);
    Future<void> get disconnected;                      // amendment 4
  }
  // How the download reaches the computer. Phase 3 (cable and classic Bluetooth, the
  // Garmin/cable session) adds LibdcSerialConnection(String port), opened with
  // dc_serial_open inside the download isolate; nothing else in this API changes.
  sealed class LibdcConnection {}
  final class LibdcBleConnection extends LibdcConnection { final LibdcBleLink link; }
  class LibdcDownload {
    static LibdcDownload start({required LibdcDescriptor descriptor, required LibdcConnection connection,
        Map<int, Uint8List> knownFingerprints = const {}, bool record = false});
    static LibdcDownload replay({required LibdcDescriptor descriptor, required LibdcRecording recording,
        Map<int, Uint8List> knownFingerprints = const {}});
    Stream<LibdcDownloadEvent> get events;   // single subscription; LibdcFinished is last
    void cancel();
  }
  sealed class LibdcDownloadEvent {}
  class LibdcProgress    { final int current, maximum; }
  class LibdcDeviceInfo  { final int model, firmware, serial; }
  class LibdcDiveDownloaded { final LibdcEnvelope envelope; final String diveId;
                              final ConvertedDive? converted; final LibdcStatus? parseError; }
  class LibdcFinished    { final LibdcStatus status; final LibdcRecording recording; }  // always present
  class LibdcRecording {
    // events is empty unless record was set; header, log and envelopes are always filled,
    // so a failed download can be shared too (spec section 9)
    final List<String> header; final List<LibdcIoEvent> events; final List<String> log;
    final List<LibdcEnvelope> envelopes;
    String toText();                          // the format below
    static LibdcRecording parse(String text); // this format, or a .combined.txt trace
    Uint8List toReplayEvents();               // Task 4's packed layout
  }
  ```

- Main isolate, for a `LibdcBleConnection`:
  1. Creates the live link with a `NativeCallable<al_request_fn>.listener`. For each request, it reads `al_link_pending` and calls `link.write`, `readCharacteristic` or `writeCharacteristic`, then `al_link_complete` with `SUCCESS`, or `IO` when that call throws.
  2. Forwards every notification to `al_link_push`, and calls `al_link_disconnected` when `link.disconnected` completes.
  3. Spawns the download isolate with the link's address, the descriptor's four fields, `knownFingerprints`, `record` and a `SendPort`.
  4. After `LibdcFinished`, closes the listener and frees the link once the isolate has exited.

  One isolate per download.
- Download isolate:
  1. Calls `dc_context_new`. The log function collects lines (INFO when recording, WARNING otherwise).
  2. Opens the iostream with `al_link_iostream`, then calls `dc_device_open` with the descriptor it finds by name.
  3. Calls `dc_device_set_cancel(al_link_cancelled, link)` and `dc_device_set_events` for DEVINFO, PROGRESS and CLOCK, with a `NativeCallable.isolateLocal`. On DEVINFO it posts `LibdcDeviceInfo` and, when `knownFingerprints[serial]` exists, passes it to `dc_device_set_fingerprint` (amendment 7).
  4. Calls `dc_device_foreach` with an isolate-local dive callback. The callback builds the envelope from the device info, the clock, the fingerprint and a copy of the data. It runs `parseDive` and `mapLibdcDive` inside a `try`, posts `LibdcDiveDownloaded`, and returns 1. On failure, `parseError` is the parser's status, or `dataFormat` when the mapping threw.
  5. Closes the device and the context, then posts `LibdcFinished` with the `foreach` status and the recording. The recording holds header lines for the descriptor, the advertised name and `kLibdcPinnedCommit`, the log, every envelope, and the packed I/O events when `record` is set.
- The dive id is `libdcDiveId(vendor: descriptor.vendor, serial: devinfo serial or 0, fingerprint)`.
- Recording text. The app adds more `#` header lines in Task 12. Every `W`, `R` and `C` line uses `.combined.txt`'s `W (<n> bytes): <hex>` form, so one reader handles both:

  ```
  # Anchorline download recording 1
  # descriptor <vendor>|<product>|<family>|<model>
  # advertised <name>
  # libdivecomputer <commit>
  [12.345678] W (10 bytes): 01 00 ff ...
  [12.401002] R (18 bytes): 01 00 01 ...
  [13.000000] P input 40 bytes dropped
  [13.100000] C read 00002a29-0000-1000-8000-00805f9b34fb (8 bytes): ...
  [13.200000] S 300 | T 3000 | I <request hex> unsupported | X configure 115200 8N1
  # log
  <libdivecomputer log lines>
  # envelope <base64 of LibdcEnvelope.encode()>      (one line per dive)
  # end
  ```

- [ ] **Step 1: Write the failing tests.** The Petrel 3 trace (`../../test/fixtures/raw/subsurface2.combined.txt`, read in place, not copied) is the only real download we hold. These tests use it through libdivecomputer's own `Shearwater|Petrel 3` descriptor, for the session's mechanics. `TraceLink` (test support) is a `LibdcBleLink` that answers each write with the `R` packets recorded after the matching `W`.

  ```dart
  // recording_test.dart
  test('parse reads the .combined.txt trace into W and R events in order', ...);  // 3101 writes
  test('toText then parse gives the same events, header, log and envelopes', ...);
  // download_test.dart
  test('replay of the Petrel 3 trace: device info first, then 8 dives, then success', ...);
  test('every dive carries its envelope, its id and a converted dive', ...);
  test('progress only rises', ...);
  test('a known fingerprint for the serial stops at that dive', ...);   // the 3rd dive's → 2 dives
  test('cancel mid-download ends with CANCELLED after the dives already posted', ...);
  test('a trace cut halfway ends with an error status and keeps the dives before it', ...);
  test('the live path through TraceLink gives the same dives as the replay', ...);
  test('a link that drops halfway ends with IO; the dives before it arrived', ...);
  test('with record: true the recording parses and replays to the same dives', ...);
  ```

  If the trace doesn't replay strictly in order against upstream's Shearwater driver, report the first diverging write to Egbert before loosening anything.
- [ ] **Step 2: Run them and check they fail.** Run: `cd packages/libdivecomputer && dart test test/download_test.dart test/recording_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement the interfaces above.**
- [ ] **Step 4: Run the package tests.** Run: `dart analyze --fatal-infos && dart test`. Expected: PASS. Push the branch and check that `libdivecomputer-build.yml` is green on every platform.
- [ ] **Step 5: Commit.** `git commit -m "feat(libdc): download on its own isolate, with recording and replay"`

### Task 7: The Petrel 3 cross-check, the output guard and the checked-family procedure

**Files:**
- Create: `packages/libdivecomputer/test/petrel3_cross_check_test.dart`, `test/output_guard_test.dart`
- Create: `packages/libdivecomputer/test/fixtures/README.md`, `test/fixtures/petrel3_expected.json`
- Test: the two files above

**Interfaces:**
- Consumes: Task 6's `LibdcDownload.replay`. The app's Dart Shearwater reader isn't importable from the package, so the cross-check compares against `petrel3_expected.json`. Generate that file once from the Dart reader with a throwaway test in the app, `ShearwaterDiveParser` plus `DiveConverter.convert` over the same trace, and commit it with the command that made it.
- Produces:
  - `petrel3_expected.json`: per dive, the start time, duration, max depth, gas mixes, sample count and interval, and the depth, temperature, voted ppO2 and setpoint arrays, all as the Dart reader gives them.
  - `fixtures/README.md` says how a family becomes checked. A real recording is anonymised the way #191 did it. The expected output is compared by a person with what the computer itself or Subsurface shows. Then a replay test like this one is added, and the family plus the fixture name go into `kCheckedLibdcFamilies` (Task 12).

- [ ] **Step 1: Write the tests.**

  ```dart
  test('libdivecomputer and the Dart reader agree on every Petrel 3 dive', ...);
    // start time, duration ±1 s, max depth ±0.01 m, gas mixes equal; depth ±0.01 m and
    // temperature ±0.1 °C on every grid point; voted ppO2 and setpoint ±0.01 bar.
    // Any other difference is listed in the test's doc comment as a finding, with the field.
  test('dc_parser_new and dc_parser_new2 give the same dive', ...);
    // replay once with dc_parser_new inside the foreach callback and compare. If they differ,
    // mark the test skip with the difference and tell Egbert: it is a finding for Jef.
  test('mapping output matches the digests for kLibdcParserVersion', ...);
    // one SHA-256 per replayed dive over its fields, sample arrays (raw bytes) and events;
    // on mismatch: "libdivecomputer mapping output changed: bump kLibdcParserVersion and update these digests".
  ```

- [ ] **Step 2: Run them.** Run: `cd packages/libdivecomputer && dart test`. Expected: PASS. A difference from the Dart reader is either a mapping bug, which you fix in Task 5's code, or a known difference between the two Shearwater parsers (PR #213 lists four), which you document. Never widen a tolerance to make a mapping bug pass.
- [ ] **Step 3: Commit and open PR B.** `git commit -m "test(libdc): cross-check a replayed Petrel 3 download against the Dart reader"`

---

## PR C — Sync readiness

### Task 8: Migration 0028 and the fingerprint rule

**Files:**
- Create: `supabase/migrations/0028_dive_fingerprint.sql`, `supabase/checks/0028_dive_fingerprint.sql`
- Modify: `lib/sync/cloud/powersync_schema.dart`, `lib/data/db/tables.dart`, `lib/data/db/database.dart` (schemaVersion 21 → 22), `lib/data/db/database.g.dart` (regenerated)
- Modify: `packages/subsurface_core/lib/data/models/dive.dart` (`String? dcFingerprint`)
- Modify: `lib/data/db/dive_dao.dart`, `lib/data/db/dive_dao_refresh.dart`, `lib/data/import/same_dive_matcher.dart`
- Test: `test/sync/cloud/powersync_schema_test.dart`, `test/data/db/migration_test.dart`, `test/data/import/same_dive_matcher_test.dart`, `test/data/db/dive_refresh_test.dart`

**Interfaces:**
- Produces:
  - 0028: `alter table public.dives add column if not exists dc_fingerprint text;`, the grants restated for `dives`, and `NOTIFY pgrst, 'reload schema';`. The check script inserts and reads back a row with the column inside a transaction that rolls back.
  - `dc_fingerprint` (text) in `appSchema` and the Drift `Dives` table. It's mapped in `rowToDive`, written by `importDive`, and written by a download refresh. `refreshFromRawBlob` keeps it.
  - `StoredDiveKey` gains `String? dcFingerprint`. `findSameDive` gains `String? fingerprint`. When the incoming dive has one, a stored row with `dcFingerprint` set matches only if it is equal. Rows without one (Subsurface copies, Shearwater) keep today's rule. `alreadyDownloadedAmong` passes it through.
  - A refresh never changes a stored `dc_family` that is already set. Only a copy's NULL may become set, and then `dives`, `dive_samples` and `dive_bailout_carry` change in the one transaction (phase 1 already does this). A refresh whose engine differs from the stored row's writes nothing, including the raw blob. That settles the phase 1 note about `unchanged` on an engine mismatch.

- [ ] **Step 1: Write the failing tests.**

  ```dart
  test('appSchema has dives.dc_fingerprint as text', ...);
  test('v21 → v22 adds dc_fingerprint', ...);
  test('two libdc dives from one computer 30 s apart both import', ...);
    // same vendor and serial, dcDiveNumber 0, fingerprints aa.. and bb..: two inserts, two ids
  test('downloading both again changes nothing', ...);                 // ImportOutcome.unchanged twice
  test('a libdc download refreshes a matching Subsurface copy and stores its fingerprint', ...);
  test('a refreshed copy is matched again by its fingerprint, not by the window alone', ...);
  test('a refresh never changes a set dc_family; a copy that becomes libdc moves dive, samples and carry together', ...);
  test('an engine mismatch writes no raw blob', ...);
  ```

- [ ] **Step 2: Run them and check they fail.** Run: `flutter test test/sync/cloud/powersync_schema_test.dart test/data/db test/data/import`. Expected: FAIL.
- [ ] **Step 3: Implement the interfaces above.** Run `dart run build_runner build --delete-conflicting-outputs`. Run `./supabase/lint_migrations.sh`, then dry-run 0001–0028 plus the check script in a local `postgres:17-alpine`, as phase 1 did.
- [ ] **Step 4: Run all tests.** Run: `flutter analyze && flutter test && (cd packages/subsurface_core && dart test)`. Expected: clean, all pass.
- [ ] **Step 5: Commit.** `git commit -m "feat(sync): store the libdivecomputer fingerprint and match downloads by it"`
- [ ] **Step 6 (Egbert): apply 0028 and run its check before PR C merges.**

### Task 9: The Subsurface writer skips libdc dives; builds send `dc_engines: 2`

**Files:**
- Modify: `packages/subsurface_core/lib/sync/subsurface_git/sync_inputs.dart` (`SubsurfaceDiveInput.dcFamily`)
- Modify: `packages/subsurface_core/lib/sync/subsurface_git/sync_planner.dart`
- Modify: `lib/sync/subsurface_git/drift_sync_inputs.dart`, `lib/sync/subsurface_git/sync_orchestrator.dart` (result field only; the safety hold stays untouched)
- Modify: `lib/ui/widgets/subsurface_sync_section.dart`
- Modify: `lib/sync/cloud/sync_params.dart`
- Test: `packages/subsurface_core/test/sync/subsurface_git/sync_planner_test.dart`, `test/sync/subsurface_git/sync_orchestrator_test.dart`, `test/sync/cloud/cloud_sync_coordinator_test.dart`, `test/ui/widgets/subsurface_sync_section_test.dart`

**Interfaces:**
- Produces:
  - The planner leaves out every bundle whose `dive.dcFamily != null`, before any matching or numbering, and counts them in `SyncPlanStats.otherBrandDives`. The rule lives in the shared planner, so the future server-side sync gets it too.
  - `SubsurfaceSyncResult.otherBrandDives`. Whenever it is above 0, the sync section shows: "N dives from other brands aren't sent to Subsurface Cloud yet. Anchorline only writes Shearwater dives there for now."
  - `kSyncConnectionParams = {'dc_engines': 2}`. The doc comment says 2 = this build reads libdivecomputer dives, and its Subsurface writer skips them.

- [ ] **Step 1: Write the failing tests.**

  ```dart
  test('the planner skips a dive with dcFamily set and counts it', ...);   // nothing written for it
  test('a Shearwater dive next to it is planned as before', ...);
  test('the orchestrator reports otherBrandDives', ...);
  testWidgets('the sync section says why other-brand dives are not sent', ...);
  test('connect passes {dc_engines: 2}', ...);                             // updates the phase 1 test
  ```

- [ ] **Step 2: Run them and check they fail.** Run: `(cd packages/subsurface_core && dart test test/sync) && flutter test test/sync test/ui/widgets/subsurface_sync_section_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement the interfaces above.**
- [ ] **Step 4: Run all tests.** Run: `flutter analyze && flutter test && (cd packages/subsurface_core && dart test)`. Expected: clean, all pass.
- [ ] **Step 5: Commit and open PR C.** `git commit -m "feat(sync): skip other brands in the Subsurface writer and ask for libdivecomputer rows"`. The PR description says it merges only after (1) 0028 is applied and checked and (2) Egbert confirms that `libdc_dives` is deployed and the fake-row check passed.

---

## PR D — Downloads in the app (the tester milestone)

### Task 10: The Bluetooth link and the per-family profiles

**Files:**
- Create: `lib/devices/libdc/libdc_ble_profile.dart`, `lib/devices/libdc/ble_central_libdc_link.dart`
- Modify: `lib/ble/ble_central.dart` (a doc line: the libdivecomputer import now uses this seam too)
- Modify: `NOTICE.md` (spec section 4: the UUIDs and Bluetooth facts taken from Subsurface's `core/qt-ble.cpp`)
- Test: `test/devices/libdc/libdc_ble_profile_test.dart`, `test/devices/libdc/ble_central_libdc_link_test.dart` (with a fake `BlePeripheral` and GATT table)

**Interfaces:**
- Consumes: `BleCentral`, `BlePeripheral`, `BleCharacteristic`, `chunkForWrite`, `normalizeBleUuid` from `lib/ble/ble_central.dart`. `LibdcBleLink` from the package.
- Produces:
  - `class LibdcBleProfile { List<String> preferredServices; List<String> ignoreForRead; List<String> ignoreForWrite; LibdcFlowControl flowControl; }` and `LibdcBleProfile libdcProfileFor(LibdcDescriptor d)`. The facts come from Subsurface's `qt-ble.cpp`, implemented here rather than translated:
    - Known serial services, in priority order: `0000fefb-…` (HW, Telit), `2456e1b9-26e2-8f83-e744-f34f01e9d701` (HW, u-blox), `544e326b-5b72-c6b0-1c46-41c1bc448118` (Mares), `98ae7120-e62e-11e3-badd-0002a5d5c51b` (Suunto), `cb3c4555-d670-4670-bc20-b61dbc851e9a` and `ca7b0001-f785-4c38-b599-c7c5fbadb034` (Pelagic), `fdcdeaaa-295d-470e-bf15-04217b7aa0a0` (Scubapro), `0000fcef-…` (Divesoft), `6e400001-b5a3-f393-e0a9-e50e24dc10b8` (Cressi, before Nordic), `6e400001-b5a3-f393-e0a9-e50e24dcca9e` (Nordic UART), `00000001-8c3b-4f2c-a59e-8c08224f3253` (Halcyon), `84968ffe-d26d-478a-b953-5010bcf58bca` (Seac).
    - Services never used: `00001530-1212-efde-1523-785feabcd123` and `9e5d1e47-5c13-43a0-8635-82ad38a1386f` (firmware upgrade).
    - Characteristics never read from: `00000101-8c3b-4f2c-a59e-8c08224f3253` (Halcyon). Never written to: `00000201-8c3b-4f2c-a59e-8c08224f3253` (Halcyon). Neither: `49535343-6daa-4d02-abf6-19569aca69fe`, `49535343-aca3-481c-91ec-d85e28a60318`, `49535343-026e-3a9b-954c-97daef17e26e`, `49535343-4c8a-39b3-2f49-511cff073b7e` (McLean).
    - `LibdcFlowControl.telitCredits` for HW: on the Telit service, data comes in on `00000002-0000-1000-8000-008025000000`, is written to `…0001…`, credits go out on `…0003…` (written with response), and credits come in on `…0004…` (indications). On u-blox, data is `2456e1b9-26e2-8f83-e744-f34f01e9d703` and credits are `…d704`. At connect the link grants 254 credits. Each data packet uses one. When 32 are left it grants 222 more. Packets from any other characteristic are dropped.
    - Choosing the GATT, for a family with or without its own profile: skip upgrade services, and skip standard 16-bit services unless known. Take the known serial service of highest priority, otherwise the first remaining service with a notify-or-indicate characteristic and a write characteristic that aren't ignored.
  - `class BleCentralLibdcLink implements LibdcBleLink`:
    - `static Future<BleCentralLibdcLink> connect(BleCentral central, String deviceId, {required String advertisedName, required LibdcBleProfile profile})` does the following in order:
      1. Connects with a 15 s timeout.
      2. Calls `requestMtu(517)`, which does nothing outside Android.
      3. Discovers services and chooses the GATT.
      4. Turns on notifications. If that throws on Windows, it calls `pair()` and retries once.
      5. Sets up the credits.
    - `write` chunks the bytes to `maxWritePayload` and writes without response when the characteristic supports that, with response otherwise, in order.
    - `readCharacteristic` and `writeCharacteristic` throw `UnsupportedError` until Task 18, which the C layer turns into `UNSUPPORTED`.
    - `List<String> get gattSummary`: one line per service and characteristic, with its properties, for the recording.
    - `Future<void> close()`: time-bounded at 3 s, and idempotent.

- [ ] **Step 1: Write the failing tests.**

  ```dart
  test('Divesoft: the fcef service is chosen over a Nordic UART on the same device', ...);
  test('Halcyon: the Rx/Tx characteristics Subsurface skips are never used', ...);
  test('an unknown vendor service with notify and write is chosen; upgrade and standard services are not', ...);
  test('HW Telit: 254 credits at connect, 222 more after 222 packets, other characteristics dropped', ...);
  test('HW u-blox: the same credit rule on d704, data on d703', ...);
  test('a write longer than the payload is chunked in order; without-response when supported', ...);
  test('a dropped connection completes disconnected', ...);
  test('Windows: a notify failure triggers pair() once, then retries', ...);
  ```

- [ ] **Step 2: Run them and check they fail.** Run: `flutter test test/devices/libdc`. Expected: FAIL.
- [ ] **Step 3: Implement the interfaces above.**
- [ ] **Step 4: Run them and check they pass.** Same command. Expected: PASS.
- [ ] **Step 5: Commit.** `git commit -m "feat(devices): a libdivecomputer Bluetooth link over BleCentral, with per-family profiles"`

### Task 11: The libdivecomputer download source

**Files:**
- Create: `lib/devices/libdc/libdc_download_source.dart`, `lib/devices/fingerprint_store.dart`
- Modify: `lib/devices/dive_download_source.dart` (`DiveSourceFinished`)
- Modify: `lib/data/db/import_state_dao.dart` (`fingerprintsWithPrefix`, `implements FingerprintStore`)
- Modify: `packages/libdivecomputer/lib/src/mapping/map_dive.dart` (set `dcFingerprint` now that Task 8 added it; update the Task 7 digests in the same commit)
- Test: `test/devices/libdc/libdc_download_source_test.dart`, `test/data/db/import_state_dao_test.dart`, `packages/libdivecomputer/test/mapping_test.dart`

**Interfaces:**
- Consumes: `LibdcDownload`, `LibdcDescriptor`, `LibdcBleLink`, `kLibdcParserVersion`, `DiveDownloadSource`, `DcIdentity`.
- Produces:
  - `class DiveSourceFinished extends DiveSourceEvent { final String? importStateKey; final Uint8List? fingerprintToKeep; final String? recordingText; }`. Shearwater never emits it.
  - `abstract interface class FingerprintStore { Future<Map<String, Uint8List>> withPrefix(String prefix); }`. `ImportStateDao.fingerprintsWithPrefix(String prefix)` backs it.
  - `class LibdcDownloadSource implements DiveDownloadSource`. Its constructor takes `{required LibdcDescriptor descriptor, required LibdcConnection connection, required Future<void> Function() closeConnection, FingerprintStore? fingerprints, bool record = false, LibdcDownload Function({...})? starter}`. `fingerprints: null` means "Download everything again". `starter` is the test seam and defaults to `LibdcDownload.start`. Nothing in the source is Bluetooth-specific, so phase 3 reuses it for serial.
    - `canListDives` is false, and `listDives` throws `UnsupportedError`.
    - `download()` ignores `selection` and `sinceFingerprint` (documented). It loads `withPrefix('libdc:${family}:')` and turns the keys into `Map<int serial, Uint8List>`. Then it maps the package's events:
      - `LibdcDeviceInfo` becomes `DiveSourceIdentified(DcIdentity(vendor: descriptor.vendor, product: descriptor.product, serial, family: descriptor.family, modelCode: model, firmware, dcModel: ShearwaterModel.unknown, computerModel: 0, importStateKey: 'libdc:<family>:<serial>', modelLabel: '<vendor> <product>', serialLabel: '<serial>', firmwareLabel: '<firmware>'))`.
      - `LibdcProgress` becomes `DiveSourceProgress(diveIndex: dives so far, totalDives: null, diveBytes: current, diveTotalBytes: maximum)`.
      - `LibdcDiveDownloaded` with a converted dive becomes `DiveSourceDive(listing: null, converted, rawBlob: envelope.encode(), fingerprint, parserVersion: kLibdcParserVersion)`. With a parse error it becomes `DiveSourceDiveFailed(error: LibdcDiveParseFailed(status))`.
      - `LibdcFinished` becomes `DiveSourceFinished`, whose `fingerprintToKeep` is the first dive's fingerprint when the status is `success` or `done`, and null otherwise, and whose `recordingText` is `recording.toText()`. When the status is anything other than `success`, `done` or `cancelled`, the stream then fails with `LibdcDownloadFailed(status)`.
    - A dive that arrives before any device info gets serial 0 and the key `libdc:<family>:0`.
    - `close()` cancels the download and calls `closeConnection`. It is idempotent and time-bounded at 3 s.

- [ ] **Step 1: Write the failing tests.** These use a fake `starter` emitting scripted events, plus one test over the real replay of the Petrel trace through `LibdcDownload.replay`.

  ```dart
  test('device info gives DiveSourceIdentified with the libdc key and labels', ...);
  test('a dive gives DiveSourceDive with the envelope as raw blob and kLibdcParserVersion', ...);
  test('a parse error gives DiveSourceDiveFailed and the next dive still arrives', ...);
  test('a clean finish keeps the newest dive\'s fingerprint; a cancel or IO keeps none', ...);
  test('IO after two dives: two dives, Finished without fingerprint, then the stream fails', ...);
  test('saved fingerprints for the family are passed by serial', ...);   // keys libdc:<f>:1, libdc:<f>:2
  test('fingerprints: null passes none (download everything again)', ...);
  test('a dive before device info uses serial 0', ...);
  test('fingerprintsWithPrefix returns only matching keys', ...);
  // mapping_test.dart
  test('the mapped dive carries the fingerprint as lower-case hex', ...);
  ```

- [ ] **Step 2: Run them and check they fail.** Run: `flutter test test/devices/libdc test/data/db/import_state_dao_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement the interfaces above.**
- [ ] **Step 4: Run them and check they pass.** Same command. Expected: PASS.
- [ ] **Step 5: Commit.** `git commit -m "feat(devices): the libdivecomputer download source, with its own fingerprints"`

### Task 12: Scan, picker, tiers, recording and sharing on the import screen

**Files:**
- Create: `lib/devices/libdc/libdc_tiers.dart`, `lib/devices/libdc/download_share.dart`, `lib/ui/widgets/libdc_model_picker.dart`
- Modify: `lib/ui/notifiers/import_notifier.dart`, `lib/ui/screens/import_screen.dart`
- Test: `test/ui/notifiers/import_notifier_test.dart`, `test/ui/screens/import_screen_test.dart`, `test/devices/libdc/libdc_tiers_test.dart`, `test/devices/libdc/download_share_test.dart`

**Interfaces:**
- Consumes: Tasks 10–11. `defaultBleCentral()`. `Libdc.matchBle`, `Libdc.descriptors`. `ImportStateDao`. `share_plus`.
- Produces:
  - `const Map<int, String> kCheckedLibdcFamilies = {};` (family → fixture path under `packages/libdivecomputer/test/fixtures/`) and `bool isCheckedLibdcFamily(int family)`. The test fails if a listed family has no fixture file.
  - The notifier takes `BleCentral? central`, defaulting to `defaultBleCentral()`. One scan runs through `central.scan()` with no service filter, for 15 s. Each result becomes an `ImportScanResult { String id; String name; ImportDeviceKind kind; List<LibdcDescriptor> candidates; }`:
    - `shearwater` when it advertises `shearwaterServiceUuid`, except on Windows, where these stay unlisted as today.
    - Otherwise `libdc` when `Libdc.matchBle(name)` isn't empty.
    - Otherwise `unmatched`, when it has a name.

    `discoveredDevices` becomes `List<ImportScanResult>`. `selectRealDevice` stays the Shearwater path, given `BluetoothDevice.fromId(result.id)`. The mock flow stays.
  - `Future<void> selectLibdcDevice(ImportScanResult r, LibdcDescriptor d)` connects through `BleCentralLibdcLink`, builds the source, and goes from connecting straight to downloading: there is no manifest step. The wakelock is on during the download, as for Shearwater. When a name matches several models of one family, the first candidate is used: the family decides the protocol, and the model comes from the device info (spec section 5). `forceFullReimport` becomes "Download everything again" (`fingerprints: null`). `bool recordNextDownload` defaults to false. The `import_completed` and `import_failed` usage events gain `engine` (`shearwater` or `libdc`) and `vendor`.
  - In `downloadAll`, `DiveSourceFinished` saves `fingerprintToKeep` under `importStateKey` only when `_failedCount == 0`, and keeps `recordingText`. When a libdivecomputer download fails, the message is "Download stopped (<reason>). N dives saved." `reason` is a short English text per `LibdcStatus`: timeout → "the computer stopped answering", io → "the connection dropped", protocol → "unexpected data from the computer", cancelled → "cancelled", anything else → "error <name>".
  - Import screen:
    - The device list shows Shearwater and libdivecomputer devices. A libdivecomputer row shows `<vendor> <product>` and the advertised name, plus the badge "Not yet tested by us" when its family isn't checked. A name that matches several families opens a family picker. "My computer isn't listed" opens `LibdcModelPicker`: brands, then models, every BLE descriptor present except Shearwater, then a choice among the named devices seen.
    - Before connecting there is a switch, "Record this download".
    - During the download, the progress bar shows the bytes fraction, "N dives saved", and a Cancel button.
    - "Share this download" appears after every libdivecomputer download, including a failed one. The file always holds the log and the envelopes, plus the packets when recording was on.
  - `Future<void> shareDownload({required String recordingText, required List<String> extraHeader, Rect? origin})` writes `anchorline-download-<yyyymmdd-HHmmss>.txt` to the temporary directory. When the file is larger than 10 MB it is gzipped as `.txt.gz` instead. It opens the share sheet anchored at `origin`; on iPad and iOS the sheet needs that origin (#232). The extra header is the app version and build, the platform, and `gattSummary`. The share text, verbatim, with the address from "Before anything is built": "This file is a recording of your dive computer's download. It contains the dives on the computer, its serial number and any GPS positions it logged. Send it to recordings@anchorline.eu or attach it to an issue at github.com/Egbertdepauw/anchorline/issues so we can check your computer."
  - `README.md` gets a "Help us test your dive computer" section with the same ask.

- [ ] **Step 1: Write the failing tests.**

  ```dart
  // import_notifier_test.dart
  test('a Petrel and an OSTC in one scan: one shearwater, one libdc result', ...);
  test('a Shearwater name never becomes a libdc candidate', ...);
  test('an unnamed device is not listed; a named unmatched one is offered to the picker', ...);
  test('a libdc download skips the manifest and imports each dive', ...);
  test('the fingerprint is saved after a clean finish with no failures only', ...);
  test('a failed dive keeps the old fingerprint', ...);
  test('download everything again passes no fingerprints', ...);
  test('a failed libdc download says how many dives were saved', ...);
  // import_screen_test.dart
  testWidgets('an unchecked family shows "Not yet tested by us"', ...);
  testWidgets('a name matching two families asks which one', ...);
  testWidgets('the model picker lists brands and models without Shearwater', ...);
  testWidgets('Share this download appears after a recorded download and after a failure', ...);
  // libdc_tiers_test.dart
  test('every checked family has its fixture file', ...);
  // download_share_test.dart
  test('the share file has the header, the recording and the log; large files are gzipped', ...);
  ```

- [ ] **Step 2: Run them and check they fail.** Run: `flutter test test/ui test/devices/libdc`. Expected: FAIL.
- [ ] **Step 3: Implement the interfaces above.**
- [ ] **Step 4: Run all tests.** Run: `flutter analyze && flutter test`. Expected: clean, all pass.
- [ ] **Step 5: Commit.** `git commit -m "feat(import): download from other brands' Bluetooth computers, record and share a download"`

### Task 13: Other brands on the dive screens, and the documents

**Files:**
- Create: `lib/ui/util/dive_computer_labels.dart`
- Create: `packages/subsurface_core/lib/sync/subsurface_git/brand_serial.dart` (+ barrel export)
- Modify: `lib/ui/widgets/dive_information_section.dart`, `lib/ui/screens/dive_detail_screen.dart` (the model name)
- Modify: the CCR-only widgets on the dive screens that show mV, calibration or stack time, only where a test shows they don't already hide when empty
- Modify: `CLAUDE.md`, `docs/PROJECT_PLAN.md`, `docs/superpowers/specs/2026-06-04-multi-dc-driver-architecture-design.md` (spec section 13)
- Test: `test/ui/util/dive_computer_labels_test.dart`, `test/ui/screens/libdc_dive_screens_test.dart`, `test/data/db/cell_health_libdc_test.dart`, `packages/subsurface_core/test/sync/subsurface_git/brand_serial_test.dart`

**Interfaces:**
- Produces:
  - `int brandSerialOf({required int storedSerial, required String? vendor, required int parserVersion, required int? dcFamily})`. It returns `int.tryParse(storedSerial.toRadixString(16)) ?? storedSerial` for a non-Shearwater Subsurface copy (vendor set and not Shearwater, `dcFamily` NULL, `parserVersion == -1`), and `storedSerial` otherwise. It undoes the legacy hex reading of a decimal serial (phase 1 Task 7).
  - `String diveComputerName(Dive d)`: the existing Shearwater name when `dcFamily == null` and the vendor is null or Shearwater, otherwise `'<dcVendor> <dcProduct>'`. `String diveComputerSerialText(Dive d)`: 8 hex digits for Shearwater, as today, otherwise `brandSerialOf(...)` in decimal.
  - `CLAUDE.md`, as spec section 13 says. In the Tech stack, libdivecomputer is linked through FFI, pinned, and built by the hook in `packages/libdivecomputer/`. Under "Working in this project": the `dive_id` rule gains the libdivecomputer form, the package's purity and pin rules, and "imported data changes only through the refresh". Under "Out of scope", the "Anything not Shearwater" line is replaced with the Garmin and IrDA notes. `PROJECT_PLAN.md` points its "Phase 4 if at all" line at the 2026-11-15 design. The June draft's status becomes "Superseded in part by the 2026-11-15 libdivecomputer design".

- [ ] **Step 1: Write the failing tests.** Fixture dives are built with `mapLibdcDive` from synthetic parsed dives: a Divesoft CCR dive with 4 cells, a Ratio CCR dive with a setpoint only, and an OSTC OC dive.

  ```dart
  test('Divesoft Liberty shows as "Divesoft Liberty" with a decimal serial', ...);
  test('a Shearwater dive shows exactly as before', ...);                  // name and 8-digit hex
  test('a non-Shearwater copy shows its decimal serial', ...);             // stored 0x1234567 → '1234567'
  testWidgets('detail, information and statistics screens render a Divesoft dive with cells and no mV', ...);
  testWidgets('a Ratio setpoint-only CCR dive shows no cell views', ...);
  testWidgets('an OSTC OC dive renders like a Shearwater OC dive', ...);
  test('cell health never counts a dive without mV as cells at 0 mV', ...);  // mvSeriesForCell skips it
  ```

- [ ] **Step 2: Run them and check they fail.** Run: `flutter test test/ui test/data/db/cell_health_libdc_test.dart && (cd packages/subsurface_core && dart test)`. Expected: FAIL.
- [ ] **Step 3: Implement.** Hide what is empty, following how OC dives already hide the CCR fields. Don't restructure any screen.
- [ ] **Step 4: Run all tests.** Run: `flutter analyze && flutter test && (cd packages/subsurface_core && dart test) && (cd packages/libdivecomputer && dart test)`. Expected: clean, all pass.
- [ ] **Step 5: Commit and open PR D.** `git commit -m "feat(ui): show dives from other brands; update the project documents"`

### Task 14: The tester build (Egbert)

- [ ] **Step 1: Check that the gates hold.** PR C is merged (so 0028 is live and the deploy is confirmed), and PR D is merged.
- [ ] **Step 2 (Egbert): build** the next build number from `main`, following `docs/RELEASING.md`, for TestFlight, Play internal, the macOS website build, the Windows website build (the GitHub workflow) and the Linux AppImage (Docker). On each build, About shows the libdivecomputer line.
- [ ] **Step 3 (Egbert): Petrel 3 checks on the tester build. Shearwater must be unchanged.**
  1. The scan finds the Petrel, and only once.
  2. Download the new dives. They show the same profile as the store build.
  3. A forced full re-scan gives no duplicates, and the next scan shows nothing new.
  4. A second device on 1.1.0+48 still syncs these Shearwater dives.
  5. Subsurface sync pushes as before and reports no other-brand dives.
  6. Switch the Petrel off mid-transfer: "Connection lost" appears, and the next scan lists the same dives.
- [ ] **Step 4: Testers' checks** (Ratio, OSTC, Divesoft). Send them with the build.
  1. Before the first download, turn on "Record this download".
  2. Scan. The computer appears with "Not yet tested by us". If it doesn't, use "My computer isn't listed" and note what name appeared.
  3. Download. Compare the number of dives, their dates and times, maximum depths and durations with the computer's own log, or with Subsurface.
  4. Open three dives and check the depth profile, the temperature and the gas or setpoint.
  5. Download again: nothing new. Then "Download everything again": no duplicates.
  6. Signed in, on a second device if you have one: the dives arrive there.
  7. Tap "Share this download" and send the file, including after a failed download.
  8. Divesoft and OSTC CCR divers: note whether ppO2 looks right. Per-cell traces come in a later build (Task 17).
- [ ] **Step 5: Each recording that comes back** is anonymised and added as a replay fixture following `packages/libdivecomputer/test/fixtures/README.md`. Its family moves into `kCheckedLibdcFamilies` once a person has compared the output. One PR per family.

---

## PR E — After the testers start (independent PRs, any order)

### Task 15: Stand-ins for Halcyon Symbios, OSTC and Ratio

**Files:**
- Create: `test/devices/libdc/standins/fake_gatt_peripheral.dart`, `standins/halcyon_symbios.dart`, `standins/hw_ostc3.dart`, `standins/ratio_idive.dart`, `standins/README.md`
- Test: `test/devices/libdc/standins_test.dart`

**Interfaces:**
- Consumes: `BleCentralLibdcLink`, `LibdcDownloadSource` and the real native library, on the live path (amendment 3).
- Produces:
  - `FakeGattPeripheral implements BlePeripheral`, with a GATT table and a scriptable responder.
  - Each stand-in is written from our reading of its backend at the pin, `halcyon_symbios.c`, `hw_ostc3.c` and `divesystem_idive.c` respectively. Each answers that backend's commands with two synthetic dives in that family's log format. Halcyon has the characteristics that must be skipped and three cells. OSTC has the Telit credit service and cells. Ratio relies on the backend's `sleep`, `purge` and `poll`, and has a setpoint only.
  - `enum StandinFault { badChecksum, nak, droppedPacket, disconnectHalfway }`.
  - The README says a stand-in can only find bugs in our layers, and never makes a family checked.

- [ ] **Step 1: Write the failing tests.** For each stand-in: 'two dives arrive and map as expected' (Halcyon: three `cellPpo2Bar` channels; OSTC: its cells; Ratio: setpoint, no cells), plus one test per fault: a bad checksum and a NAK end in a clean error with the earlier dives kept; a dropped packet times out; a disconnect halfway ends in IO.
- [ ] **Step 2: Run them and check they fail.** Run: `flutter test test/devices/libdc/standins_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement.** If a stand-in shows a bug in our layers, fix it in that layer, in this PR.
- [ ] **Step 4: Run all tests.** Run: `flutter analyze && flutter test`. Expected: clean, all pass.
- [ ] **Step 5: Commit and open the PR.** `git commit -m "test(devices): stand-ins for Halcyon Symbios, OSTC and Ratio on the live Bluetooth path"`

### Task 16: Re-parse stored libdivecomputer dives after a pin move or mapping change

**Files:**
- Create: `lib/data/import/libdc_reparser.dart`
- Modify: `lib/data/db/dive_dao.dart` (`reparseCandidates` gains an engine filter), `lib/main.dart` (start it next to the Shearwater re-parse)
- Test: `test/data/import/libdc_reparser_test.dart`

**Interfaces:**
- Consumes: `refreshFromRawBlob`, `getRawBlob`, `DiveImportMarks`, `LibdcEnvelope.decode`, `parseDive`, `mapLibdcDive`, `kLibdcParserVersion`, and `ShearwaterReparser`'s `waitUntilSynced` and baseline rules (phase 1 PR 6).
- Produces: `class LibdcReparser`, with the same constructor shape and `run()` result as `ShearwaterReparser`.
  - Candidates are rows with `dc_family IS NOT NULL AND parser_version < kLibdcParserVersion AND deleted_at IS NULL`, a non-empty local raw blob that decodes as `ALDC`, and no failure mark for this version.
  - Each dive is parsed in `Isolate.run`. The run keeps the stored id, the stored serial and `dc_fingerprint`.
  - A parse failure, an envelope that doesn't decode, `rejected`, or an `ArgumentError` from the codecs marks the dive and is reported. Any other write error stops the run without marking anything (phase 1 note).

- [ ] **Step 1: Write the failing tests.**

  ```dart
  test('refreshes every older libdc dive with a local envelope to the current version', ...);
  test('skips Shearwater dives, dives without a blob and deleted dives', ...);
  test('a failed parse or a codec ArgumentError is marked and reported once', ...);
  test('an interrupted run carries on; nothing runs before the first sync when signed in', ...);
  test('keeps the id, annotations, cylinders and dc_fingerprint', ...);
  ```

- [ ] **Step 2: Run them and check they fail.** Run: `flutter test test/data/import/libdc_reparser_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement the interfaces above.**
- [ ] **Step 4: Run all tests.** Run: `flutter analyze && flutter test`. Expected: clean, all pass.
- [ ] **Step 5: Commit and open the PR.** `git commit -m "feat(import): re-parse stored libdivecomputer dives after a reader update"`. This PR must merge before the first PR that bumps `kLibdcParserVersion`.

### Task 17: Per-cell ppO2 traces and the per-dive cell agreement summary

**Files:**
- Create: `lib/analysis/cell_agreement.dart`, `lib/ui/widgets/cell_agreement_card.dart`
- Modify: `lib/ui/widgets/profile_chart.dart` (cell traces when `cellPpo2Bar` isn't empty), and the dive screen that shows the cell section
- Test: `test/analysis/cell_agreement_test.dart`, `test/ui/widgets/cell_agreement_card_test.dart`, `test/ui/widgets/profile_chart_cells_test.dart`

**Interfaces:**
- Produces:
  - `CellAgreement? cellAgreement(SampleSet s)`. It returns null with fewer than two cell channels. It counts only samples at a depth of 1.0 m or more. Fields:
    - `double maxSpreadBar` and `int maxSpreadAtMs`, where the spread is the largest minus the smallest cell at that sample;
    - `Map<int, int> secondsAwayByCell`, the time a cell was more than `kCellAwayThresholdBar` from the median of the other cells;
    - `Map<int, ({double meanDiff, double maxAbsDiff})> vsSetpointByCell`, over samples where the setpoint is above 0.
  - `const double kCellAwayThresholdBar = 0.10;`. **Egbert reviews these thresholds before merge** (spec section 8): 0.10 bar, 1.0 m, and the setpoint comparison.
  - The profile chart draws one thin trace per cell in the ppO2 lane, with the theme's existing palette.

- [ ] **Step 1: Write the failing tests.**

  ```dart
  test('three agreeing cells: spread under 0.05, no time away', ...);
  test('one cell 0.2 bar low for 60 s: 60 s away for that cell only', ...);
  test('samples shallower than 1 m are ignored', ...);
  test('setpoint comparison only where a setpoint is set', ...);
  test('fewer than two cells gives null', ...);
  testWidgets('the card shows the spread, time away and the setpoint comparison', ...);
  testWidgets('the chart draws one trace per cell, and none for Shearwater dives', ...);
  ```

- [ ] **Step 2: Run them and check they fail.** Run: `flutter test test/analysis/cell_agreement_test.dart test/ui/widgets`. Expected: FAIL.
- [ ] **Step 3: Implement the interfaces above.**
- [ ] **Step 4: Run all tests.** Run: `flutter analyze && flutter test`. Expected: clean, all pass.
- [ ] **Step 5: Commit and open the PR.** `git commit -m "feat(analysis): per-cell ppO2 traces and a per-dive cell agreement summary"`

### Task 18: A characteristic read on every platform

**Files:**
- Modify: `lib/ble/ble_central.dart` (`Future<List<int>> read({Duration timeout})` on `BleCharacteristic`), `lib/ble/fbp_ble_central.dart`, `lib/ble/windows_ble_central.dart`, `windows/runner/ble_central_channel.cpp` (a `read` method using WinRT `ReadValueAsync`)
- Modify: `lib/devices/libdc/ble_central_libdc_link.dart` (`readCharacteristic` / `writeCharacteristic` over it)
- Test: `test/ble/fbp_ble_central_test.dart` or the existing central tests, `test/ble/windows_ble_central_test.dart`, `test/devices/libdc/ble_central_libdc_link_test.dart`

**Interfaces:**
- Produces: `BleCharacteristic.read` throws a `BleException` with `kBleErrorGatt` when the characteristic can't be read. On the Windows channel the method is `read` with arguments `{id, service, characteristic}`, returning bytes. `LibdcBleLink.readCharacteristic(uuid)` finds the characteristic in the chosen service, or in any service.

- [ ] **Step 1: Write the failing tests:** 'read returns the value', 'read of a non-readable characteristic is a gatt error', 'the Windows central sends read with the ids and decodes the bytes', 'the libdc link reads and writes a characteristic by uuid'.
- [ ] **Step 2: Run them and check they fail.** Run: `flutter test test/ble test/devices/libdc`. Expected: FAIL.
- [ ] **Step 3: Implement.** Build Windows through `libdivecomputer-build.yml`'s Windows job.
- [ ] **Step 4: Run all tests.** Run: `flutter analyze && flutter test`. Expected: clean, all pass. The Windows job is green.
- [ ] **Step 5: Commit and open the PR.** `git commit -m "feat(ble): read a characteristic on every platform"`

### Task 19: Subsurface copies across serial readings

**Files:**
- Modify: `lib/data/db/equipment_dao.dart` (the dive-computer lookups behind `recentImportsForComputer` and `getDiveComputer`), the merge validator (`lib/analysis/merge/`), `lib/ui/notifiers/dive_detail_notifier.dart`
- Test: `test/data/db/equipment_dao_test.dart`, `test/analysis/merge/merge_validator_test.dart`

**Interfaces:**
- Consumes: Task 13's `brandSerialOf`.
- Produces: equipment lookups and the merge validator's equal-serial rule compare `brandSerialOf(...)` values. Stored values never change. This settles the phase 1 note: gated downloads store decimal serials while copies keep hex.

- [ ] **Step 1: Write the failing tests:** 'an OSTC copy and an OSTC download of the same computer list under one computer', 'they may be merged', 'Shearwater lookups are unchanged'.
- [ ] **Step 2: Run them and check they fail.** Run: `flutter test test/data/db/equipment_dao_test.dart test/analysis/merge`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run all tests.** Run: `flutter analyze && flutter test`. Expected: clean, all pass.
- [ ] **Step 5: Commit and open the PR.** `git commit -m "fix(equipment): match Subsurface copies and downloads of one computer across serial readings"`

---

## Changes made during execution (2026-11-17)

The PRs are #239 (PR A, Tasks 1–3), #243 (PR B, Tasks 4–7), #242 (PR C, Tasks 8–9) and #244 (PR D, Tasks 10–13). Where this plan and the code differ, the code and this list are what was decided.

- **PR A, the build.**
  - Windows exports through the `.def` file passed bare on the `cl` command line; `#pragma comment(linker, "/DEF:...")` is ignored (LNK4229). The sources go in a response file (cmd.exe's 8,191-character limit), and the DLL links `ws2_32` and `advapi32`. CI checks the exports with `dumpbin`.
  - macOS CI builds with `--config-only` plus an unsigned `xcodebuild`. iOS CI builds the device slice without codesigning, because the image has no simulator runtime.
  - `tool/update_upstream.sh` applies the patches in a temporary clone. Inside a subdirectory of the repo, `git apply` silently skipped paths relative to the repo root.
  - The licence page is reached from a new "Open-source licences" row on About, which also names the source repository.
- **PR C, the Subsurface writer (Ruling G1, from the Garmin session).** Instead of skipping every other-brand dive, the writer leaves out only those that match no remote dive, and the sync screen counts them. A matched one gets the merge of CCRLog-owned lines, and only of non-empty ones, so a download without annotations never blanks Subsurface's buddy or suit. "Other brand" means `dc_family` is set, or a vendor other than Shearwater; a vendor-less copy whose product is a Shearwater model counts as Shearwater.
- **PR C → PR D.** `dc_engines: 2` moved to PR D, together with the first code that creates libdivecomputer dives. `dc_family` -1 is reserved for FIT: `diveEngineOf` maps null to shearwater, -1 to fit and everything else to libdc.
- **PR B, the C layer.** `al_link_pending` returns a request id and the request's kind, and `al_link_complete` takes that id, so a late answer can never complete a newer request. Recordings also carry `E` (a failed call's status) and empty `R` events, so a replay fails where the live download failed.
- **PR B, parse and identity.** This amends spec section 7 and the Global Constraint "Parse with `dc_parser_new2` and the descriptor chosen for the download".
  - Dives are parsed with the *identity descriptor*: the row in the opened descriptor's family whose model equals the model the computer reported in DEVINFO, the first such row in table order, or else the opened row. libdivecomputer's own `dc_parser_new(device)` uses the reported model; `dc_parser_new2` takes the model from the descriptor, and a Bluetooth name matches every model of its family (an OSTC 4 opens as "OSTC 2").
  - The identity descriptor also gives the dive id's vendor and `dc_vendor` / `dc_product`, so the same dive gets the same id whichever sibling row was opened.
  - The envelope keeps the opened descriptor and the device info, so a re-parse from the envelope alone gives the same dive.
  - The opened row is found by vendor, product and model, then by family and model. Some vendor-and-product pairs repeat with different models (the Aqualung i200C).
  - Checked against the vendored source: the OSTC 4 and 5 report 0x43 and 0x44, and Divesoft reports 10 (Liberty) and 19 (Freedom), as in the table. Ratio's 16-bit model uses the table's numbering. hwOS 3 OSTCs report 0 and so show as "OSTC 2", which doesn't change their parse.
- **PR B, the dive id.** When a computer gives no fingerprint, the hex of the SHA-256 of the dive's data stands in for it in the id, and `dc_fingerprint` stays null.
- **PR B, the mapping.**
  - The grid is capped in time, at twice the dive time or 24 h, and at 1,000,000 points.
  - Carried channels start from their first value, and no gas or setpoint event is made up at t = 0.
  - Air is assumed only when the computer reports no mixes; a lone oxygen-usage mix is kept.
  - Impossible dates are rejected.
- **PR B, the Petrel 3 trace.** It was recorded on Subsurface's fork of libdivecomputer, which reads RDBI 0x8050 where upstream reads 0x8060. Test support swaps that one exchange; the C replay stays strict, and a test pins the difference. The trace stops inside a 9th dive, so a replay gives 8 dives and then PROTOCOL.
- **PR B, the time base.** libdivecomputer dates a Shearwater's first sample one interval into the dive, and the grid holds it back to t = 0. This is accepted for libdivecomputer dives; Shearwater dives keep the Dart reader.
- **PR B, the session.** A crash inside a callback ends the download as `io`. `LibdcFinished` always comes, and every native object is freed on every path.
- **PR D, how it was built.** Task 12 was built in two halves: the scan, pickers and share file first, the download after Task 11. `LibdcDownloadSource`'s test seam returns `LibdcRun {events, cancel}`, because `LibdcDownload` has a private constructor, and the source gained `cancel()`, which stops the run and keeps the connection.
- **PR D, the download.**
  - A cancelled download ends as "Download stopped (cancelled). N dives saved.", is tracked as `import_failed`, and can still be shared.
  - For libdivecomputer dives the per-dive fingerprint save is skipped. Only `fingerprintToKeep` is saved, after a clean finish with no failed dive.
  - `LibdcDeviceInfo` carries the identity descriptor, so the download screen, the dive and the `dive_computers` row name the same model. Before connecting, a name that fits several products shows only the vendor and the advertised name.
  - There is no model picker. Ratio's Bluetooth models, the OSTCs and Divesoft open the same way whatever model the row names.
- **PR D, the screen.**
  - The re-import toggle keeps its label, "Re-import all dives (ignore prior imports)". The plan's "Download everything again" describes what it does.
  - On Linux, share_plus can't share files, so "Share this download" saves the file to Downloads and shows its path with "Open folder". Windows keeps the share sheet.
  - The scan screen offers "Scan again" when the 15 s scan has ended.
  - `redactImportError` doesn't exist. The import path uses `captureRedactedException` and the global Sentry redaction.

### Follow-ups found during execution

- A model picker for families whose device open depends on the model: Oceanic, Mares, Suunto EON Steel and the Pelagic i330R.
- "Share this download", with the GATT summary, when the connect itself fails.
- Android connection priority and PHY in `BleCentral`.
- PIN pairing: Windows answers 0000, Linux has no BlueZ agent, and the 15 s notify step can cut off a slow PIN entry.
- A name-based model hint for hwOS 3 OSTCs, as Subsurface's Bluetooth discovery does.
- Building the recording text only when it is shared.
- On Linux, a configured but missing Downloads folder fails instead of falling back to the temporary directory, and the share text isn't shown.
- The dive computers list shows "Unknown" as the model of other brands.
- A fresh `record: true` recording of a Petrel 3 needs a developer tool, because the app never sends a Shearwater through libdivecomputer.

## Follow-ups outside this plan

These are from the spec and phase 1, unchanged:
- Shearwater import on Windows.
- The Subsurface writer for other brands, with Subsurface's own ids (it can use `dc_fingerprint`).
- The raw-blob write joining the PowerSync transaction.
- Folding the duplicate pairs that already exist.
- Pushing refreshed dives to Subsurface Cloud.
- The PIN prompt for the Aqualung i330R and Apeks DSX.
- Longitudinal ppO2-based cell health.
- The Divesoft millivolt patch to Jef.
- Phases 3 and 4.
- The website's ask for recordings, which belongs to the website session.
