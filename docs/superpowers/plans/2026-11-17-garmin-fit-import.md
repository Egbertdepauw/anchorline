# Garmin dives from FIT files — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A diver can import Garmin Descent dives (and other FIT dive files) on all five platforms from `.fit` files, a Garmin Connect "Export Original" zip, or Garmin's whole-account export. The dives are stored, refreshed, synced and shown like every other dive.

**Architecture:** A new pure-Dart package, `packages/fit_reader`, decodes FIT files and maps dive sessions to `ConvertedDive`. It is written from format facts only. In the app, a small zip reader and a `FitFileSource` behind the shared `DiveDownloadSource` turn picked files into dives. The existing import notifier and manifest list commit them through `DiveDao.importDive`. FIT dives set `dc_family = -1`, so they ride phase 2's `libdc_dives` gate, its engine-aware refresh and its Subsurface writer rule. The work ships as four PRs: the reader package, engine wiring, the file import, and documents.

**Tech Stack:** Dart 3.12 / Flutter 3.44. `dart:io` raw deflate (`ZLibDecoder(raw: true)`). The existing `file_picker` and `share_plus`. `crypto` (already a `subsurface_core` dependency). PowerSync 2.1.0. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-11-17-garmin-fit-import-design.md` (PR #237). Read it with the phase 2 plan, `docs/superpowers/plans/2026-11-17-libdivecomputer-phase-2-bluetooth.md` (PR #235). PRs 2–4 here build on its PR C (Tasks 8–9: `dc_fingerprint`, `diveEngineOf`, the writer rule) and PR D (Task 12: the reworked import screen and notifier). Where that plan's "Changes made during execution" section differs from it, that section wins.

## Before anything is built (Egbert)

1. Merge the spec PR (#237).
2. PR 1 can start now. PRs 2–4 start only once phase 2's PR C and PR D are merged into `main`. They change the same notifier, screen and refresh code.
3. The share address is phase 2's: `recordings@anchorline.eu`, unless Egbert picked another one for phase 2.

## Global Constraints

- **Licence:** no Garmin FIT SDK code, no port of it (`fit_sdk` on pub.dev is one), and no table generated from its `Profile.xlsx` in the repo. Agents must not download, open or fetch Garmin's SDK, `Profile.xlsx`, or the FIT pages on developer.garmin.com. Facts come only from:
  - Subsurface's Garmin parser, read for facts and not translated: `src/garmin_parser.c` and `src/garmin-models.h` in `github.com/subsurface/libdc`, branch `Subsurface-DS9`;
  - other openly licensed decoders;
  - the real files.

  `packages/fit_reader` code is Anchorline's own (GPL-2.0-only, like the app).
- **Dive id:** `sha256('fit:<manufacturer>:<serial>:<time created>')`, truncated to 32 hex characters, with the same form as `generateDiveId`. All three are decimal integers taken raw from the file id message. `<time created>` is the raw FIT value (seconds since 1989-12-31 00:00 UTC), not Unix time. A file's second and later dive sessions append `:<n>` (n = 1, 2, …). The id is frozen at first import.
- **`dc_fingerprint`:** lower-case hex of the serial as `u32` big-endian, followed by the time created as `u32` big-endian (16 hex characters). A session `n ≥ 1` adds one `u8` with n. For example, serial 1 and time 2 give `"0000000100000002"`.
- **Brand columns:**
  - `dc_family` = `kFitDcFamily` = `-1`.
  - `dc_model` = `ShearwaterModel.unknown`.
  - `dc_model_code` = the FIT product number.
  - `dc_vendor`: `"Garmin"` for manufacturer 1, `"Suunto"` for 23, otherwise `"FIT manufacturer <n>"`.
  - `dc_dive_number`: the session dive summary's dive number, or 0 when it's missing.
  - `dive_computers.model` = 0.
  - `DcIdentity.importStateKey` = `fit:<manufacturer>:<serial>`. Nothing reads it; there is no saved fingerprint for files.
- **Parser version:** `kFitParserVersion` starts at 1. Bump it whenever the FIT reader's output changes. The guard test in Task 4 enforces this.
- **Raw blob:** the `ALFT` envelope (Task 3), in `dive_raw_blobs`, holding the FIT bytes exactly as read.
- **Time:**
  - `start_time` = session start + the activity's offset (local timestamp minus timestamp), stored as if UTC.
  - `utc_offset_minutes` = that offset.
  - Without an activity local timestamp, use device settings' offset, then none. Each fallback gets a comment in the code.
  - Imported data changes only through the refresh, and a refresh never changes `start_time` (phase 1).
- **Copy:**
  - The tier badge is exactly "Not yet tested by us".
  - The share text, verbatim: "This file is one of your dives, as your watch recorded it. It contains the dive, the watch's serial number, and any GPS positions and heart rate it logged. Send it to recordings@anchorline.eu or attach it to an issue at github.com/Egbertdepauw/anchorline/issues so we can check your model."
- **Skipped:** apnea and apnea-hunt sessions, and non-dive activities. Both are counted, never imported.
- **Sentry:** never receives FIT bytes, file names, serials or dive data. Use `redactImportError`.
- Dives and samples live in PowerSync. Read and write them through `_ps`.
- Never remove the write-direction safety hold in `sync_orchestrator.dart`. Don't run `dart format` on whole files. Never `git reset --hard`.
- **Every PR:**
  - `flutter analyze` clean and `flutter test` passing;
  - `dart analyze --fatal-infos` and `dart test` passing in `packages/subsurface_core` and in `packages/fit_reader`.
- **Git and agents:** git text is in English, and commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Build agents run on `model: "sonnet"`, review agents on `"opus"`.

## Review Focus

1. **The same dive from two sources in one pick.** For example, a Connect export (`<activityId>_ACTIVITY.fit`) and a copy off the watch (`2023-08-17-08-51-59.fit`), or a folder and a zip of it. Expected: one listing and one stored dive. Pinned in Task 8.
2. **An account export that is mostly runs and rides,** with thousands of non-dive files and a few dives. Expected:
   - the reader stops decoding each non-dive file at its sport message;
   - memory stays bounded;
   - the counts are right;
   - the import finishes.

   Pinned in Tasks 2 and 7.
3. **A newer watch's file with developer fields (Connect IQ data fields), unknown messages and unknown fields.** Expected: it imports, and the unknown parts are skipped by size. Pinned in Task 1.
4. **A file with no activity local timestamp, or no dive number, and two short dives from one watch less than a minute apart.** Expected: start times fall back as the constraints say, and both dives are stored under their own ids (by fingerprint). Pinned in Tasks 3 and 5.
5. **The import cancelled, the app backgrounded, or the app killed halfway on a phone.** Expected: dives already committed stay, nothing is half-written, and the temp folder is gone at the next start. Pinned in Task 8.

---

## PR map

| PR | What | Base | Tasks |
|---|---|---|---|
| 1 Reader | `packages/fit_reader`: container, dive reader, mapping, envelope, real fixtures, anonymiser, CI | `main` | 1–4 |
| 2 Engine | the FIT engine in refresh and re-parse, the overlap query | `main` after phase 2 PR C and D | 5 |
| 3 Import | zip reader, `FitFileSource`, notifier and screen, tiers, sharing | PR 2 | 6–8 |
| 4 Docs | `CLAUDE.md`, `NOTICE.md`, README, the Mk1 marked checked | PR 3 | 9 |

---

## PR 1 — The reader package

### Task 1: Package, engine constant and the FIT container

**Files:**
- Create: `packages/fit_reader/pubspec.yaml` (path dependency on `../subsurface_core`; dev: `lints`, `test`), `analysis_options.yaml` (as `subsurface_core`), `lib/fit_reader.dart` (barrel), `lib/src/container.dart`, `test/purity_test.dart`, `test/container_test.dart`, `test/support/fit_writer.dart`
- Create: `packages/subsurface_core/lib/data/models/dc_engine.dart`, plus its export in `lib/subsurface_core.dart`
- Modify: `.github/workflows/check.yml`: three steps after the `subsurface_core` ones, `fit_reader pub get`, `fit_reader analyze` (`dart analyze --fatal-infos`) and `fit_reader test`, with `working-directory: packages/fit_reader`

**Interfaces:**
- Produces:
  - `const int kFitDcFamily = -1;` in `subsurface_core`, documented as "a FIT file dive; libdivecomputer families are positive".
  - `class FitFormatException implements Exception { final String message; }`.
  - `class FitField { final int number; final int baseType; final int size; final int offset; final Object? value; }`:
    - `offset` is the byte offset of the value in the file;
    - `value` is an `int`, a `double`, a `String`, or a `List<int>` for arrays;
    - `value` is null when the field holds its base type's invalid marker.
  - `class FitMessage { final int global; final int? timestamp; final Map<int, FitField> fields; int? intField(int n); double? doubleField(int n); String? stringField(int n); }`:
    - `timestamp` is absolute FIT seconds, from field 253 or a compressed timestamp header;
    - developer fields are not in `fields`.
  - `class FitFile { final int protocolVersion; final int profileVersion; final List<FitMessage> messages; }`.
  - `FitFile decodeFit(Uint8List bytes, {bool Function(FitMessage m)? stopAfter})`:
    - it throws `FitFormatException` on a bad header, a missing `.FIT` tag, a wrong header or file CRC, a truncated file, or a data message with no definition;
    - when `stopAfter` returns true, decoding ends there and the file CRC is not checked.
  - Test-only: `Uint8List buildFit(List<FitMessageSpec> messages, {bool bigEndian = false, bool compressedTimestamps = false, List<FitDevFieldSpec> devFields = const []})` and `FitMessageSpec(int global, Map<int, (int baseType, Object value)> fields)`.

    The writer is the test side of the container: definitions, data, a CRC that's correct by default, and options for a bad CRC and truncation. It has no dive knowledge.

- [ ] **Step 1: Write the failing tests** (`container_test.dart`, all on `buildFit` output):

  ```dart
  test('12- and 14-byte headers both decode', ...);
  test('little- and big-endian definitions give the same values', ...);
  test('a compressed timestamp header adds its offset to the last timestamp, with rollover', ...);
  test('developer fields are skipped by their declared size and the next message still decodes', ...);
  test('an unknown global message and an unknown field are kept, not fatal', ...);
  test('each base type\'s invalid marker reads as null', ...);   // uint8 0xFF, uint16 0xFFFF, uint32z 0, sint32 0x7FFFFFFF, string empty, float NaN
  test('a wrong file CRC throws FitFormatException', ...);
  test('a truncated file throws FitFormatException', ...);
  test('stopAfter ends decoding without a CRC check', ...);
  test('a data message whose local type was never defined throws', ...);
  test('FitField.offset points at the value bytes', ...);       // overwrite there, decode again, see the new value
  ```

  `purity_test.dart` copies `subsurface_core`'s, forbidding `dart:io` everywhere in `lib/` with no exceptions, and checks the barrel exports every `lib/` file outside `lib/src/` that isn't private.
- [ ] **Step 2: Run them and check they fail.** Run: `cd packages/fit_reader && dart pub get && dart test`. Expected: FAIL (no implementation).
- [ ] **Step 3: Implement `decodeFit` and the writer.** The CRC is FIT's CRC-16 (polynomial 0xA001, nibble table). Its facts come from Subsurface's `garmin_parser.c` or an openly licensed decoder.
- [ ] **Step 4: Run them and check they pass.** Run: `dart analyze --fatal-infos && dart test` in `packages/fit_reader`, then `dart test` in `packages/subsurface_core`. Expected: clean, all pass.
- [ ] **Step 5: Commit.** `git commit -m "feat(fit): a pure-Dart FIT container decoder in packages/fit_reader"`

### Task 2: The dive reader and the classifier

**Files:**
- Create: `packages/fit_reader/lib/src/messages.dart`, `lib/src/dive_reader.dart`, `test/dive_reader_test.dart`

**Interfaces:**
- Consumes: Task 1's `decodeFit`, `FitMessage`.
- Produces:
  - `messages.dart`: named constants for the global message numbers and field numbers used below. These numbers were checked against the Mk1 files:
    - file id 0: type 0, manufacturer 1, product 2, serial 3, time created 4, product name 8;
    - sport 12: sub-sport 1;
    - session 18: start time 2, sport 5, sub-sport 6, total elapsed time 7 (ms);
    - record 20: depth 92 (mm);
    - activity 34: local timestamp 5;
    - dive settings 258: model 1, GF low 2, GF high 3, water type 4, water density 5 (float), low setpoint switch mode 22, low setpoint 23 (cbar), low switch depth 24 (mm), high switch mode 25, high setpoint 26 (cbar), high switch depth 27 (mm);
    - dive gas 259: helium 0, oxygen 1, status 2 (0 disabled, 1 enabled, 2 backup only), type 3 (0 open circuit, 1 CCR diluent);
    - dive summary 268: reference message 0, max depth 3, dive number 10, bottom time 11.

    The builder adds, from the allowed sources:
    - the other record fields (temperature, CNS, next stop depth and time, time to surface, NDL);
    - event 21 (gas switch and dive alert codes);
    - device info 23 and device settings 2;
    - sensor profile 147, tank update 319 and tank summary 323;
    - the sub-sport numbers: dive kinds 53–57 and 63, where 63 is CCR. Apnea and apnea hunt are among 53–57; the builder confirms which.
  - `enum FitFileKind { dive, apnea, otherActivity, notActivity }`.
  - `FitFileKind classifyFit(Uint8List bytes)`:
    - it decodes with `stopAfter` at the first sport message, or failing that the first session;
    - it throws `FitFormatException` for an unreadable file;
    - a file id type other than activity (4) is `notActivity`.
  - `class FitFileId { final int manufacturer; final int? product; final int serial; final int timeCreated; final String? productName; }`, with serial 0 when absent.
  - `class FitDiveSession`: the session's start and end (FIT seconds), offset minutes (nullable), sub-sport, dive number, summary max depth, and lists of `FitMessage` for records, events, tank updates, dive gases, sensor profiles and tank summaries. It also has the dive settings message and a `firmware` (`int?`, from the main device info's software version).
  - `class FitDiveFile { final FitFileId id; final List<FitDiveSession> sessions; }`.
  - `FitDiveFile readFitDives(Uint8List bytes)`:
    - it checks the CRC;
    - it gives one session per dive session, assigning records, events and tank updates to the session whose time span contains them;
    - apnea sessions are left out.

- [ ] **Step 1: Write the failing tests** (synthetic files from Task 1's writer):

  ```dart
  test('a CCR dive file classifies as dive', ...);
  test('apnea and apnea-hunt files classify as apnea', ...);
  test('a running activity classifies as otherActivity, and decoding stopped at its sport message', ...);  // stopAfter observed via a counter
  test('a settings file (file id type 2) is notActivity', ...);
  test('readFitDives gives one session with its records, events, gases and summary', ...);
  test('two dive sessions in one file split records by time span', ...);
  test('the local offset comes from the activity; without it from device settings; else null', ...);
  test('a missing serial reads as 0', ...);
  ```
- [ ] **Step 2: Run them and check they fail.** Run: `dart test test/dive_reader_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run them and check they pass.** Run: `dart analyze --fatal-infos && dart test`. Expected: clean, all pass.
- [ ] **Step 5: Commit.** `git commit -m "feat(fit): read dive sessions out of FIT files and classify files"`

### Task 3: Mapping, ids, products and the envelope

**Files:**
- Create: `packages/fit_reader/lib/src/mapping.dart`, `lib/src/products.dart`, `lib/src/envelope.dart`, `test/mapping_test.dart`, `test/envelope_test.dart`

**Interfaces:**
- Consumes: Task 2. From `subsurface_core`: `ConvertedDive`, `Dive`, `SampleSet`, `DiveEvent`, `DiveEventType`, `DiveGasMix`, `DiveTank`, `TankUsage`, `DiveMode`, `DecoModel`, `ShearwaterModel`, `kFitDcFamily`.
- Produces:
  - `const int kFitParserVersion = 1;`
  - `String fitDiveId({required int manufacturer, required int serial, required int timeCreated, int session = 0})` and `String fitFingerprintHex({required int serial, required int timeCreated, int session = 0})`, both as in Global Constraints.
  - `String fitVendorName(int manufacturer)`.
  - `String fitProductName({required int manufacturer, int? product, String? productName})`. For Garmin it uses the product table, else the file's product name with a leading vendor name removed (`"Suunto Ocean"` becomes `"Ocean"`), else `"Garmin product <n>"` / `"product <n>"`. The Garmin table, with names and ids as facts from Subsurface's `garmin-models.h` and the ™ and ® signs dropped:

    | Ids | Name |
    |---|---|
    | 2859, 2991 | Descent Mk1 |
    | 3258, 3702 | Descent Mk2/Mk2i |
    | 3542, 3930 | Descent Mk2 S |
    | 4005 | Descent G1 |
    | 4588 | Descent G2 |
    | 4222 | Descent Mk3 43 mm |
    | 4223 | Descent Mk3 51 mm |
    | 4518 | Descent X50i |
    | 4532, 4533, 4534, 4536, 4631, 4775, 4776 | fēnix 8 |

  - `List<ConvertedDive> mapFitFile(Uint8List bytes)`: `readFitDives` plus `mapFitSession` for each session.
  - `ConvertedDive mapFitSession(FitFileId id, FitDiveSession s, int sessionIndex)`. It follows spec section 5:
    - **Dive mode:** CCR → `cc`; single- and multi-gas → `ocTec`; gauge → `gauge`; no sub-sport → `ocTec`.
    - **Gases:** enabled and backup-only gases become mixes in file order; a diluent → `isDiluent`; disabled gases are left out.
    - **Deco:** `decoModel` `gf` with the settings' GF.
    - **Water:** `waterDensityKgM3` from the density, or 1000 / 1025 by water type.
    - **Atmospheric pressure:** 1013 when the file gives none. The builder checks for a surface-pressure field first.
    - **Setpoints:** the setpoint channel starts at the low setpoint and follows the setpoint-switch alerts (low or high, automatic or manual). `ppo2Bar`, the cell mV channels and `cellPpo2Bar` stay empty, the way an OC Shearwater dive leaves them.
    - **Tanks:** one `DiveTank` and one `tankPressuresBar` channel per tank transmitter, in sensor-profile order, with the slot as the index.
    - **Samples:** resampled to the most common record gap, carrying values forward. Deco time is the next stop time when the next stop depth is above 0, else NDL.
    - **Events:** at their exact times, `rawType` = the alert code.
    - **Header and identity:**
      - `logVersion` 0, `sensorCalibration` empty, stack times null;
      - `sampleIntervalMs` = the grid;
      - `duration` and `maxDepthMeters` from the samples;
      - `endTime` = start + duration;
      - id from `fitDiveId`, serial from the file id.
  - `enum FitSource { file(0), connectExport(1), accountExport(2), folder(3) }`.
  - `class FitEnvelope { final FitSource source; final String fileName; final Uint8List fit; Uint8List encode(); static FitEnvelope decode(Uint8List bytes); }`. The layout is big-endian: `'ALFT'`, `u8 1`, `u8 source`, `u16 length` plus the UTF-8 file name, `u32 length` plus the FIT bytes. `decode` throws `FormatException` on a bad magic, a newer version or truncated input.
  - The `Dive` gets `dcFingerprint` from `fitFingerprintHex`. Phase 2's Task 8 adds that field to `Dive`. If PR 1 lands before it, leave it out and add it in Task 5.

- [ ] **Step 1: Write the failing tests:**

  ```dart
  test('fitDiveId matches its formula', ...);   // sha256('fit:1:1000000001:1061159483') first 32 hex
  test('fitFingerprintHex(serial: 1, timeCreated: 2) == "0000000100000002"; session 1 appends "01"', ...);
  test('a CCR dive maps to cc with a diluent, bailout mixes and a 0.7 → 1.3 setpoint trace', ...);
  test('setpoint switch alerts move the setpoint and add setpointChange events', ...);
  test('gas switch events set the gas mix index and add gasSwitch events', ...);
  test('two tank transmitters give two tanks and two pressure channels', ...);
  test('irregular records resample to the most common gap, carrying values forward', ...);
  test('start time is wall clock: session start + offset, stored as UTC; offset in utcOffsetMinutes', ...);
  test('no dive number gives 0, and two short dives one minute apart get different ids and fingerprints', ...);
  test('brand fields: Garmin, Descent Mk1, family -1, model code 2859, dcModel unknown', ...);
  test('Suunto Ocean product name maps to vendor Suunto, product Ocean', ...);
  test('an unknown Garmin product id gives "Garmin product 9999"', ...);
  test('a disabled gas is left out; a backup-only gas is kept', ...);
  test('envelope round trip; bad magic, version 2 and truncation throw FormatException', ...);
  ```
- [ ] **Step 2: Run them and check they fail.** Run: `dart test test/mapping_test.dart test/envelope_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run them and check they pass.** Run: `dart analyze --fatal-infos && dart test`. Expected: clean, all pass.
- [ ] **Step 5: Commit.** `git commit -m "feat(fit): map FIT dive sessions to Anchorline dives"`

### Task 4: Real fixtures, the anonymiser and the output guard

**Files:**
- Create:
  - `packages/fit_reader/tool/anonymise_fit.dart`;
  - `test/fixtures/garmin_mk1_ccr_2023-08-17.fit`, `test/fixtures/garmin_mk1_ccr_2023-10-21.fit` and `test/fixtures/suunto_ocean_nitrox.fit`;
  - `test/fixtures/README.md`;
  - `test/fixtures_test.dart`, `test/reader_output_guard_test.dart`, `test/anonymise_test.dart`.

**Interfaces:**
- Consumes: Tasks 1–3 (`FitField.offset` for in-place patching).
- Produces:
  - `dart run tool/anonymise_fit.dart <in.fit> <out.fit> [--serial 1000000001]`. It patches the file in place, so the layout and sizes stay as they are:
    - every serial field (file id, device info) becomes the given serial (default `1000000001`);
    - GPS latitude and longitude fields become their invalid marker;
    - every string field in user profile and device messages is zeroed;
    - the file CRC is recomputed.

    It prints what it changed: the counts per message type, no values.
  - `String fitReaderDigest(ConvertedDive c)` in the guard test. It is the same idea as `test/shearwater/parser/reader_output_guard_test.dart`: SHA-256 over named fields, gas and tank JSON, raw sample arrays and events, with a pinned version.

- [ ] **Step 1: Get the real files.** Clone `https://github.com/subsurface/subsurface` with `--depth 1` into the session scratchpad, not the repo. Copy `dives/garmin_2023-08-17-08-51-59.fit`, `dives/garmin_2023-10-21-12-13-38.fit` and `dives/suunto_ocean_nitrox.fit`.
- [ ] **Step 2: Write the failing tests:**

  ```dart
  // anonymise_test.dart (on a synthetic file)
  test('serials, GPS and profile strings are replaced; everything else is byte-identical; CRC valid', ...);
  // fixtures_test.dart (on the committed, anonymised files)
  test('Mk1 dive 1: facts', () {
    // classifyFit == dive; one session; vendor Garmin, product Descent Mk1, modelCode 2859, serial 1000000001
    // startTime == DateTime.utc(2023, 8, 17, 8, 51, 59); utcOffsetMinutes == 720; dcDiveNumber == 11
    // diveMode cc; gfLow 50, gfHigh 60; waterDensity 1025; maxDepth ≈ 51.765 (±0.01)
    // duration between 97 and 99 minutes; sampleIntervalMs 1000
    // gases: 18/20 dil, 18/20 OC, 50/0 OC, 50/0 dil (file order)
    // setpoint starts at 0.7 and reaches 1.3
  });
  test('Mk1 dive 2: facts', () {
    // startTime DateTime.utc(2023, 10, 21, 12, 13, 38); offset 780; dive number 538; GF 50/70
    // maxDepth ≈ 62.02; duration between 105 and 107 minutes; gases 17/30 dil, 17/30 OC, 52/0 OC, 52/0 dil
  });
  test('Suunto Ocean: vendor Suunto, product Ocean, serial 0, ocTec, one 32% mix, GF 40/85', ...);
  // reader_output_guard_test.dart
  test('kFitParserVersion matches the pinned version, and every fixture matches its digest', ...);
  ```

  When a fact above disagrees with what the file says, check it against Subsurface's reading of the same file before changing the test. Note the disagreement in the PR.
- [ ] **Step 3: Implement the anonymiser, run it on the three files, and commit only the anonymised output.** `test/fixtures/README.md` says:
  - where each file comes from: Subsurface's repository, GPL-2.0, added there on 2026-10-31;
  - that it was anonymised with `tool/anonymise_fit.dart`;
  - that the originals are not in this repo.
- [ ] **Step 4: Run the tests and paste the digests.** Run: `dart analyze --fatal-infos && dart test`. Expected: clean, all pass, with the digests pinned at version 1.
- [ ] **Step 5: Commit and open PR 1.** `git commit -m "test(fit): real Descent Mk1 and Suunto Ocean fixtures, anonymised, with an output guard"`. The PR description lists the licence constraint and the sources used for field facts.

---

## PR 2 — The FIT engine

### Task 5: FIT dives in refresh and re-parse, and the overlap query

**Files:**
- Modify: `pubspec.yaml` (`fit_reader: path: packages/fit_reader`), `lib/data/import/refresh_policy.dart` (`diveEngineOf` uses `kFitDcFamily` instead of a literal), `lib/data/db/dive_dao.dart`, `lib/main.dart` (start the FIT re-parse next to the others)
- Create: `lib/data/import/fit_reparser.dart`
- Test: `test/data/import/fit_import_test.dart`, `test/data/import/fit_reparser_test.dart`, `test/data/db/dive_dao_overlap_test.dart`, `packages/subsurface_core/test/sync/subsurface_git/sync_planner_fit_test.dart`

**Interfaces:**
- Consumes:
  - from PR 1: `mapFitFile`, `FitEnvelope`, `kFitParserVersion`, `kFitDcFamily`;
  - from phase 2 PR C: `diveEngineOf`, `dc_fingerprint`, the refresh rules;
  - the re-parse candidates query with its engine filter (phase 2's Task 16).
- Produces:
  - `FitReparser`, shaped like `ShearwaterReparser`. Its candidates are rows with `dc_family = -1`, `parser_version < kFitParserVersion`, not deleted, with a non-empty local raw blob that decodes as `ALFT`, and no failure mark for this version. Each blob is parsed in `Isolate.run` with `mapFitFile`. The session is chosen by the stored `dc_fingerprint`, and the dive is refreshed through `DiveDao.refreshFromRawBlob`. It keeps the id, the stored serial and `dc_fingerprint`.
  - `Future<({String id, String label})?> DiveDao.overlappingDiveFromOtherComputer({required int startSeconds, required int endSeconds, required String vendor, required int serial})`:
    - it returns the first live dive whose `[start_time, end_time]` overlaps the given span and whose `(effective vendor, serial)` differs;
    - a NULL vendor counts as Shearwater on downloads, as `effectiveVendor` says;
    - `label` is the dive's product name, or the Shearwater model name when the product is NULL.

- [ ] **Step 1: Write the failing tests:**

  ```dart
  // fit_import_test.dart (fixture bytes from packages/fit_reader/test/fixtures)
  test('a FIT dive imports with family -1, its fingerprint, and an ALFT raw blob', ...);
  test('the same dive again is unchanged; a newer FIT version refreshes it', ...);
  test('a Garmin Subsurface copy (decimal serial, start within 60 s) is refreshed under its own id', ...);
  test('a libdivecomputer row with the same id is never written by a FIT import, raw blob included', ...);
  test('two dives from one watch 40 s apart with dive number 0 are both stored', ...);
  // fit_reparser_test.dart
  test('re-parses FIT dives below the current version and keeps id, annotations and fingerprint', ...);
  test('skips Shearwater and libdivecomputer rows, and rows without a local blob', ...);
  test('a blob that does not decode as ALFT is marked as failed for this version only', ...);
  // dive_dao_overlap_test.dart
  test('a Petrel dive overlapping the span is returned with label "Petrel 3"', ...);
  test('the same watch, a deleted dive or a dive that only touches the span is not', ...);
  // sync_planner_fit_test.dart (phase 2's writer rule, pinned for dcFamily -1)
  test('a never-pushed FIT dive is left out and counted', ...);
  test('a FIT dive matching a remote dive gets its notes merged, its Divecomputer file untouched, no setpoint injected', ...);
  ```
- [ ] **Step 2: Run them and check they fail.** Run: `flutter test test/data`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run all tests.** Run: `flutter analyze && flutter test`, then `dart test` in both packages. Expected: clean, all pass.
- [ ] **Step 5: Commit and open PR 2.** `git commit -m "feat(fit): FIT dives in the refresh rules, the background re-parse and an overlap lookup"`

---

## PR 3 — The file import

### Task 6: A zip reader on dart:io

**Files:**
- Create: `lib/devices/fit/zip_reader.dart`, `test/devices/fit/zip_reader_test.dart`, `test/devices/fit/support/zip_builder.dart` (test-only writer: stored and deflated entries, Zip64, data descriptors)

**Interfaces:**
- Produces:
  - `class ZipEntryInfo { final String name; final int method; final int compressedSize; final int size; final int localHeaderOffset; bool get isStored; bool get isDirectory; }`.
  - `class ZipReader`, with:
    - `static Future<ZipReader> open(RandomAccessFile file, {int base = 0, int? length})`. `base` and `length` let a stored inner zip be read in place inside its outer file.
    - `List<ZipEntryInfo> get entries`, from the end-of-central-directory record or its Zip64 form.
    - `Future<Uint8List> read(ZipEntryInfo e, {int maxSize = 64 << 20})`, which inflates with `ZLibDecoder(raw: true)` and throws `ZipFormatException` above `maxSize`, on an unsupported method, or on a size mismatch.
    - `Future<void> extractTo(ZipEntryInfo e, File target)`, which streams in chunks of at most 1 MB.
    - `({int base, int length}) storedSpan(ZipEntryInfo e)`.
  - `class ZipFormatException implements Exception`.

- [ ] **Step 1: Write the failing tests:**

  ```dart
  test('lists and reads stored and deflated entries', ...);
  test('a Zip64 archive (forced Zip64 records) lists and reads', ...);
  test('a stored inner zip opens in place through storedSpan', ...);
  test('extractTo never reads more than 1 MB at once', ...);   // RandomAccessFile wrapper counting the largest read
  test('a 50 MB zip of stored entries reads entry by entry with bounded reads', ...);  // generated in a temp dir
  test('a corrupt central directory or a size mismatch throws ZipFormatException', ...);
  ```
- [ ] **Step 2: Run them and check they fail.** Run: `flutter test test/devices/fit/zip_reader_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run them and check they pass.** Expected: PASS.
- [ ] **Step 5: Commit.** `git commit -m "feat(fit): a small streaming zip reader on dart:io"`

### Task 7: `FitFileSource`

**Files:**
- Create: `lib/devices/fit/fit_inputs.dart`, `lib/devices/fit/fit_file_source.dart`
- Modify: `lib/devices/dive_download_source.dart` (`DiveListing` gains `double? maxDepthMeters`, `int? durationSeconds`, `String? modelLabel`, `String? flag`, `bool preselected = true`; other engines leave the defaults)
- Test: `test/devices/fit/fit_file_source_test.dart`

**Interfaces:**
- Consumes: Task 6, PR 1 (`classifyFit`, `mapFitFile`, `FitEnvelope`, `FitSource`, `fitVendorName`, `fitProductName`), and the `DiveDownloadSource` shape.
- Produces:
  - `sealed class FitInput`, with `FitFileInput(String path)` and `FitFolderInput(String path)`.
  - `class FitScanCounts { int filesRead; int? filesTotal; int dives; int otherActivities; int apnea; int unreadable; }`.
  - `class FitFileSource implements DiveDownloadSource`:
    - **Constructor:** `FitFileSource({required List<FitInput> inputs, required Directory workDir, void Function(FitScanCounts)? onProgress})`.
    - **Basics:** `canListDives` is true, and `identity` is the last watch announced.
    - **What it walks:**
      - picked `.fit` files (`FitSource.file`);
      - folders, recursively (`folder`);
      - `.zip` files: one with at most one `.fit` entry is `connectExport`, and one with several entries or inner zips is `accountExport`;
      - inner `.zip` entries up to two levels deep: stored ones in place, compressed ones extracted to `workDir` one at a time and deleted after.
    - **Per file:** each FIT entry is classified and mapped in `Isolate.run`. Every dive file is copied into `workDir/dives/<n>.fit`, so `download` never re-walks a zip.
    - **Duplicates:** the same dive id seen twice in one pick is listed once.
  - `listDives()`:
    - it returns one `DiveListing` per dive session, newest first;
    - `diveNumber` is the dive number, and the start and end timestamps are the stored wall-clock seconds;
    - `fingerprint` is the 8 raw bytes (9 for a later session) whose hex is `fitFingerprintHex`;
    - `diveId`, `maxDepthMeters`, `durationSeconds` and `modelLabel` are filled.
  - `download({selection})`:
    - for each watch, in order, it emits `DiveSourceIdentified(DcIdentity(...))` with the Global Constraints values. The labels are `<vendor> <product>`, the decimal serial and the firmware;
    - each dive becomes `DiveSourceDive(rawBlob: FitEnvelope(...).encode(), parserVersion: kFitParserVersion, fingerprint, converted)`;
    - a dive that maps to nothing usable becomes `DiveSourceDiveFailed`;
    - it emits `DiveSourceProgress` per dive.
  - `close()` deletes `workDir`, and is idempotent.
  - `Future<void> purgeStaleFitWorkDirs(Directory tempRoot)` deletes leftover `fit-import-*` folders. Call it at app start (Task 8).

- [ ] **Step 1: Write the failing tests** (fixtures, plus synthetic files and zips from the PR 1 writer and Task 6's builder):

  ```dart
  test('loose .fit files: dives listed, a run counted as other, a broken file as unreadable', ...);
  test('a Connect export zip and the same file copied off the watch give one listing', ...);
  test('an account export (zip of a stored and a deflated inner zip) finds every dive', ...);
  test('a folder is read recursively', ...);
  test('apnea sessions are counted and not listed', ...);
  test('progress counts reach their totals', ...);
  test('download announces each watch before its dives and emits ALFT blobs', ...);
  test('two watches in one pick give two identities', ...);
  test('close deletes the work folder; purgeStaleFitWorkDirs removes leftovers', ...);
  test('cancelling the download subscription leaves committed dives and close still cleans up', ...);
  ```
- [ ] **Step 2: Run them and check they fail.** Run: `flutter test test/devices/fit`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run them and check they pass.** Run: `flutter analyze && flutter test test/devices`. Expected: clean, all pass.
- [ ] **Step 5: Commit.** `git commit -m "feat(fit): a download source that reads FIT files, folders and Garmin exports"`

### Task 8: Import screen, notifier, tiers and sharing

**Files:**
- Create:
  - `lib/devices/fit/fit_tiers.dart` and `lib/devices/fit/fit_share.dart`;
  - `lib/ui/widgets/garmin_files_help_sheet.dart`.
- Modify: `lib/ui/notifiers/import_notifier.dart`, `lib/ui/screens/import_screen.dart`, `lib/main.dart` (`purgeStaleFitWorkDirs` at start), `README.md`
- Test: `test/ui/notifiers/import_notifier_fit_test.dart`, `test/ui/screens/import_screen_fit_test.dart`, `test/devices/fit/fit_tiers_test.dart`, `test/devices/fit/fit_share_test.dart`

**Interfaces:**
- Consumes: Tasks 5 and 7. Phase 2 PR D's notifier and screen: its idle layout, `downloadAll` and usage events.
- Produces:
  - `const Map<String, String> kCheckedFitModels = {};` (model name → fixture path under `packages/fit_reader/test/fixtures/`) and `bool isCheckedFitModel(String product)`. It starts empty; Task 9 adds the Mk1 after Egbert's check. A test fails if a listed model has no fixture file.
  - `Future<void> ImportNotifier.importFitFiles(List<FitInput> inputs)`:
    - it creates `FitFileSource` with `workDir` = `<temp>/fit-import-<yyyymmdd-HHmmss>`, and the state goes to `readingManifest` with `fitCounts` updating;
    - after `listDives`, it marks each listing, grouped by watch:
      - a dive already stored (`existingDiveIdsAmong`, plus `alreadyDownloadedAmong` per watch) gets `flag` "Already in Anchorline" and `preselected` false;
      - otherwise, a dive for which `overlappingDiveFromOtherComputer` gives a label gets `flag` "Overlaps your <label> dive" and `preselected` false;
    - the existing manifest flow follows, with `downloadAll(subset)`;
    - "Import N dives" counts only the ticked ones.
    - `FitScanCounts? fitCounts` and `List<String> untestedModels` (the models of the imported dives that aren't checked) are exposed for the screen.
    - The source is closed on done, error and reset.
    - The usage events get `engine: 'fit'` and `vendor`.
  - The manifest screen:
    - pre-ticks only `preselected` listings;
    - shows `flag` next to a row;
    - shows depth, duration and model when the listing has them.
  - The idle screen gets a button, "Import Garmin files…", with the subline ".fit files, or a Garmin Connect export (.zip)", and a "Where do I find them?" link that opens `GarminFilesHelpSheet` with the spec's section 2 content.
    - The picker allows several files at once, `.fit` and `.zip`.
    - On desktop there is also a folder choice.
    - A failed copy into the cache because of free space shows "Not enough free space to read this file. It needs about <size>."
  - The reading state shows "Reading <filesRead> of <filesTotal> files…" and the four counts, using the spec section 6 wording.
  - The done screen, when `untestedModels` isn't empty, shows "Not yet tested by us: <models>" and a "Send us one of these dives" button.
  - `Future<void> shareFitDive({required String diveId, Rect? origin})` decodes that dive's raw blob and writes the FIT bytes to `<temp>/<vendor>-<product>-<yyyymmdd-HHmm>.fit`. It opens the share sheet at `origin` with the Global Constraints share text, as #232 requires on iOS.
  - The README gets "Help us test your Garmin" in phase 2's "Help us test your dive computer" section.

- [ ] **Step 1: Write the failing tests:**

  ```dart
  // import_notifier_fit_test.dart (fake DAO and source)
  test('importFitFiles lists dives and goes to the manifest with counts', ...);
  test('a stored dive is flagged "Already in Anchorline" and unticked', ...);
  test('a dive overlapping a Petrel dive is flagged "Overlaps your Petrel 3 dive" and unticked', ...);
  test('importing the ticked dives commits each through importDive with the FIT version', ...);
  test('untestedModels lists Descent Mk3 when kCheckedFitModels lacks it', ...);
  test('the source is closed after done, error and reset', ...);
  // import_screen_fit_test.dart
  testWidgets('idle shows "Import Garmin files…" and the help link opens the sheet', ...);
  testWidgets('manifest shows flags, depth, duration and model; flagged rows start unticked', ...);
  testWidgets('done shows "Not yet tested by us" and the share button for an unchecked model', ...);
  // fit_tiers_test.dart
  test('every checked model has its fixture file', ...);
  // fit_share_test.dart
  test('the shared file is the FIT bytes from the envelope, named by brand and date', ...);
  ```
- [ ] **Step 2: Run them and check they fail.** Run: `flutter test test/ui test/devices/fit`. Expected: FAIL.
- [ ] **Step 3: Implement.** Follow phase 2's screen layout. Don't restructure it.
- [ ] **Step 4: Run all tests.** Run: `flutter analyze && flutter test`, then `dart test` in both packages. Expected: clean, all pass.
- [ ] **Step 5: Commit and open PR 3.** `git commit -m "feat(import): import Garmin dives from FIT files and Garmin Connect exports"`. The description lists Egbert's checks (below).

---

## PR 4 — Documents

### Task 9: CLAUDE.md, NOTICE.md and the checked Mk1

**Files:**
- Modify: `CLAUDE.md`, `NOTICE.md`, `lib/devices/fit/fit_tiers.dart`

**Interfaces:**
- Produces:
  - **`CLAUDE.md`:**
    - the `dive_id` bullet gains "FIT dives: `sha256('fit:<manufacturer>:<serial>:<time created>')`, from the file id";
    - a bullet says "`packages/fit_reader` is pure Dart like `subsurface_core`; no Garmin SDK code, port of it, or `Profile.xlsx` table may enter it (Garmin's licence forbids copyleft use); facts come from Subsurface's Garmin parser and real files";
    - if phase 2 hasn't already replaced it, the out-of-scope line about non-Shearwater computers names Garmin FIT files as supported.
  - **`NOTICE.md`:** a "Garmin and FIT" entry. It names the fixtures' provenance (Subsurface, GPL-2.0, anonymised) and says the trademarks Garmin, Descent and FIT are used only to name the files.
  - **`kCheckedFitModels`:** `{'Descent Mk1': 'garmin_mk1_ccr_2023-08-17.fit'}`, added only after Egbert's check 1 passes.

- [ ] **Step 1: Make the document edits.** Edit by hand; don't run `dart format`.
- [ ] **Step 2: After Egbert's check 1, add the Mk1 to `kCheckedFitModels`, then run `flutter test test/devices/fit`.** Expected: PASS.
- [ ] **Step 3: Commit and open PR 4.** `git commit -m "docs(fit): CLAUDE.md, NOTICE.md and the Descent Mk1 checked"`

---

## Checks on real devices (Egbert)

These come from the spec's list, with the PR in which each one is possible:

1. **PR 1:** open the two original Mk1 files in Subsurface. Compare them with the fixture facts and with PR 3's import: start time, duration, max depth, gases, setpoint changes, temperature and the profile's shape.
2. **PR 3:** on each of the five platforms, import the Mk1 files through the picker, once as loose `.fit` files and once inside a zip made like a Connect export. On iOS, from the Files app.
3. **PR 3:** import the same files again. Expected: "Already in Anchorline", and nothing new.
4. **PR 3:** a test file whose dive overlaps one of Egbert's Petrel dives. The builder generates it with the PR 1 writer at that dive's time. Expected: "Overlaps your Petrel 3 dive", unticked.
5. **PR 3:** a second device with the same account receives the dives. An installed store build from before phase 2 doesn't show them.
6. **PR 3:** on a phone, a synthetic account export of about a gigabyte imports without the app being killed, and the work folder is gone afterwards.
