# Cylinder Label Printing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Print a 50 × 30 mm cylinder label (bailout/deco or diluent) for a saved gas analysis on a Phomemo M110 over BLE, from the analyzer's save card and from the analysis log.

**Architecture:** Pure-Dart label model (`lib/labels/`) turns a `GasAnalysis` plus the MOD setting into the label's values and strings. A Flutter renderer (`lib/labels/render/`) draws it into a 1-bit 384 × 240 bitmap. A pure-Dart printer layer (`lib/label_printer/`) encodes the bitmap into Phomemo bytes, and a thin `flutter_blue_plus` transport sends them. A `LabelPrintService` ties these together for the UI. The desired mix and gas role are new synced columns on `gas_analyses`.

**Tech Stack:** Flutter/Dart, `flutter_blue_plus` (already a dependency), `intl`, `shared_preferences`, PowerSync, Supabase migrations.

**Spec:** `docs/superpowers/specs/2026-10-31-cylinder-label-printing-design.md` (approved 2026-10-31). Read it before starting any task. This plan doesn't repeat its reasoning.

## Global Constraints

- **No new dependencies.** Use `flutter_blue_plus`, `intl` and `shared_preferences`, which are already in `pubspec.yaml`. Don't add the `phomemo` pub package.
- **Pure-Dart boundaries:** nothing under `lib/labels/` (except `lib/labels/render/`) or `lib/label_printer/` (except `lib/label_printer/phomemo/ble/`) may import `package:flutter`. Check this in each task with `grep -rn "package:flutter" lib/labels lib/label_printer | grep -v "/render/\|/ble/"`, which must print nothing.
- **Label geometry:** 50 × 30 mm, rendered at **384 × 240 dots** (203 dpi), all content inside a **12-dot (1.5 mm) safe margin**.
- **Depths are floored** to whole metres, never rounded: `floor(modMeters(analysedO2 / 100, ppO2))`.
- **Bailout/deco ppO2:** 1.6 by default. With "Use 1.4 for deeper mixes" on, it's 1.4 when the O2 used for the rule is below 50 %. The O2 for the rule is the desired O2, or the analysed O2 rounded to a whole percent when there's no desired mix or on a hard mismatch.
- **Diluent ppO2s are fixed:** headline TOD at 1.1, then 1.3 and MOD 1.6. The 1.4 setting never affects them.
- **Match thresholds** use the absolute difference in percentage points, rounded to 0.1 first. The overall level is the worse of O2 and He.

  | Level | O2 off by | He off by |
  |---|---|---|
  | match | ≤ 1.0 | ≤ 2.0 |
  | orange | ≤ 2.0 | ≤ 4.0 |
  | red | ≤ 5.0 | ≤ 10.0 |
  | hard | > 5.0 | > 10.0 |

- **Label name:** the desired mix name up to red. The analysed name on a hard mismatch or with no desired mix. Always `gasMixName()` from `lib/analysis/gas_naming.dart`.
- **Date on the label:** `DateFormat('d MMM yy', 'en_US')`, e.g. `31 Oct 26`, whatever the device locale.
- **UI copy fixed by the spec** (use verbatim): "Save & print", "Set up label printer", "Mix does not conform to analysis", "Print as {analysed name}", "Change desired mix", "Cancel", "Use 1.4 for deeper mixes", "Find printer", "Print test label", "Forget printer", "Printer not found", "Diluent", "Bailout/deco", "Other…".
- **Never block printing, never lose an analysis:** a print failure leaves the saved analysis in place and offers "Retry".
- **Measured values are immutable.** Only desired mix, gas role, analysed by and notes are editable after saving.
- **Device-local settings** (SharedPreferences, never synced): printer id/name, "Use 1.4 for deeper mixes", the Blend tab's target.
- **Migrations are idempotent:** `add column if not exists`. `./supabase/lint_migrations.sh` must pass.
- **Style:** don't run `dart format` on whole files (main isn't format-clean; it churns ~1000 lines). Match the surrounding style by hand.
- **Git:** work on branch `feat/114-cylinder-label-printing`, never on `main`. One commit per task, conventional prefix (`feat(labels): …`, `feat(analyzer): …`), English, ending with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- **Every task ends with** `flutter analyze` clean and `flutter test` passing.

## Review Focus

These are the failure modes the spec implies but no feature test would naturally hit. Each has a test in the task named after it.

1. **Printer off, out of range, or Bluetooth off.** `connect()` never completes. Expect "Printer not found" within the connect timeout (not a hang), the analysis still saved, and "Retry" offered. Tests in Task 7 (timeout) and Task 12 (save kept, Retry prints without a second save).
2. **Double tap on "Save & print".** Expect exactly one saved analysis and one print job. Test in Task 12.
3. **Non-English device locale (e.g. `nl_NL`).** Expect the label date to stay `31 Oct 26` and decimals to stay `20.6`. Test in Task 3.
4. **Rows from older builds or other devices:** null `gas_role`, an unknown `gas_role` string, null targets, or a target O2 with a null target He. Expect the bailout/deco label, no match level when there's no target O2, and He 0 when only He is null. Tests in Task 2.
5. **A long "analysed by"** (e.g. `Egbert de Pauw`). Expect the mix name never cut, the initials ellipsized, and no render exception. Test in Task 5.

---

### Task 1: Mix match grading

**Files:**
- Create: `lib/analysis/mix_match.dart`
- Test: `test/analysis/mix_match_test.dart`

**Interfaces:**
- Produces:
  - `enum MixMatchLevel { match, orange, red, hard }`
  - `class MixMatch { final MixMatchLevel level; final double o2Off; final double heOff; }`. `o2Off` and `heOff` are absolute differences in percentage points, rounded to 0.1.
  - `MixMatch gradeMix({required double o2Percent, required double hePercent, required int targetO2Percent, required int targetHePercent})`
  - `String mixMatchText(MixMatch m, String desiredName)`. Returns `Matches Tx21/35` for a match, otherwise lists each gas above its match bound, e.g. `O2 1.5 off Tx21/35` or `O2 1.5, He 4.5 off Tx21/35`.

- [ ] **Step 1: Create the branch**

```bash
git checkout -b feat/114-cylinder-label-printing
```

- [ ] **Step 2: Write the failing tests** in `test/analysis/mix_match_test.dart`. All use target 21/35.
  - O2 boundaries with He 35.0: 22.0 → match; 22.1 → orange; 23.0 → orange; 23.1 → red; 26.0 → red; 26.1 → hard; 19.9 → orange (below target works the same).
  - He boundaries with O2 21.0: 37.0 → match; 37.1 → orange; 39.0 → orange; 39.1 → red; 45.0 → red; 45.1 → hard.
  - Worst wins: 22.5 / 39.5 → red, with `o2Off == 1.5` and `heOff == 4.5`.
  - Float noise: 22.1 vs 21 gives `o2Off == 1.1` exactly (the 0.1 rounding).
  - `mixMatchText`:
    - 21.4 / 35.2 → `Matches Tx21/35`;
    - 22.5 / 35.0 → `O2 1.5 off Tx21/35`;
    - 22.5 / 39.5 → `O2 1.5, He 4.5 off Tx21/35`;
    - 21.0 / 38.0 → `He 3.0 off Tx21/35`.

- [ ] **Step 3: Run the tests to verify they fail**

Run: `flutter test test/analysis/mix_match_test.dart`
Expected: FAIL, `mix_match.dart` not found.

- [ ] **Step 4: Implement `lib/analysis/mix_match.dart`.** Pure Dart, no Flutter imports. Keep the thresholds as named constants (`kO2MatchMax = 1.0`, `kO2OrangeMax = 2.0`, `kO2RedMax = 5.0`, `kHeMatchMax = 2.0`, `kHeOrangeMax = 4.0`, `kHeRedMax = 10.0`). The doc comment says the O2 bounds and the hard limits are Egbert's, and the He 2/4 bounds were scaled from them. Round each difference with `(d * 10).round() / 10` before comparing. Format off-by values with `toStringAsFixed(1)`.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `flutter test test/analysis/mix_match_test.dart && flutter analyze`
Expected: all pass; no analyzer issues.

- [ ] **Step 6: Commit**

```bash
git add lib/analysis/mix_match.dart test/analysis/mix_match_test.dart
git commit -m "feat(analysis): grade an analysis against the desired mix (#114)"
```

---

### Task 2: Desired mix and gas role in the data layer

**Files:**
- Create: `supabase/migrations/0020_gas_analysis_label_fields.sql`
- Modify: `lib/data/models/gas_analysis.dart`, `lib/data/db/gas_analyses_dao.dart`, `lib/data/models/gas_analysis_csv.dart`, `lib/sync/cloud/powersync_schema.dart`, `test/_helpers/fake_gas_analyses_dao.dart`
- Test: `test/data/db/gas_analyses_dao_test.dart`, `test/data/models/gas_analysis_csv_test.dart`, `test/data/models/gas_analysis_test.dart` (create), `test/sync/cloud/powersync_schema_test.dart`

**Interfaces:**
- Consumes: `gradeMix`, `MixMatch` (Task 1).
- Produces (all in `lib/data/models/gas_analysis.dart`):
  - `enum GasRole { bailout, diluent }`, with `String get dbValue` (`'bailout'` / `'diluent'`) and `static GasRole fromDb(String? v)`. Anything other than `'diluent'` gives `bailout`.
  - `GasRole gasRoleForCylinderRole(String? cylinderRole)`: `CylinderRole.diluent` → `diluent`; everything else, including null, → `bailout`.
  - `class DesiredMix { final int o2Percent; final int hePercent; String get name; }`. Value equality and `hashCode`. `name` is `gasMixName(o2Percent, hePercent)`.
  - `CylinderChoice` gains `final String? role`.
  - `NewGasAnalysis` gains `final DesiredMix? desiredMix` and `final GasRole gasRole` (default `GasRole.bailout`).
  - `GasAnalysis` gains:
    - fields `final int? targetO2Percent`, `final int? targetHePercent` and `final GasRole gasRole` (default `bailout`);
    - getters `DesiredMix? get desiredMix` (null when `targetO2Percent` is null; a null He counts as 0) and `MixMatch? get match`;
    - `factory GasAnalysis.fromNew(String id, NewGasAnalysis n)`;
    - `GasAnalysis applyEdit(GasAnalysisEdit e)`.
  - `class GasAnalysisEdit { final DesiredMix? desiredMix; final GasRole gasRole; final String? analysedBy; final String? notes; }`
  - `List<DesiredMix> recentDesiredMixes(List<GasAnalysis> newestFirst, {DesiredMix? blendTarget, int lookback = 10})`. Returns the blend target first (when given), then the distinct desired mixes of the first `lookback` analyses in order, with no duplicates.
  - `GasAnalysesDaoLike` gains `Future<void> update(String id, GasAnalysisEdit edit)`.

- [ ] **Step 1: Write the migration** `supabase/migrations/0020_gas_analysis_label_fields.sql`:
  - a header comment covering what the columns are (spec "Data") and that a null `gas_role` means bailout/deco;
  - three `alter table gas_analyses add column if not exists …` statements: `target_o2_percent integer`, `target_he_percent integer`, `gas_role text`;
  - `NOTIFY pgrst, 'reload schema';`.
  - No grants (the table exists) and no publication change.

Run: `./supabase/lint_migrations.sh`
Expected: exit 0.

- [ ] **Step 2: Write the failing tests**
  - `gas_analysis_test.dart`:
    - `GasRole.fromDb`: `null`, `'bailout'`, `'stage'` and `''` → `bailout`; `'diluent'` → `diluent`.
    - `gasRoleForCylinderRole`: `'diluent'` → diluent; `'oxygen'`, `'offboard'`, `'bailout'` and `null` → bailout.
    - `DesiredMix(21, 35).name == 'Tx21/35'`, `DesiredMix(21, 0).name == 'Air'`, and value equality.
    - `GasAnalysis.desiredMix` is null without a target O2, and `DesiredMix(32, 0)` when the target O2 is 32 and the target He is null.
    - `match` is null without a desired mix.
    - `recentDesiredMixes`:
      - the blend target comes first;
      - duplicates of the blend target and of each other are dropped;
      - only the first 10 analyses count (the 11th's mix is excluded);
      - analyses without a desired mix are skipped.
    - `applyEdit` changes only the four editable fields.
  - `gas_analyses_dao_test.dart`:
    - `add` round-trips `desiredMix` and `gasRole`;
    - `update` changes the desired mix, role, analysed by (trimmed, blank → null) and notes, bumps `version` to 2 and sets `updated_at`, and leaves `o2_percent` unchanged;
    - a row inserted with raw SQL with `gas_role = 'weird'` and null targets reads as `GasRole.bailout` with a null `desiredMix` (**Review Focus 4**);
    - `listCylinderChoices` returns `role` (the existing `insertCylinder` helper writes `'bailout'`).
  - `gas_analysis_csv_test.dart`: the header ends with `desired_mix`, `gas_role`; a row with a desired 21/35 diluent ends `"Tx21/35","diluent"`; a row with no desired mix and a null role ends `"","bailout"`.
  - `powersync_schema_test.dart`: `gas_analyses` has the columns `target_o2_percent` (integer), `target_he_percent` (integer) and `gas_role` (text).

- [ ] **Step 3: Run the tests to verify they fail**

Run: `flutter test test/data test/sync/cloud/powersync_schema_test.dart`
Expected: FAIL (compile errors on the new names).

- [ ] **Step 4: Implement**
  - Model types and getters per the Interfaces block.
  - DAO:
    - `add` writes `target_o2_percent`, `target_he_percent` and `gas_role`;
    - `_rowToAnalysis` reads them, with `GasRole.fromDb` for the role;
    - `listCylinderChoices` selects `role`;
    - `update` follows `softDelete`'s pattern: in a `writeTransaction`, read `version`, write the four fields plus `updated_at = now`, `version + 1`, and use `blankToNull` for the strings. Do nothing if the id doesn't exist.
  - PowerSync schema: add the three columns after `notes`.
  - CSV:
    - append `desired_mix` (the `desiredMix?.name` or empty) and `gas_role` (the `dbValue`) to the header and to every row;
    - update the doc comment's column list.
  - Fake DAO:
    - `add` stores the new fields through `GasAnalysis.fromNew`;
    - `update` replaces the entry with `applyEdit` and records `(id, edit)` in a new `final List<(String, GasAnalysisEdit)> updated`.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `flutter test && flutter analyze`
Expected: all pass. Existing tests that construct `CylinderChoice` or `GasAnalysis` still compile, because the new parameters are optional.

- [ ] **Step 6: Commit**

```bash
git add supabase/migrations/0020_gas_analysis_label_fields.sql lib/data lib/sync/cloud/powersync_schema.dart test/_helpers/fake_gas_analyses_dao.dart test/data test/sync/cloud/powersync_schema_test.dart
git commit -m "feat(analyzer): store desired mix and gas role with each analysis (#114)"
```

Don't run the migration against production. Egbert deploys 0020 before any build with this code ships (see the release note at the end of this plan).

---

### Task 3: The label model and MOD rule

**Files:**
- Create: `lib/labels/cylinder_label.dart`
- Test: `test/labels/cylinder_label_test.dart`

**Interfaces:**
- Consumes: `GasAnalysis`, `DesiredMix`, `GasRole` (Task 2); `MixMatchLevel` (Task 1); `modMeters` (`lib/analysis/mod.dart`); `gasMixName`, `kHeliumNoiseFloorPercent` (`lib/analysis/gas_naming.dart`).
- Produces:
  - `int? floorDepthMeters(double o2Percent, double ppO2)`: the floor of `modMeters(o2Percent / 100, ppO2)`, or null when that isn't finite or is below 0.
  - `double bailoutModPpo2({required int o2PercentForRule, required bool use14ForDeeperMixes})`
  - `enum CylinderLabelKind { bailout, diluent }`
  - `class CylinderLabel` with:
    - fields `kind`, `mixName`, `String? analysedBy` (trimmed, null when blank), `int? headlineMeters`, `double headlinePpo2`, `double o2Percent`, `double? hePercent` (null below `kHeliumNoiseFloorPercent`), `DateTime analysedAt`;
    - for diluent only: `int? setpointMeters` (ppO2 1.3) and `int? mod16Meters` (ppO2 1.6), both null on bailout.
  - String getters on `CylinderLabel`, which the renderer draws as-is:
    - `String? get barTag`: `'DIL'` or null;
    - `String get headlineText`: `'67'`, or `'–'` when `headlineMeters` is null;
    - `String get headlineCaption`: `'MOD 1.6'`, `'MOD 1.4'` or `'TOD 1.1'`;
    - `String? get diluentLeft`: `'1.3: 53 m'`;
    - `String? get diluentRight`: `'MOD 1.6: 67 m'`;
    - `String get footerLeft`: `'O2 20.6  He 33.8'` (two spaces), or `'O2 32.1'` without He;
    - `String get footerRight`: `'31 Oct 26'`.
  - `factory CylinderLabel.fromAnalysis(GasAnalysis a, {required bool use14ForDeeperMixes})`
  - `factory CylinderLabel.testLabel({required DateTime now, required bool use14ForDeeperMixes})`: desired Tx21/35, analysed 20.6 / 33.8, bailout, no initials.

- [ ] **Step 1: Write the failing tests.** Build each `GasAnalysis` with the constructor, dated `DateTime(2026, 10, 31, 18, 5)`.
  - **Bailout:**
    - desired 21/35, analysed 20.6/33.8, setting off → `Tx21/35`, `67`, `MOD 1.6`;
    - the same with the setting on → `57`, `MOD 1.4`;
    - desired 50/0, analysed 49.6/0, setting on → `EAN50`, `22`, `MOD 1.6`;
    - desired 49/0, analysed 49.6/0, setting on → `18`, `MOD 1.4`;
    - no desired mix, analysed 49.6/0, setting on → `EAN50`, `22`, `MOD 1.6` (rounds to 50);
    - no desired mix, analysed 49.4/0, setting on → `EAN49`, `18`, `MOD 1.4`;
    - 3-digit: analysed 11.4/70.2 with desired 11/70 → `130`;
    - O2: desired 100/0, analysed 99.6/0 → `O2`, `6`, `MOD 1.6`.
  - **Mismatch** (spec examples):
    - desired 50/0, analysed 32.0/0, setting on → hard → `EAN32`, `MOD 1.4`, `33`;
    - desired 32/0, analysed 36.5/0, setting off → red → keeps `EAN32`, `33`, `MOD 1.6`.
  - **Diluent:**
    - role diluent, desired 21/35, analysed 20.6/33.8 → `barTag == 'DIL'`, `43`, `TOD 1.1`, `1.3: 53 m`, `MOD 1.6: 67 m`;
    - the same with the setting on gives identical values;
    - `gasRole: GasRole.bailout` (and the default) gives `kind == bailout`, a null `barTag` and a null `diluentLeft`.
  - **Text:**
    - He 0.4 → `footerLeft == 'O2 20.6'`;
    - He 33.8 → `'O2 20.6  He 33.8'`;
    - `footerRight == '31 Oct 26'`;
    - analysedBy `'  '` → null;
    - analysedBy `' EdP '` → `'EdP'`.
  - **Locale (Review Focus 3):** with `Intl.defaultLocale = 'nl_NL'` (reset in `tearDown`), `footerRight` is still `'31 Oct 26'` and `footerLeft` still uses `.` decimals.
  - `floorDepthMeters(20.6, 1.6) == 67`, and `floorDepthMeters(0, 1.6) == null`.
  - `CylinderLabel.testLabel(now: DateTime(2026, 10, 31), use14ForDeeperMixes: false)` → `Tx21/35`, `67`.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/labels/cylinder_label_test.dart`
Expected: FAIL, file not found.

- [ ] **Step 3: Implement `lib/labels/cylinder_label.dart`.** Pure Dart.
  - Decide whether the analysis is a hard mismatch with `a.match?.level == MixMatchLevel.hard`.
  - Use the desired name and desired O2 for the rule unless there's no desired mix or the match is hard. Then use `gasMixName(analysedO2, analysedHe)` and `analysedO2.round()`.
  - Always compute depths from the analysed O2.
  - Format the ppO2 in captions with `toStringAsFixed(1)`.
  - Create the date format once: `DateFormat('d MMM yy', 'en_US')`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/labels && flutter analyze`
Expected: all pass. The pure-Dart grep from Global Constraints prints nothing.

- [ ] **Step 5: Commit**

```bash
git add lib/labels/cylinder_label.dart test/labels/cylinder_label_test.dart
git commit -m "feat(labels): cylinder label model and MOD rule (#114)"
```

---

### Task 4: Printer interface, bitmap and Phomemo encoder

**Files:**
- Create: `lib/label_printer/label_bitmap.dart`, `lib/label_printer/label_printer.dart`, `lib/label_printer/phomemo/phomemo_encoder.dart`, `lib/label_printer/phomemo/phomemo_status.dart`
- Test: `test/label_printer/label_bitmap_test.dart`, `test/label_printer/phomemo/phomemo_encoder_test.dart`, `test/label_printer/phomemo/phomemo_status_test.dart`

**Interfaces:**
- Produces:
  - `label_bitmap.dart`:
    - constants `kLabelWidthDots = 384`, `kLabelHeightDots = 240`, `kLabelSafeMarginDots = 12`;
    - `class LabelBitmap { final int width; final int height; final Uint8List bits; int get bytesPerRow; bool isBlack(int x, int y); }`. Rows are packed MSB-first, 1 = black, and `bytesPerRow = (width + 7) ~/ 8`;
    - `factory LabelBitmap.blank(int width, int height)`;
    - `LabelBitmap bitmapFromRgba(Uint8List rgba, int width, int height, {int threshold = 128})`. A pixel is black when its luminance `(299 R + 587 G + 114 B) / 1000` is below `threshold`; transparent pixels are white.
  - `label_printer.dart`:
    - `enum PrinterFault { noLabels, coverOpen, overheated, lowBattery }`;
    - `String printerFaultMessage(PrinterFault f)`: `'Out of labels'`, `'Printer cover is open'`, `'Printer is overheated. Let it cool down.'`, `'Printer battery is low'`;
    - `class LabelPrinterException implements Exception { const LabelPrinterException(this.message, {this.fault}); final String message; final PrinterFault? fault; }`. Its `toString()` returns `message`;
    - `bool isFatalPrinterFault(PrinterFault f)`: true for everything except `lowBattery`;
    - `abstract class LabelPrinter { Stream<PrinterFault> get faults; Future<void> connect(); Future<List<PrinterFault>> printLabel(LabelBitmap bitmap, {int copies = 1}); Future<void> disconnect(); }`. `printLabel` returns the non-fatal faults seen during the job and throws `LabelPrinterException(fault: …)` on a fatal one;
    - `class FoundLabelPrinter { final String id; final String name; }`;
    - `abstract class LabelPrinterScanner { Stream<List<FoundLabelPrinter>> scan({Duration timeout = const Duration(seconds: 10)}); Future<void> stop(); }`.
  - `phomemo_encoder.dart`:
    - `Uint8List encodePhomemoM110Job(LabelBitmap bitmap, {int copies = 1, int density = kPhomemoDefaultDensity, int speed = kPhomemoDefaultSpeed})`;
    - `class PhomemoWrite` and `List<PhomemoWrite> planPhomemoM110Writes(...)` (Step 3);
    - `List<Uint8List> chunkBytes(Uint8List data, int chunkSize)`;
    - the constants named in Step 3.
  - `phomemo_status.dart`: `enum PhomemoEvent { jobDone, noLabels, coverOpen, lowBattery }` and `PhomemoEvent? parsePhomemoNotification(List<int> bytes)`. Returns null for unknown bytes.

- [ ] **Step 1: Write the failing tests**
  - `label_bitmap_test.dart`:
    - `blank(384, 240)` has 48 bytes per row and 11 520 bytes, all white;
    - in `bitmapFromRgba` on a 9 × 2 image, black pixels at (0,0) and (8,1) set bit 7 of byte 0 and bit 7 of byte 3, with `bytesPerRow == 2`;
    - a mid-grey of 127 is black and 128 is white;
    - alpha 0 is white.
  - `phomemo_encoder_test.dart`, for a 384 × 2 bitmap whose first row is all black and second row all white:
    - the job is exactly `1B 4E 0D 05 1B 4E 04 0A 1F 11 0A 1D 76 30 00 30 00 02 00`, then 48 × `FF`, then 48 × `00`, then `1F F0 05 00 1F F0 03 00` (123 bytes);
    - a blank 384 × 240 job is 11 547 bytes, with `30 00 F0 00` as the width and height;
    - `copies: 2` is the single job twice (246 bytes);
    - `copies` is clamped to 1–9;
    - `density: 0x0D` changes byte 7 only;
    - a bitmap that isn't 384 wide throws `ArgumentError`;
    - `chunkBytes` of 250 bytes at 100 gives chunk lengths `[100, 100, 50]`, and the chunks concatenate back to the input.
    - `planPhomemoM110Writes` for 384 × 240 has 95 writes:
      - the first 4 pause 30 ms;
      - writes 5–93 are 128-byte raster chunks pausing 20 ms;
      - write 94, the last raster chunk, pauses 300 ms;
      - write 95 is the 8-byte footer pausing 500 ms;
      - all 95 concatenate to `encodePhomemoM110Job`.
  - `phomemo_status_test.dart`:
    - each row of Step 3's status table;
    - `1A 05 99`, `1A 04 5A`, `1A 03 A9`, `01 01` and `[]` all → null.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/label_printer`
Expected: FAIL, files not found.

- [ ] **Step 3: Implement.** Pure Dart. The M110 byte sequence comes from the reference implementations below. It has **not** been verified on hardware. Name each command as a constant with a comment citing its source, so the bench session (Task 15) can correct one value at a time.

  **Sources** (researched 2026-10-31):
  - vivier/phomemo-tools `2b76748`: `cups/filter/rastertopm110.py`, README.
  - transcriptionstream/phomymo `1f58d3f`: `printer.js`, `ble.js`.
  - Knightro63/phomemo `1c015d7`: the pub.dev package.
  - Niko11111/SpoolmanScale `ee704a5`: `phomemo_m_series.h`, `ble_service.cpp`.
  - yaddran/thermal-print `73dd564`: the origin of phomymo's status parser.

  **One label (`phomemo_encoder.dart`).** All four print sources agree on this sequence. There is no `ESC @` init (vivier removed it after testing on an M110).

  | Constant | Bytes | Notes |
  |---|---|---|
  | speed | `1B 4E 0D <speed>` | `kPhomemoDefaultSpeed = 5` (range 1–5; every source sends 5) |
  | density | `1B 4E 04 <density>` | `kPhomemoDefaultDensity = 0x0A` (vivier's filter and SpoolmanScale use 10; phomymo's default sends 0x0D; range up to 0x0F) |
  | media | `1F 11 <media>` | `kPhomemoMediaGapLabel = 0x0A` (0x0B continuous, 0x26 black mark) |
  | raster | `1D 76 30 00 <w LE16> <h LE16>` + `w × h` bytes | `w` = 48 bytes per row (384 dots), all 240 rows in one block (no M110 row limit) |
  | footer | `1F F0 05 00 1F F0 03 00` | Meaning undocumented in every source |

  - **Copies:** repeat the whole sequence, header + raster + footer, once per copy, as vivier does per page.
  - **Bits:** MSB first, 1 = black, which is how `LabelBitmap` is already packed.
  - **Expected values:** a 384 × 2 job is `1B 4E 0D 05 1B 4E 04 0A 1F 11 0A 1D 76 30 00 30 00 02 00`, then the 96 raster bytes, then the footer: 123 bytes. A 384 × 240 job is 11 547 bytes.

  **Writing it over BLE.** This is pure Dart, so it's tested here; Task 6 only executes it.
  - Add `class PhomemoWrite { final Uint8List bytes; final Duration pauseAfter; }` and `List<PhomemoWrite> planPhomemoM110Writes(LabelBitmap bitmap, {int copies = 1, int density = kPhomemoDefaultDensity, int speed = kPhomemoDefaultSpeed, int chunkSize = kPhomemoChunkSize})`. This follows phomymo's pacing, with SpoolmanScale's 20 ms gap:
    - each of the 3 header commands is one write, with `kPhomemoCommandPause` (30 ms) after it;
    - the 8-byte raster header is one write with 30 ms after it;
    - the raster data goes in `chunkSize` pieces (`kPhomemoChunkSize = 128`) with `kPhomemoChunkPause` (20 ms) between them. The last chunk waits `kPhomemoBeforeFooterPause` (300 ms);
    - the footer is one write with `kPhomemoAfterFooterPause` (500 ms) after it.
  - `encodePhomemoM110Job` returns the concatenated bytes of the same plan.
  - **BLE constants:** `kPhomemoServiceUuid = 'ff00'`, `kPhomemoWriteUuid = 'ff02'`, `kPhomemoNotifyUuid = 'ff03'` (phomymo and SpoolmanScale agree).
  - **Name prefixes:** `kPhomemoNamePrefixes = ['Q199', 'M110', 'M120', 'M220']`. Only `Q199…` is seen in the sources (the M110S and M-series examples); the others are a guess from the model names.
  - **Status queries:** `kPhomemoQueryPaper = 1F 11 11`, `kPhomemoQueryCover = 1F 11 12`, `kPhomemoQueryBattery = 1F 11 08`.
  - **Done timeout:** `kPhomemoDoneTimeout = 3 s` per copy.

  **Status (`phomemo_status.dart`).** Define `enum PhomemoEvent { jobDone, noLabels, coverOpen, lowBattery }` and `PhomemoEvent? parsePhomemoNotification(List<int> bytes)`. Use it instead of returning `PrinterFault` directly. Only `1A 0F 0C` (done) has been seen on hardware, and only on an M220. The rest come from one source, written for a Q30 and never checked on an M110.

  | Bytes | Event |
  |---|---|
  | `1A 0F 0C` | `jobDone` |
  | `1A 06 88` | `noLabels` (paper out) |
  | `1A 05 98` | `coverOpen` (`1A 05 99` = closed → null) |
  | `1A 04 A4` | `lowBattery` (battery level 0; other `1A 04 xx` → null) |
  | `01 xx` | null (per-chunk ack seen on the M220; ignored until the bench shows the M110 sends it) |
  | `1A 03 xx` | null. "Hot" status, but no source says which value means overheated, so `PrinterFault.overheated` stays unmapped until Task 15 records it. |
  | anything else | null |

  **Fault severity:** in `label_printer.dart`, `lowBattery` is a warning and the others are fatal. `LabelPrinter.printLabel` therefore returns `Future<List<PrinterFault>>`, the warnings seen during the job. A fatal fault throws.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/label_printer && flutter analyze`
Expected: all pass. The pure-Dart grep prints nothing.

- [ ] **Step 5: Commit**

```bash
git add lib/label_printer test/label_printer
git commit -m "feat(labels): label printer interface and Phomemo M110 encoder (#114)"
```

---

### Task 5: Render a label to a 1-bit bitmap

**Files:**
- Create: `lib/labels/render/cylinder_label_renderer.dart`
- Test: `test/labels/render/cylinder_label_renderer_test.dart`, with goldens in `test/labels/render/goldens/`

**Interfaces:**
- Consumes: `CylinderLabel` (Task 3); `LabelBitmap`, `bitmapFromRgba` and the `kLabel*` constants (Task 4).
- Produces:
  - `class CylinderLabelRender { final LabelBitmap bitmap; final Rect bar; final Rect mixName; final Rect? initials; final Rect? tag; final Rect headline; }`. The rects are in dots, where each element was drawn.
  - `Future<CylinderLabelRender> renderCylinderLabelWithLayout(CylinderLabel label)`
  - `Future<LabelBitmap> renderCylinderLabel(CylinderLabel label)`: the `bitmap` of the call above. It's the `LabelRenderer` the app uses.
  - `Future<ui.Image> renderCylinderLabelImage(CylinderLabel label)`: the 1-bit result as a black-and-white image, for goldens and a future preview.

- [ ] **Step 1: Write the failing tests.**
  - Use plain `test()` with `TestWidgetsFlutterBinding.ensureInitialized()`.
  - In `setUpAll`, load the bundled font: `FontLoader('Inter')..addFont(rootBundle.load('fonts/Inter-VariableFont.ttf'))`, then `await loader.load()`.
  - **Structural tests (run everywhere):**
    - the bitmap is 384 × 240;
    - no black pixel lies within 12 dots of any edge, so the bar stays inside the margin too;
    - `bar`, `mixName`, `initials`, `tag` and `headline` all lie inside `Rect.fromLTRB(12, 12, 372, 228)`;
    - at least 60 % of the pixels inside `bar` are black;
    - `headline` contains black pixels;
    - diluent: `tag` is non-null, inside `bar`, left of `mixName`, and contains white pixels;
    - bailout: `tag` is null;
    - the `130` headline (Tx11/70 at 11.4 %) fits: `headline.right <= 372`.
  - **Review Focus 5:**
    - `analysedBy: 'Egbert de Pauw'` with mix `Tx21/35` renders without throwing;
    - its `mixName` rect equals the one from the same label with no initials, so the name wasn't shortened;
    - `initials.left >= mixName.right` and `initials.right <= 372`.
  - **Goldens (macOS only):** CI runs Ubuntu, and font rasterization differs between the two. Mark each `skip: !Platform.isMacOS`. Cover:
    - `tx2135_bailout.png`: desired 21/35, 20.6/33.8, setting off;
    - `ean50_bailout.png`: 50/0, 50.1/0;
    - `o2_bailout.png`: 100/0, 99.6/0;
    - `tx1170_130m.png`: 11/70, 11.4/70.2;
    - `tx2135_diluent.png`: diluent, 20.6/33.8;
    - `long_initials.png`.
    - Use `expectLater(await renderCylinderLabelImage(label), matchesGoldenFile('goldens/<name>.png'))`.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/labels/render`
Expected: FAIL, file not found.

- [ ] **Step 3: Implement `lib/labels/render/cylinder_label_renderer.dart`**
  - Draw with `ui.PictureRecorder` + `Canvas` on a white 384 × 240 background, `TextPainter` for text, then `toImage`, `toByteData(format: rawRgba)` and `bitmapFromRgba`.
  - Font: `fontFamily: 'Inter'`, `fontWeight: FontWeight.w800`, plus `fontVariations: [FontVariation('wght', 800)]` (variable font).
  - Layout follows the spec's two diagrams:
    - **Black bar:** about 52 dots tall. The mix name is on the left, white, never truncated. `analysedBy` is on the right, `maxLines: 1` with an ellipsis, in whatever width the mix name leaves. The diluent `DIL` tag is an outlined white box before the mix name.
    - **Headline:** as large as fits. Shrink the font until the number plus `m` fits the content width, with `130` as the design case. The caption goes underneath or beside it, small.
    - **Diluent line:** above the footer, left and right.
    - **Footer:** at the bottom margin, left and right.
  - The exact pixel positions are left to the builder. Generate goldens with `flutter test --update-goldens test/labels/render` on macOS, then look at each PNG before committing.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/labels/render && flutter analyze`
Expected: all pass on macOS. On Linux the goldens are skipped and the structural tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/labels/render test/labels/render
git commit -m "feat(labels): render cylinder labels to a 1-bit bitmap (#114)"
```

---

### Task 6: Phomemo BLE transport and scanner

**Files:**
- Create: `lib/label_printer/phomemo/ble/phomemo_ble_printer.dart`, `lib/label_printer/phomemo/ble/phomemo_ble_scanner.dart`
- Modify: `ios/Runner/Info.plist` (both Bluetooth usage strings), `macos/Runner/Info.plist`

**Interfaces:**
- Consumes: `LabelPrinter`, `LabelPrinterScanner`, `FoundLabelPrinter`, `PrinterFault`, `isFatalPrinterFault`, `printerFaultMessage`, `LabelPrinterException` (Task 4); `planPhomemoM110Writes`, `PhomemoWrite`, `parsePhomemoNotification`, `PhomemoEvent` and the UUID, name, query and timing constants (Task 4).
- Produces:
  - `class PhomemoBlePrinter implements LabelPrinter { PhomemoBlePrinter({required String remoteId}); }`
  - `class PhomemoBleScanner implements LabelPrinterScanner { PhomemoBleScanner(); }`

This layer has no protocol logic and no unit tests. Everything testable is in Task 4. It's verified on hardware in Task 15.

- [ ] **Step 1: Implement `PhomemoBlePrinter`**, mirroring `lib/shearwater/ble/ble_io_impl.dart`:
  - **`connect()`:**
    - wait up to 10 s for `FlutterBluePlus.adapterState` to reach `on`, as `ImportNotifier._startRealScan` does; otherwise throw `LabelPrinterException('Bluetooth is off')`;
    - `BluetoothDevice.fromId(remoteId).connect(timeout: 10 s)`;
    - on Android, `requestMtu(247)` (ignore failures);
    - `discoverServices()`, then find the service and the write/notify characteristics by `Guid`. If any is missing, throw `LabelPrinterException('Not a supported Phomemo printer')`;
    - `setNotifyValue(true)`;
    - listen to `onValueReceived` and map each value with `parsePhomemoNotification`. Keep the events in a broadcast stream inside the class, and expose `faults` with `noLabels` → `PrinterFault.noLabels`, `coverOpen` → `coverOpen` and `lowBattery` → `lowBattery`.
  - **`printLabel(bitmap, copies)`:**
    1. **Pre-print check:** send `kPhomemoQueryPaper`, `kPhomemoQueryCover` and `kPhomemoQueryBattery` 100 ms apart, then wait 300 ms. A `noLabels` or `coverOpen` answer throws before any raster is sent. No answer is fine.
    2. Execute `planPhomemoM110Writes(bitmap, copies: copies, chunkSize: min(kPhomemoChunkSize, mtuNow - 3))` in order, pausing each write's `pauseAfter`.
       - Write without response when the characteristic supports it, else with response.
       - A write that throws is back pressure (SpoolmanScale saw this on an M220): retry every 25 ms, up to 40 times, then throw `LabelPrinterException('Printer connection lost')`.
    3. After the last write, wait up to `kPhomemoDoneTimeout × copies` for `copies` `jobDone` events. Reaching the timeout counts as printed, since the M110 may not send `1A 0F 0C`; Task 15 checks. Don't disconnect before this wait ends: vivier found that closing the link too early stops the print.
    4. A fatal fault at any point stops the writes and throws `LabelPrinterException(printerFaultMessage(f), fault: f)`.
    5. Return the warnings (`lowBattery`) seen.
  - **`disconnect()`:** cancel the subscription, close the stream, `device.disconnect()`, and swallow errors.
  - Any `FlutterBluePlusException` or `TimeoutException` from `connect` → `LabelPrinterException('Printer not found')`.

- [ ] **Step 2: Implement `PhomemoBleScanner`**
  - Wait for the adapter like Step 1, then subscribe to `FlutterBluePlus.scanResults` before calling `startScan(timeout:)`.
  - Emit the accumulated, de-duplicated (by `remoteId`), name-sorted list of results that advertise `kPhomemoServiceUuid` or whose `advName` / `platformName` starts with one of `kPhomemoNamePrefixes`. Use the advertised name as `FoundLabelPrinter.name`, falling back to `'Phomemo printer'`.
  - `stop()` calls `FlutterBluePlus.stopScan()` and cancels the subscription.

- [ ] **Step 3: Update the Bluetooth usage strings**
  - `ios/Runner/Info.plist`, both `NSBluetoothAlwaysUsageDescription` and `NSBluetoothPeripheralUsageDescription`: "Anchorline uses Bluetooth to import dive logs from your Shearwater dive computer and to print cylinder labels on a Bluetooth label printer."
  - `macos/Runner/Info.plist`: the same sentence.

- [ ] **Step 4: Verify**

Run: `flutter analyze && flutter test`
Expected: clean; all pass.

- [ ] **Step 5: Commit**

```bash
git add lib/label_printer/phomemo/ble ios/Runner/Info.plist macos/Runner/Info.plist
git commit -m "feat(labels): Phomemo BLE transport and printer scan (#114)"
```

---

### Task 7: Printer settings and the print service

**Files:**
- Create: `lib/labels/label_print_service.dart`
- Modify: `lib/ui/notifiers/settings_notifier.dart`
- Test: `test/labels/label_print_service_test.dart`, `test/ui/notifiers/settings_notifier_label_test.dart`
- Create (test helper): `test/_helpers/fake_label_printer.dart`

**Interfaces:**
- Consumes: `CylinderLabel` (Task 3); `LabelBitmap`, `LabelPrinter`, `LabelPrinterScanner`, `FoundLabelPrinter`, `LabelPrinterException` (Task 4); `GasAnalysis` (Task 2).
- Produces:
  - `lib/labels/label_print_service.dart` (pure Dart):
    - `typedef LabelRenderer = Future<LabelBitmap> Function(CylinderLabel label);`
    - `typedef LabelPrinterFactory = LabelPrinter Function(String printerId);`
    - `class LabelPrintService { LabelPrintService({required LabelRenderer render, required LabelPrinterFactory printerFor, required LabelPrinterScanner scanner, required String? Function() printerId, required bool Function() use14ForDeeperMixes, Duration connectTimeout = const Duration(seconds: 15), DateTime Function() now = DateTime.now}); }`
    - members: `LabelPrinterScanner get scanner`, `bool get isConfigured`, `CylinderLabel labelFor(GasAnalysis a)`, `Future<List<PrinterFault>> printAnalysis(GasAnalysis a, {int copies = 1})` and `Future<List<PrinterFault>> printTestLabel()`. Both return the printer's warnings.
  - `SettingsNotifier`:
    - `bool get labelUse14ForDeeperMixes` (key `label_use_14_for_deeper_mixes`, default false) and `Future<void> setLabelUse14ForDeeperMixes(bool v)`;
    - `String? get labelPrinterId` and `String? get labelPrinterName` (keys `label_printer_id` and `label_printer_name`);
    - `Future<void> setLabelPrinter({required String id, required String name})` and `Future<void> forgetLabelPrinter()`.
  - `test/_helpers/fake_label_printer.dart`:
    - `FakeLabelPrinter implements LabelPrinter` records `connects`, `printed` (a list of `(LabelBitmap, int copies)`) and `disconnects`. Its constructor options are `Object? failOnConnect`, `bool hangOnConnect`, `PrinterFault? faultOnPrint` (thrown as `LabelPrinterException`), `List<PrinterFault> warnings` (returned by `printLabel`), and an optional `Completer<void>? printGate`, so tests can hold a print in flight;
    - `FakeLabelPrinterScanner implements LabelPrinterScanner` emits a given list.

- [ ] **Step 1: Write the failing tests**
  - `settings_notifier_label_test.dart`, using `SharedPreferences.setMockInitialValues`:
    - the defaults are false / null / null;
    - each setter persists and a fresh `load()` reads it back;
    - `forgetLabelPrinter()` clears both id and name;
    - setters notify listeners.
  - `label_print_service_test.dart`, with a fake renderer that returns `LabelBitmap.blank(384, 240)` and records each label:
    - `isConfigured` follows `printerId()`;
    - `printAnalysis` connects, prints once with `copies`, and disconnects;
    - `copies: 12` is sent as 9 and `copies: 0` as 1;
    - with `printerId()` returning null, `printAnalysis` throws `LabelPrinterException` with `'No label printer set up'`;
    - `failOnConnect` → `LabelPrinterException('Printer not found')`, and disconnect is still called;
    - **Review Focus 1:** `hangOnConnect` under `fakeAsync`, after `connectTimeout`, throws `'Printer not found'`;
    - `faultOnPrint: PrinterFault.noLabels` → the exception carries `fault == noLabels`, and disconnect is called;
    - `warnings: [PrinterFault.lowBattery]` → `printAnalysis` completes and returns `[lowBattery]`;
    - `labelFor` reads `use14ForDeeperMixes()` at call time: flip the closure's value between two calls and the second label shows `MOD 1.4` (a reprint uses the current setting);
    - `printTestLabel` renders `CylinderLabel.testLabel` with today's date from `now`.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/labels/label_print_service_test.dart test/ui/notifiers/settings_notifier_label_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement**
  - **`LabelPrintService.printAnalysis`:**
    - resolve the printer id, then render the label before connecting, so a render error doesn't hold the BLE link;
    - `connect().timeout(connectTimeout)`. Pass a `LabelPrinterException` through unchanged; map `TimeoutException` and any other error to `LabelPrinterException('Printer not found')`;
    - `printLabel(bitmap, copies: copies.clamp(1, 9))`;
    - always `disconnect()` in `finally` and ignore its errors.
  - **`SettingsNotifier`:** add the fields, the `load()` lines and the setters in the existing style (key constants at the top, next to `_kAnalyzerModPpo2s`).

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test && flutter analyze`
Expected: all pass. The pure-Dart grep prints nothing.

- [ ] **Step 5: Commit**

```bash
git add lib/labels/label_print_service.dart lib/ui/notifiers/settings_notifier.dart test/labels/label_print_service_test.dart test/ui/notifiers/settings_notifier_label_test.dart test/_helpers/fake_label_printer.dart
git commit -m "feat(labels): label print service and printer settings (#114)"
```

---

### Task 8: Settings → Label printer

**Files:**
- Create: `lib/ui/widgets/label_printer_settings_section.dart`
- Modify: `lib/ui/screens/settings_screen.dart`
- Test: `test/ui/widgets/label_printer_settings_section_test.dart`

**Interfaces:**
- Consumes: `LabelPrintService`, `FakeLabelPrinter`, `FakeLabelPrinterScanner` (Task 7); `SettingsNotifier` label members (Task 7).
- Produces:
  - `class LabelPrinterSettingsSection extends StatelessWidget { const LabelPrinterSettingsSection({super.key, required this.settings, required this.printing}); }`
  - `class LabelPrinterSettingsScreen extends StatelessWidget { const LabelPrinterSettingsScreen({super.key, required this.settings, required this.printing}); }`: a `Scaffold` titled "Label printer" holding the section. Task 12's "Set up label printer" link pushes it.
  - `SettingsScreen` gains an optional `final LabelPrintService? labelPrinting`. When set, the section appears after "Gas analyzer", with a `Divider(height: 32)` before it.

- [ ] **Step 1: Write the failing widget tests**
  - Setup: real `SettingsNotifier` on mock prefs, plus a `LabelPrintService` built on the fakes.
  - With no printer: a "No printer set up" line, a "Find printer" button (`label-printer-find`), and "Print test label" (`label-printer-test`) disabled.
  - **"Find printer":**
    - tapping it opens a dialog listing the fake scanner's results (`label-printer-result-<id>`);
    - tapping a result calls `setLabelPrinter`, and the section then shows the printer's name and "Forget printer" (`label-printer-forget`);
    - closing the dialog calls `scanner.stop()`.
  - **"Forget printer"** clears the printer.
  - **"Use 1.4 for deeper mixes"** (`label-printer-use14`) toggles `labelUse14ForDeeperMixes`. Subtitle: "MOD at ppO₂ 1.4 for mixes below 50 % O₂. Off: 1.6 for all mixes."
  - **"Print test label"** with a configured printer prints one label on the fake. With `failOnConnect`, a SnackBar shows "Printer not found".

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/ui/widgets/label_printer_settings_section_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement** the section, the screen and the `SettingsScreen` parameter. Rebuild the section with a `ListenableBuilder` on `settings`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test && flutter analyze`
Expected: all pass. The existing settings-screen tests are unchanged, because the section stays hidden without `labelPrinting`.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/widgets/label_printer_settings_section.dart lib/ui/screens/settings_screen.dart test/ui/widgets/label_printer_settings_section_test.dart
git commit -m "feat(labels): label printer settings (#114)"
```

---

### Task 9: Persist the Blend tab's target

**Files:**
- Modify: `lib/ui/notifiers/blend_notifier.dart`
- Test: `test/ui/notifiers/blend_notifier_target_test.dart`

**Interfaces:**
- Consumes: `DesiredMix` (Task 2).
- Produces:
  - the `BlendNotifier({required this.settings, DateTime Function()? now})` constructor;
  - `Future<void> loadTarget()`;
  - `DesiredMix? recentTarget()`: the target mix if it was edited in the last 24 h, otherwise null.

- [ ] **Step 1: Write the failing tests** (mock SharedPreferences, injected clock):
  - **Fresh install:** `recentTarget()` is null, even though the default target 18/45 exists.
  - **Edits:**
    - `setTargetMix(21, 35)` makes `recentTarget()` return `DesiredMix(21, 35)`;
    - advance the clock 23 h 59 min → still returned;
    - advance it to 24 h 1 min → null;
    - `setTargetPressure(200)` also counts as an edit.
  - **Persistence:** after `setTargetMix(21, 35)` and `setTargetPressure(200)`, a new notifier plus `loadTarget()` restores 21 / 35 / 200 bar and the edited-at time.
  - `loadTarget()` itself doesn't change the edited-at time.
  - `loadTarget()` with nothing stored keeps the defaults 18 / 45 / 230.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/ui/notifiers/blend_notifier_target_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement.**
  - Keys: `blend_target_o2`, `blend_target_he`, `blend_target_pressure_bar`, `blend_target_edited_at` (millis).
  - `setTargetMix` and `setTargetPressure` set the edited-at time from `now()` and write the prefs without awaiting in the setter, the same fire-and-forget style `SettingsNotifier` setters use after `notifyListeners()`.
  - `loadTarget()` applies the stored values through the private fields, recomputes and notifies.
  - Replace the library doc's "blend drafts are session-scoped" sentence: the target is now persisted on the device, and why.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test && flutter analyze`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/notifiers/blend_notifier.dart test/ui/notifiers/blend_notifier_target_test.dart
git commit -m "feat(blend): keep the target mix on the device (#114)"
```

---

### Task 10: Analyzer screen: floored MODs, and demo readings can't be saved

**Files:**
- Modify: `lib/ui/screens/analyzer_screen.dart`
- Test: `test/ui/screens/analyzer_screen_test.dart`, `test/ui/screens/analyzer_save_analysis_test.dart`

**Interfaces:**
- Produces: `AnalyzerTransportOption` gains `final bool isDemo` (default `false`). The built-in "Demo" option in `defaultAnalyzerTransportOptions()` sets `isDemo: true`.

- [ ] **Step 1: Update and add tests**
  - In `analyzer_screen_test.dart`, the 1.4 row for 18.2 % now expects `'66 m'` (66.9 floored). Update the comment to say floored.
  - New test: `defaultAnalyzerTransportOptions()` contains exactly one option with `isDemo`, and its label is `'Demo'`.
  - New test in `analyzer_save_analysis_test.dart`: pump with a single option `AnalyzerTransportOption(label: 'Demo', isDemo: true, create: …)` and a DAO. The `analysis-save-card` finds nothing. The existing tests, whose demo option leaves `isDemo` false, still find the card.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/ui/screens/analyzer_screen_test.dart test/ui/screens/analyzer_save_analysis_test.dart`
Expected: FAIL (`67 m` is still shown; `isDemo` doesn't exist).

- [ ] **Step 3: Implement**
  - In `_PlanningCard`'s MOD rows, `'${m.floor()} m'` replaces `toStringAsFixed(0)`. Leave END, min depth and density as they are.
  - Add `isDemo` to `AnalyzerTransportOption` and set it on the built-in Demo option.
  - `_saveCard()` returns `const []` when `_options[_selected].isDemo`. The selection can't change while connected, so this matches the live transport.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test && flutter analyze`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/screens/analyzer_screen.dart test/ui/screens/analyzer_screen_test.dart test/ui/screens/analyzer_save_analysis_test.dart
git commit -m "feat(analyzer): floor MODs and keep demo readings out of the log (#114)"
```

---

### Task 11: Shared label UI pieces

**Files:**
- Create: `lib/ui/widgets/desired_mix_picker.dart`, `lib/ui/widgets/mix_match_indicator.dart`, `lib/ui/widgets/mix_mismatch_dialog.dart`, `lib/ui/widgets/label_print_controls.dart`
- Test: `test/ui/widgets/desired_mix_picker_test.dart`, `test/ui/widgets/mix_match_indicator_test.dart`, `test/ui/widgets/mix_mismatch_dialog_test.dart`, `test/ui/widgets/label_print_controls_test.dart`

**Interfaces:**
- Consumes: `DesiredMix`, `GasAnalysis` (Task 2); `gradeMix`, `mixMatchText`, `MixMatchLevel` (Task 1); `LabelPrintService` (Task 7); `LabelPrinterException`, `printerFaultMessage` (Task 4); `SafetyColors` (`lib/ui/theme/safety_colors.dart`).
- Produces:
  - `DesiredMixPicker({required List<DesiredMix> options, required DesiredMix? selected, required ValueChanged<DesiredMix?> onChanged})`.
    - One `ChoiceChip` per option (key `desired-mix-<o2>-<he>`), plus "Other…" (`desired-mix-other`).
    - Tapping the selected chip deselects it, i.e. calls `onChanged(null)`.
    - A selected mix that isn't in `options` (picked through "Other…") shows as an extra chip.
    - "Other…" opens a dialog with whole-number fields O2 (`desired-mix-other-o2`) and He (`desired-mix-other-he`, default 0) and OK (`desired-mix-other-ok`). Validation: O2 1–100, He 0–99, and O2 + He ≤ 100, with the error "O2 + He can't exceed 100 %".
  - `Color mixMatchColor(MixMatchLevel level)`: match → `SafetyColors.success`, orange → `SafetyColors.warning`, red and hard → `SafetyColors.danger`.
  - `MixMatchIndicator({required double o2Percent, required double hePercent, required DesiredMix desired})` (key `mix-match-indicator`). It shows `O2 20.6  He 33.8` in the level colour and, below it, `mixMatchText(...)` in the same colour, so the colour is never the only signal.
  - `enum MismatchChoice { printAnalysed, changeMix, cancel }` and `Future<MismatchChoice> showMixMismatchDialog(BuildContext context, {required GasAnalysis analysis})`:
    - the red header "Mix does not conform to analysis";
    - the body `Desired EAN50, analysed O2 32.1 % (EAN32). The label will show EAN32.`;
    - the buttons "Print as EAN32" (primary, `mix-mismatch-print`), "Change desired mix" (`mix-mismatch-change`) and "Cancel" (`mix-mismatch-cancel`);
    - dismissing it counts as cancel.
  - `CopiesStepper({required int value, required ValueChanged<int> onChanged})`: − / + buttons (`copies-dec` / `copies-inc`) clamped to 1–9, with the value shown between them (`copies-value`).
  - `Future<int?> showCopiesDialog(BuildContext context)`: a stepper starting at 1 and "Print" (`copies-dialog-print`). Returns null on cancel.
  - `Future<void> printWithFeedback(BuildContext context, {required LabelPrintService service, required GasAnalysis analysis, required int copies})`:
    - on success, a SnackBar `Label printed.` (or `Printed 2 labels.`), followed by each warning's `printerFaultMessage`, e.g. `Label printed. Printer battery is low.`;
    - on `LabelPrinterException`, a SnackBar with the exception message and a "Retry" action that runs `printWithFeedback` again with the same arguments. Retry never saves.

- [ ] **Step 1: Write the failing widget tests** covering every behaviour in the Interfaces block. Include:
  - the "Other…" validation error for 50 / 60;
  - the mismatch dialog body for desired 50/0 and analysed 32.1/0, and each button's return value;
  - the indicator's text and colour for one case per level;
  - `printWithFeedback`'s Retry: the first call fails, Retry succeeds, and the fake records exactly one successful print.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/ui/widgets/desired_mix_picker_test.dart test/ui/widgets/mix_match_indicator_test.dart test/ui/widgets/mix_mismatch_dialog_test.dart test/ui/widgets/label_print_controls_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement** the four files. `CopiesStepper`, `showCopiesDialog` and `printWithFeedback` go in `label_print_controls.dart`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test && flutter analyze`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/widgets/desired_mix_picker.dart lib/ui/widgets/mix_match_indicator.dart lib/ui/widgets/mix_mismatch_dialog.dart lib/ui/widgets/label_print_controls.dart test/ui/widgets
git commit -m "feat(labels): desired mix picker, match indicator and print controls (#114)"
```

---

### Task 12: Save card: desired mix, role, "Save & print"

**Files:**
- Modify: `lib/ui/widgets/analysis_save_card.dart`, `lib/ui/screens/analyzer_screen.dart`, `lib/ui/screens/blend_screen.dart`
- Test: `test/ui/widgets/analysis_save_card_print_test.dart` (create), and keep `test/ui/screens/analyzer_save_analysis_test.dart` passing

**Interfaces:**
- Consumes:
  - from Task 11: `DesiredMixPicker`, `MixMatchIndicator`, `showMixMismatchDialog`, `CopiesStepper`, `printWithFeedback`;
  - from Task 2: `recentDesiredMixes`, `gasRoleForCylinderRole`, `GasAnalysis.fromNew`, `gradeMix`;
  - from Task 8: `LabelPrinterSettingsScreen`;
  - from Task 9: `BlendNotifier.recentTarget()`.
- Produces:
  - `AnalysisSaveCard` gains `final DesiredMix? blendTarget`, `final LabelPrintService? labelPrinting` and `final VoidCallback? onSetUpPrinter`.
  - `AnalyzerScreen` gains `final DesiredMix? blendTarget` and `final LabelPrintService? labelPrinting`. It passes both to the card, along with `onSetUpPrinter`, which pushes `LabelPrinterSettingsScreen(settings: widget.settings, printing: labelPrinting)`. Task 13 passes `labelPrinting` on to the log.
  - `BlendScreen` gains `final LabelPrintService? labelPrinting` and passes `blendTarget: widget.notifier.recentTarget()` and `labelPrinting` to `AnalyzerScreen`.

- [ ] **Step 1: Write the failing widget tests** in `analysis_save_card_print_test.dart`.
  - Pump `AnalysisSaveCard` directly with a fixed `AnalyzerReading` (O2 20.6, He 33.8), `ReadingStability.stable`, `FakeGasAnalysesDao`, and a `LabelPrintService` on `FakeLabelPrinter` with the printer configured.
  - **Mix chips:**
    - with `blendTarget: DesiredMix(21, 35)` and the DAO holding analyses with desired 32/0 and 21/35, the chips read `Tx21/35`, `EAN32`, `Other…` in that order, with no duplicate;
    - none is selected at start.
  - **Role:**
    - selecting a cylinder with role `diluent` switches the role control (`analysis-gas-role`) to "Diluent";
    - selecting one with role `oxygen` switches it to "Bailout/deco";
    - the user can flip it, and the saved `NewGasAnalysis.gasRole` follows the control.
  - **Match indicator:**
    - absent until a mix is picked;
    - picking `Tx21/35` shows it in green with `Matches Tx21/35`;
    - rebuilding with a reading of 22.5 / 33.8 updates it to `O2 1.5 off Tx21/35`.
  - **Save & print** (`analysis-save-print`):
    - adds one analysis carrying `desiredMix` and `gasRole`, then prints one label with the stepper's copy count (set it to 2 with `copies-inc`);
    - **Review Focus 2:** two quick taps (the second while the fake's `printGate` holds the first print) give one `dao.added` and one print;
    - **Review Focus 1:** with `failOnConnect`, the analysis is still in `dao.added`, a SnackBar says "Printer not found", and tapping "Retry" prints without a second `add`;
    - **Hard mismatch:** with desired `EAN50` and a reading of 32.1/0, the mismatch dialog appears before anything is saved.
      - "Cancel" → nothing saved, nothing printed;
      - "Change desired mix" → nothing saved, the card still shows the picker;
      - "Print as EAN32" → saved, then printed.
    - **Not stable:** the existing unstable confirm still comes first. Cancelling it saves nothing.
  - **No printer configured:** no "Save & print"; a "Set up label printer" link (`analysis-setup-printer`) calls `onSetUpPrinter`.
  - **No `labelPrinting` at all:** neither the button nor the link.
  - The plain "Save analysis" button saves the desired mix and role too, and never prints.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/ui/widgets/analysis_save_card_print_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement**
  - **Card state:** `DesiredMix? _desired`, `GasRole _role` (reset from the cylinder's role whenever the cylinder changes), `int _copies = 1`, `bool _printing`, and the mix options from `recentDesiredMixes(await dao.list(), blendTarget: widget.blendTarget)`, loaded with the cylinders.
  - **Save & print order** (spec "Matching the analysis to the desired mix" and "Printing flow"):
    1. Snapshot the reading.
    2. The unstable confirm.
    3. If `_desired` is set and `gradeMix(...)` is hard, the mismatch dialog. Pass it `GasAnalysis.fromNew('pending', snapshot)`; nothing is saved yet. "Change desired mix" and "Cancel" both abort before saving.
    4. Save, sharing the existing `_save` code. Refactor it to return the saved `GasAnalysis` (built with `GasAnalysis.fromNew`) or null.
    5. `printWithFeedback(copies: _copies)`.
  - Guard the whole sequence with `_saving || _printing`, so the buttons are disabled until it finishes.
  - The match indicator sits under the picker, from `widget.reading`.
  - **Layout:** the picker row labelled "Mix (optional)", then the role `SegmentedButton<GasRole>`, then the existing fields, then a row with "Save analysis", and, when `labelPrinting?.isConfigured == true`, "Save & print" plus the `CopiesStepper`.
  - **Wiring:** `AnalyzerScreen` and `BlendScreen` per the Interfaces block.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test && flutter analyze`
Expected: all pass, including the existing `analyzer_save_analysis_test.dart`.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/widgets/analysis_save_card.dart lib/ui/screens/analyzer_screen.dart lib/ui/screens/blend_screen.dart test/ui/widgets/analysis_save_card_print_test.dart
git commit -m "feat(labels): desired mix, gas role and Save & print on the save card (#114)"
```

---

### Task 13: Analysis log: desired mix, reprint and edit

**Files:**
- Create: `lib/ui/widgets/analysis_edit_sheet.dart`
- Modify:
  - `lib/ui/screens/gas_analysis_log_screen.dart`;
  - both places that open the log: `lib/ui/screens/analyzer_screen.dart` (its app-bar log action) and the Equipment chain, `lib/ui/screens/equipment/equipment_landing_screen.dart`, `lib/ui/screens/equipment/cylinders_list_screen.dart`, `lib/ui/screens/equipment/cylinder_detail_screen.dart`.
- Test: `test/ui/screens/gas_analysis_log_screen_test.dart`, `test/ui/widgets/analysis_edit_sheet_test.dart` (create)

**Interfaces:**
- Consumes:
  - from Task 2: `GasAnalysesDaoLike.update`, `GasAnalysisEdit`, `recentDesiredMixes`;
  - from Task 11: `DesiredMixPicker`, `MixMatchIndicator`, `showMixMismatchDialog`, `showCopiesDialog`, `printWithFeedback`;
  - from Task 7: `LabelPrintService`.
- Produces:
  - `Future<bool> showAnalysisEditSheet(BuildContext context, {required GasAnalysesDaoLike dao, required GasAnalysis analysis, required List<DesiredMix> mixOptions})`. Returns true when saved. The sheet has key `analysis-edit-sheet` and its save button `analysis-edit-save`.
  - `GasAnalysisLogScreen` gains `final LabelPrintService? labelPrinting`.
  - `EquipmentLandingScreen`, `CylindersListScreen` and `CylinderDetailScreen` each gain an optional `final LabelPrintService? labelPrinting` and pass it down to the log.
  - `AnalyzerScreen` passes its `labelPrinting` (added in Task 12) to its `GasAnalysisLogScreen` push.

- [ ] **Step 1: Write the failing widget tests**
  - **Tile:**
    - an entry with desired 21/35 and analysed 22.5/33.8 shows the desired name and a `MixMatchIndicator` reading `O2 1.5 off Tx21/35`;
    - an entry without a desired mix shows neither;
    - a diluent entry shows a `DIL` marker (`analysis-dil-<id>`), and a bailout entry doesn't.
  - **Print action** (`analysis-print-<id>`):
    - shown only when `labelPrinting?.isConfigured == true`;
    - opens the copies dialog; "Print" with 2 prints 2 copies of that entry.
  - **Hard mismatch on reprint:** desired 50/0, analysed 32.1/0 → the mismatch dialog.
    - "Print as EAN32" prints;
    - "Cancel" doesn't;
    - "Change desired mix" opens the edit sheet, and after saving 32/0 the entry prints without a second dialog (the stored mix now matches).
  - **Edit** (tap the tile):
    - the sheet shows the analysed values read-only, plus the picker (options from `recentDesiredMixes(items)`), the role control, analysed by and notes;
    - saving calls `dao.update` with exactly those four fields, and the list refreshes;
    - the measured values have no input fields.
  - **Equipment chain:** `CylinderDetailScreen` with `labelPrinting` passes it to the log (pump the detail screen, open "Gas analyses", find `analysis-print-<id>`).

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/ui/screens/gas_analysis_log_screen_test.dart test/ui/widgets/analysis_edit_sheet_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement**
  - The tile layout is the builder's choice within the spec's "Analysis log screen" bullet. Keep swipe-to-delete working.
  - Reprint order: copies dialog → mismatch dialog (only when hard) → `printWithFeedback`.
  - "Change desired mix" → `showAnalysisEditSheet`. When it returns true, reload the entry from `dao.list()` and restart the reprint from the mismatch check, without asking for copies again.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test && flutter analyze`
Expected: all pass, including the existing log and equipment tests.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/widgets/analysis_edit_sheet.dart lib/ui/screens/gas_analysis_log_screen.dart lib/ui/screens/analyzer_screen.dart lib/ui/screens/equipment test/ui/screens/gas_analysis_log_screen_test.dart test/ui/widgets/analysis_edit_sheet_test.dart
git commit -m "feat(labels): reprint and edit from the analysis log (#114)"
```

---

### Task 14: Wire it into the app

**Files:**
- Modify: `lib/ui/app_shell.dart`

**Interfaces:**
- Consumes: `LabelPrintService` (Task 7), `renderCylinderLabel` (Task 5), `PhomemoBlePrinter`, `PhomemoBleScanner` (Task 6), `BlendNotifier.loadTarget` (Task 9), and the new `labelPrinting` parameters (Tasks 8, 12, 13).

- [ ] **Step 1: Implement**
  - In `initState`, next to `_gasAnalysesDao`, build `_labelPrintService` with:
    - `render: renderCylinderLabel`;
    - `printerFor: (id) => PhomemoBlePrinter(remoteId: id)`;
    - `scanner: PhomemoBleScanner()`;
    - `printerId: () => widget.settingsNotifier.labelPrinterId`;
    - `use14ForDeeperMixes: () => widget.settingsNotifier.labelUse14ForDeeperMixes`.
  - Call `_blendNotifier.loadTarget()` right after the notifier is created (same style as `_divePlanNotifier.load()`).
  - Pass `labelPrinting: _labelPrintService` to `BlendScreen`, `EquipmentLandingScreen` and `SettingsScreen`.

- [ ] **Step 2: Verify**

Run: `flutter analyze && flutter test`
Expected: clean; all pass.

Then run the app on macOS (`flutter run -d macos`) and check, without a printer:
- Settings shows "Label printer", and "Find printer" scans and finds nothing without crashing;
- the analyzer save card, on a USB source, shows the mix picker, the role control and "Set up label printer";
- with the Demo source, the save card is hidden.

- [ ] **Step 3: Commit**

```bash
git add lib/ui/app_shell.dart
git commit -m "feat(labels): wire label printing into the app (#114)"
```

---

### Task 15: Bench verification with the M110 (needs Egbert and the hardware)

This task needs the physical printer. If it isn't available, stop here and report the branch as ready for bench testing.

- [ ] **Step 1: Get reference bytes, if an Android phone is available.** Capture an HCI snoop log of Phomemo's own app printing one 50 × 30 label. Compare it with `encodePhomemoM110Job` output for the same size. Where they differ, update the constants and the Task 4 encoder tests to the captured bytes, and note "verified on M110 fw <version>" in the comments.
- [ ] **Step 2: Test print** from Settings on macOS, Android and iPhone. Check:
  - the label is placed on the label, not across the gap;
  - the black bar prints evenly at the default density, on battery and on USB power;
  - the content sits inside the margins. If it's shifted about 1 mm sideways, as SpoolmanScale found on the M110S, the roll sits against one wall. Try a row exactly as wide as the label, or right-align the image.
  - the scanner lists the printer under its advertised name, so `kPhomemoNamePrefixes` is right.
  Adjust the density, speed or media constants, then re-run the Task 4 tests.
- [ ] **Step 3: Notifications.** Log every notification during a print and during each fault: no labels, cover open, low battery if possible, and overheat if it can be provoked by printing many copies. Settle these open questions from Task 4:
  - Does the M110 send `1A 0F 0C` when a label is done? If it does, shorten `kPhomemoDoneTimeout`.
  - Does it send `01 xx` per chunk? If it does, consider pacing on the ack instead of the 20 ms timer.
  - Which `1A 03 xx` value means overheated? Map it to `PhomemoEvent`, adding `overheated`.
  - What do the battery bytes look like at low charge?

  Update `parsePhomemoNotification` and its tests, and check that each UI message shows.
- [ ] **Step 4: Reconnect by stored id.** Restart the app and print without scanning first, on each platform. If iOS or macOS can't connect via `BluetoothDevice.fromId` without a prior scan, add a 5 s scan filtered to that id inside `PhomemoBlePrinter.connect()`.
- [ ] **Step 5: End to end.** Analyse a real cylinder → "Save & print" → reprint from the log, for a bailout Tx and a diluent.
- [ ] **Step 6: Commit** the corrections:

```bash
git add lib/label_printer test/label_printer
git commit -m "fix(labels): Phomemo M110 bytes verified on the bench (#114)"
```

---

## Before this ships

- **Deploy migration 0020 to production before any build containing Task 2 is released.** Uploads send the whole row, so Supabase rejects analysis uploads from the new build until the columns exist. Egbert runs `supabase/apply_migrations.sh` through the Session pooler. It's idempotent.
- If the Sync Streams migration (#126) has landed by then, check that the `gas_analyses` stream selects every column.
- Open the PR with `Closes #114`.
