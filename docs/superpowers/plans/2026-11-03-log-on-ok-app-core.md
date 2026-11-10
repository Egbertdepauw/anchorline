# Log on OK — App Core (plan 1 of 3) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the hardware-free half of "Log on OK":
- the new `gas_analyses` fields;
- sign-off, edit and delete in the analysis log;
- the pure-Dart bridge protocol;
- the decision that turns a bridge record into an analysis, tested against the real SOLO captures.

Plan 2 then only has to move bytes.

**Architecture:**
- Two pure-Dart files under `lib/analyzer/bridge/`, with no Flutter or I/O, the same rule as the parsers:
  - `bridge_protocol.dart` parses and formats the text protocol of spec §3, and assembles records;
  - `record_to_analysis.dart` makes every decision of spec §5.
- The data layer gains four columns (migration 0021) and two DAO methods.
- The log screen and the edit sheet gain the sign-off flow. Flagged entries can't print, in the UI or in `LabelPrintService`.

**Tech Stack:** Flutter 3.44.0 / Dart; PowerSync (local SQLite) + Supabase Postgres; the existing `crypto` package for SHA-1 (UUID v5); `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-11-03-background-gas-logging-design.md` (merged design). Read §3 (protocol), §5 (records to analyses), §8 (data model), §9 (the log) and §10 (failure cases) before starting.

**Not in this plan:**
- **Plan 2:** bridge firmware, `bridge_link.dart`, `BleBridgeTransport` and pairing (spec build steps 1–2). It needs the ESP32 board.
- **Plan 3:** `LogOnOkService`, the setup card, sessions, iOS/Android background and store notes (spec build steps 3, setup part, and 4–5).

Both are written once their inputs exist: the bench results, and this plan's interfaces.

**Branch:** file one GitHub issue, "Log on OK: app core (data, sign-off, bridge protocol, record decision)", label P2, milestone "Gas analyzer (Divesoft SOLO)". Branch `feat/<issue>-log-on-ok-core` from `spec/113-solo-bridge-background-logging`, so the spec, this plan and the capture fixtures travel with the code. One PR, squash-merged, with "Refs #113".

## Global Constraints

- Everything in git is in English: code, comments, commits, PR text.
- No new pub dependencies. SHA-1 comes from the existing `crypto` package.
- `lib/analyzer/**` stays pure Dart: no `package:flutter` imports, no I/O.
- Don't run `dart format` on whole existing files. Match the surrounding style by hand. New files may be formatted.
- **Measured values never change after a save:** `o2_percent`, `he_percent`, `temp_c`, `baro_hpa`, `analysed_at`, `stable`, and also `capture_source` and `bridge_record_id`.
- **A flagged entry (`needs_signoff = 1`) never prints:** no print action in the UI, and `LabelPrintService.printAnalysis` refuses it.
- **Room air** is O2 from `kAirO2MinPercent` (20.5) to `kAirO2MaxPercent` (21.5) inclusive, with He below `kHeliumNoiseFloorPercent` (1.0). A negative He counts as 0. All three constants live in `lib/analysis/gas_naming.dart`.
- **Wire text is ASCII only,** because the bridge's LCD font is ASCII. Feedback text is at most 24 characters. Use `AIR - NOT LOGGED`, not an em dash.
- The bridge protocol version is `1`.
- **Migration 0021 is deployed to prod before any build that writes the new columns ships.** The upload connector sends whole rows.
- Before every commit: `flutter analyze` is clean, and the touched test files pass. Before the PR: the whole `flutter test` passes.

## Review Focus

The five inputs most likely to bite that the spec implies but no test would otherwise exercise. Each has a test in the task named.

1. **A row from an older build or another device**, with no `needs_signoff`, `capture_source`, `bridge_record_id` or `analysed_for`, reads as a screen save that isn't flagged. → Task 1, `a row without the new columns reads as an unflagged screen save`.
2. **A record re-sent after a reconnect in the middle of a record:** a second `REC` arrives before `END`. The partial record is dropped and the new one starts clean, so no lines from two records get mixed. → Task 2, `a second REC before END drops the partial record`.
3. **SOLO lines carry runs of spaces, `%`, `~C` and asterisks.** They must survive `L`, `W` and `H` byte for byte, or the parser and stability see different numbers than the SOLO showed. → Task 2, `L, W and H keep the SOLO line byte for byte`.
4. **An entry that becomes flagged through sync while its print prompt is open.** Another device or the bridge flags it after the diver tapped print. The re-read before printing must catch it and print nothing. → Task 5, `an entry flagged while its print prompt is open prints nothing`.
5. **An entry whose cylinder is soft-deleted or unknown on this device.** Opening the edit sheet must keep that cylinder, not silently set "No cylinder" when the diver saves something else. → Task 6, `an unknown cylinder survives an unrelated edit`.

---

### Task 1: New `gas_analyses` fields, migration 0021, DAO

**Files:**
- Create: `supabase/migrations/0021_gas_analysis_bridge_fields.sql`
- Modify:
  - `lib/sync/cloud/powersync_schema.dart` (the `gas_analyses` table, around line 116)
  - `lib/data/models/gas_analysis.dart`
  - `lib/data/db/gas_analyses_dao.dart`
  - `lib/data/models/gas_analysis_csv.dart`
  - `test/_helpers/fake_gas_analyses_dao.dart`
  - `lib/ui/widgets/analysis_edit_sheet.dart`: only pass the new required `GasAnalysisEdit` arguments (the entry's current values); Task 6 does the UI.
- Test:
  - `test/data/db/gas_analyses_dao_test.dart`
  - `test/data/models/gas_analysis_test.dart`
  - `test/data/models/gas_analysis_csv_test.dart`
  - every other test that builds a `GasAnalysisEdit`: `test/ui/screens/gas_analysis_log_screen_test.dart` and `test/ui/widgets/analysis_save_card_print_test.dart`

**Interfaces:**
- Produces (`lib/data/models/gas_analysis.dart`):
  ```dart
  enum CaptureSource {
    screen, bridgeOk;
    String? get dbValue;                 // screen → null, bridgeOk → 'bridge_ok'
    static CaptureSource fromDb(String? v); // 'bridge_ok' → bridgeOk, anything else → screen
  }
  // NewGasAnalysis and GasAnalysis gain (named, with defaults):
  //   bool needsSignoff = false, CaptureSource captureSource = CaptureSource.screen,
  //   String? bridgeRecordId, String? analysedFor
  // GasAnalysis.fromNew copies them; GasAnalysis.applyEdit writes the edit's fields
  // and sets needsSignoff = false when edit.signOff (else keeps it).
  class GasAnalysisEdit {
    const GasAnalysisEdit({
      required DesiredMix? desiredMix, required GasRole gasRole,
      required String? analysedBy, required String? notes,
      required String? cylinderId, required double? fillPressureBar,
      required String? analysedFor, bool signOff = false,
    });
  }
  ```
- Produces (`GasAnalysesDaoLike`, implemented by `GasAnalysesDao` and `FakeGasAnalysesDao`):
  ```dart
  /// Inserts [a] under [id] unless a row with that id exists, soft-deleted
  /// rows included. True when it inserted.
  Future<bool> addFromBridge(String id, NewGasAnalysis a);
  /// Sets needs_signoff, bumps version and updated_at.
  Future<void> setNeedsSignoff(String id, bool needsSignoff);
  // update(id, edit) now also writes cylinder_id, fill_pressure_bar and
  // analysed_for, and needs_signoff = 0 when edit.signOff. It never writes
  // the measured columns, capture_source or bridge_record_id.
  ```

- [ ] **Step 1: Write the failing tests**

  In `gas_analyses_dao_test.dart`, using the file's existing `insertRawAnalysis` and `analysis()` helpers, a `FakeSessionSource()..setUserId('u1')` and `openPowerSyncForTest()`:

  ```dart
  test('add round-trips the bridge fields', () async {
    // add(NewGasAnalysis(... needsSignoff: true, captureSource: CaptureSource.bridgeOk,
    //   bridgeRecordId: 'a1b2c3d4e5f6/1a2b3c4d-7', analysedFor: 'Alex'))
    final a = (await dao.list()).single;
    expect(a.needsSignoff, isTrue);
    expect(a.captureSource, CaptureSource.bridgeOk);
    expect(a.bridgeRecordId, 'a1b2c3d4e5f6/1a2b3c4d-7');
    expect(a.analysedFor, 'Alex');
  });
  test('a row without the new columns reads as an unflagged screen save', () async {
    await insertRawAnalysis(ps, 'old-1');
    final a = (await dao.list()).single;
    expect(a.needsSignoff, isFalse);
    expect(a.captureSource, CaptureSource.screen);
    expect(a.bridgeRecordId, isNull);
    expect(a.analysedFor, isNull);
  });
  test('addFromBridge inserts once per id', () async {
    expect(await dao.addFromBridge('id-1', analysis()), isTrue);
    expect(await dao.addFromBridge('id-1', analysis(o2: 30)), isFalse);
    expect((await dao.list()).single.o2Percent, 21.4);
  });
  test('addFromBridge never brings back a soft-deleted row', () async {
    await dao.addFromBridge('id-1', analysis());
    await dao.softDelete('id-1');
    expect(await dao.addFromBridge('id-1', analysis()), isFalse);
    expect(await dao.list(), isEmpty);
  });
  test('setNeedsSignoff bumps version and updated_at', () async { /* version 1 → 2, updated_at > 0 */ });
  test('update writes cylinder, fill pressure and analysed for, never measured values', () async {
    // edit with cylinderId 'c1', fillPressureBar 210.0, analysedFor 'Alex';
    // o2Percent, hePercent, analysedAt, stable, captureSource, bridgeRecordId unchanged
  });
  test('update with signOff clears needs_signoff; without it the flag stays', () async {});
  ```

  In `gas_analysis_csv_test.dart`, the header ends with `'analysed_for', 'needs_signoff'`, and an entry with `analysedFor: 'Alex', needsSignoff: true` has row values `'Alex'` and `'true'`.

  In `gas_analysis_test.dart`: `applyEdit` with `signOff: true` gives `needsSignoff == false`; with `signOff: false` the flag is kept.

- [ ] **Step 2: Run them and see them fail**

  Run: `flutter test test/data/db/gas_analyses_dao_test.dart test/data/models/`
  Expected: compile errors (`CaptureSource`, `addFromBridge` and the new named parameters are undefined).

- [ ] **Step 3: Write the migration**

  `supabase/migrations/0021_gas_analysis_bridge_fields.sql`: a header comment in the style of `0020_gas_analysis_label_fields.sql` (what each column is, why there are no grants or publication change, deploy before the build), then:

  ```sql
  ALTER TABLE gas_analyses ADD COLUMN IF NOT EXISTS needs_signoff integer NOT NULL DEFAULT 0;
  ALTER TABLE gas_analyses ADD COLUMN IF NOT EXISTS capture_source text;
  ALTER TABLE gas_analyses ADD COLUMN IF NOT EXISTS bridge_record_id text;
  ALTER TABLE gas_analyses ADD COLUMN IF NOT EXISTS analysed_for text;

  NOTIFY pgrst, 'reload schema';
  ```

  If `0021` is taken on `main` by the time this is built, use the next free number.

- [ ] **Step 4: Implement the schema, model, DAO, CSV and fake**

  - `powersync_schema.dart`: add `Column.integer('needs_signoff')`, `Column.text('capture_source')`, `Column.text('bridge_record_id')` and `Column.text('analysed_for')` to `gas_analyses`.
  - DAO `add`: write all four. `needs_signoff` is written as 0 or 1, never left null.
  - `_rowToAnalysis`: `needs_signoff` null reads as 0.
  - `addFromBridge`: a `writeTransaction` that checks `SELECT 1 FROM gas_analyses WHERE id = ?`, with **no** `deleted_at` filter, then inserts like `add`, but with the given id.
  - `setNeedsSignoff`: same transaction shape as `softDelete`.
  - `analysedFor` goes through `_blankToNull`, like `analysedBy`.
  - CSV: two columns appended, after `gas_role`.
  - Fake:
    - `addFromBridge` checks its `analyses` list, deleted ids included, and records the call in `addedFromBridge`;
    - `setNeedsSignoff` replaces the entry and records the call in `signoffChanges`;
    - `update` keeps using `applyEdit`, and re-resolves `cylinderLabel` from its `cylinders` when the cylinder changed.

- [ ] **Step 5: Run the tests and the migration lint**

  Run:
  - `flutter test test/data/ test/ui/screens/gas_analysis_log_screen_test.dart test/ui/widgets/`
  - `./supabase/lint_migrations.sh`

  Expected: all pass, and the lint exits 0.

- [ ] **Step 6: Commit**

  ```bash
  git add supabase/migrations/0021_gas_analysis_bridge_fields.sql lib/sync/cloud/powersync_schema.dart lib/data test/data test/_helpers/fake_gas_analyses_dao.dart lib/ui/widgets/analysis_edit_sheet.dart test/ui
  git commit -m "feat(analyzer): bridge fields and sign-off flag on gas_analyses (0021)"
  ```

  Say in the PR that Egbert deploys 0021 to prod (via `supabase/apply_migrations.sh` over the Session pooler, or the SQL Editor) before the next release build.

---

### Task 2: Bridge protocol (pure Dart)

**Files:**
- Create: `lib/analyzer/bridge/bridge_protocol.dart`
- Test: `test/analyzer/bridge/bridge_protocol_test.dart`

**Interfaces:**
- Produces:
  ```dart
  const int kBridgeProtocolVersion = 1;
  const int kFeedbackTextMax = 24;

  sealed class BridgeMessage {}
  class BridgeHello extends BridgeMessage { // HELLO proto= fw= bridge= epoch= boot= up= solo= rec= vbus= batt= pending=
    final int proto; final String fw; final String bridgeId; final String epoch;
    final int boot; final int upMs; final bool soloAttached; final bool recording;
    final bool vbusOn; final int batteryMv; final int pending; }
  class BridgeStatus extends BridgeMessage { // ST solo= data= pending= batt= up=
    final bool soloAttached; final bool dataFlowing; final int pending;
    final int batteryMv; final int upMs; }
  class BridgeLiveLine extends BridgeMessage { final String line; }          // L <raw>
  class BridgeRecordStart extends BridgeMessage {                            // REC <rid> boot= up= wall= live=
    final String rid; final int boot; final int upMs; final int wallMs; final bool live; }
  class BridgeWindowLine extends BridgeMessage { final int offsetMs; final String line; } // W <offset> <raw>
  class BridgeHeldLine extends BridgeMessage { final String line; }          // H <raw>
  class BridgeRecordEnd extends BridgeMessage { final String rid; }          // END <rid>
  class BridgeUnknown extends BridgeMessage { final String raw; }            // anything else

  /// Never throws: unknown types, missing keys and bad numbers give BridgeUnknown.
  BridgeMessage parseBridgeMessage(String line);

  enum BridgeLiveState { settling, stable, sensorError, air } // wire: settling|stable|sensor_error|air
  enum FeedbackCode { printed, saved, check, skipped, error }  // wire: the lowercase name

  // App → bridge. Each returns one line WITHOUT the trailing '\n' (the link adds it).
  String formatTime(DateTime now);                       // 'TIME <millisecondsSinceEpoch>'
  String formatLive(bool on);                            // 'LIVE ON' | 'LIVE OFF'
  String formatState(BridgeLiveState s, {String? mix});  // 'STATE stable Tx21/35'
  String formatAck(String rid);                          // 'ACK <rid>'
  String formatFeedback(String rid, FeedbackCode c, String text); // 'FB <rid> <code> <text>'
  String formatConfig({required bool recording, required bool vbusOn}); // 'CFG rec=on vbus=off'

  class BridgeRecord {
    final String rid; final int boot; final int upMs; final int wallMs; final bool live;
    final List<BridgeWindowLine> window; // oldest first, offsets ≤ 0
    final String heldLine; }

  /// Feeds parsed messages; returns a complete record on its END, else null.
  class BridgeRecordAssembler { BridgeRecord? add(BridgeMessage m); }
  ```
- Parsing rules:
  - The first space-separated token is the type.
  - Key/value tokens split on the first `=`; unknown keys are ignored.
  - Booleans are `0`/`1`, except `rec=` and `vbus=`, which are `on`/`off`.
  - For `L` and `H`, the payload is everything after the first space, verbatim.
  - For `W`, the payload is everything after the second space, verbatim.
  - `formatFeedback` replaces line breaks with spaces and cuts the text to `kFeedbackTextMax` characters.
  - The assembler drops a partial record when a new `REC` arrives, or when an `END` has another rid.

- [ ] **Step 1: Write the failing tests**

  ```dart
  test('parses HELLO', () {
    final m = parseBridgeMessage('HELLO proto=1 fw=0.1.0 bridge=a1b2c3d4e5f6 epoch=1a2b3c4d '
        'boot=3 up=120000 solo=1 rec=on vbus=off batt=3912 pending=2') as BridgeHello;
    expect((m.proto, m.bridgeId, m.boot, m.upMs, m.soloAttached, m.recording, m.vbusOn,
        m.batteryMv, m.pending), (1, 'a1b2c3d4e5f6', 3, 120000, true, true, false, 3912, 2));
  });
  test('parses ST', () { /* 'ST solo=1 data=0 pending=0 batt=3800 up=5000' */ });
  test('L, W and H keep the SOLO line byte for byte', () {
    const solo = 'He   0.5 %  O2  19.8 %  Ti  22.0 ~C  1029.5 hPa   2026/11/03 15:21:00';
    expect((parseBridgeMessage('L $solo') as BridgeLiveLine).line, solo);
    final w = parseBridgeMessage('W -2000 $solo') as BridgeWindowLine;
    expect((w.offsetMs, w.line), (-2000, solo));
    expect((parseBridgeMessage('H He ***.* %  O2  19.8 %') as BridgeHeldLine).line,
        'He ***.* %  O2  19.8 %');
  });
  test('parses REC and END', () { /* 'REC 1a2b3c4d-7 boot=3 up=99000 wall=0 live=1' */ });
  test('unknown or malformed input gives BridgeUnknown and never throws', () {
    for (final s in ['', 'XYZ 1', 'ST solo=maybe data=1 pending=0 batt=1 up=1', 'W notanumber x']) {
      expect(parseBridgeMessage(s), isA<BridgeUnknown>());
    }
  });
  test('formats app messages', () {
    expect(formatTime(DateTime.fromMillisecondsSinceEpoch(1762182000000)), 'TIME 1762182000000');
    expect(formatLive(true), 'LIVE ON');
    expect(formatState(BridgeLiveState.sensorError), 'STATE sensor_error');
    expect(formatState(BridgeLiveState.stable, mix: 'Tx21/35'), 'STATE stable Tx21/35');
    expect(formatAck('1a2b3c4d-7'), 'ACK 1a2b3c4d-7');
    expect(formatFeedback('r1', FeedbackCode.skipped, 'AIR - NOT LOGGED'), 'FB r1 skipped AIR - NOT LOGGED');
    expect(formatConfig(recording: true, vbusOn: false), 'CFG rec=on vbus=off');
  });
  test('feedback text loses line breaks and is cut to 24 characters', () {
    expect(formatFeedback('r', FeedbackCode.check, 'A\nB'), 'FB r check A B');
    expect(formatFeedback('r', FeedbackCode.check, 'X' * 30), 'FB r check ${'X' * 24}');
  });
  group('BridgeRecordAssembler', () {
    test('assembles REC, W lines, H and END into one record', () {});
    test('a second REC before END drops the partial record', () {
      // REC r1, W, W, REC r2, W, H, END r2 → one record r2 with only r2's single W line
    });
    test('END with another rid drops the record', () {});
    test('messages outside a record give null', () {});
  });
  ```

- [ ] **Step 2: Run them and see them fail**

  Run: `flutter test test/analyzer/bridge/bridge_protocol_test.dart`
  Expected: FAIL; the library doesn't exist.

- [ ] **Step 3: Implement `lib/analyzer/bridge/bridge_protocol.dart`** to the interface above.

  The library doc comment points at spec §3 and states the version rule: anything incompatible bumps `kBridgeProtocolVersion`.

- [ ] **Step 4: Run the tests and see them pass**

  Run: `flutter test test/analyzer/bridge/bridge_protocol_test.dart`
  Expected: PASS.

- [ ] **Step 5: Commit**

  ```bash
  git add lib/analyzer/bridge/bridge_protocol.dart test/analyzer/bridge/bridge_protocol_test.dart
  git commit -m "feat(analyzer): bridge protocol v1 parser, formatter and record assembler"
  ```

---

### Task 3: Record to analysis (pure Dart), tested on the real captures

**Files:**
- Create:
  - `lib/analyzer/bridge/record_to_analysis.dart`
  - `test/_helpers/solo_capture_log.dart`
- Test: `test/analyzer/bridge/record_to_analysis_test.dart`

**Interfaces:**
- Consumes:
  - from Task 1: `NewGasAnalysis` (`needsSignoff`, `captureSource`, `bridgeRecordId`, `analysedFor`), `CaptureSource.bridgeOk`;
  - from Task 2: `BridgeRecord`, `BridgeWindowLine`, `FeedbackCode`;
  - existing: `parseSoloLine` (`lib/analyzer/protocol/solo_line_parser.dart`), `StabilityDetector` / `ReadingStability` (`lib/analyzer/stability.dart`), `gradeMix` / `MixMatchLevel` (`lib/analysis/mix_match.dart`), `gasMixName` and the air and helium constants (`lib/analysis/gas_naming.dart`), `DesiredMix` / `GasRole` (`lib/data/models/gas_analysis.dart`).
- Produces:
  ```dart
  const Duration kLiveRecordMaxAge = Duration(seconds: 30);
  bool isRoomAir(double o2Percent, double hePercent);

  /// What the diver set up before pressing OK (the setup card, plan 3).
  class LogOnOkSetup {
    const LogOnOkSetup({this.analysedBy, this.desiredMix, this.gasRole = GasRole.bailout,
      this.analysedFor, this.printOnOk = false, this.printerConfigured = false,
      this.cylinderId, this.fillPressureBar, this.notes, this.modPpo2s = const []});
    // fields as named; all final
  }
  /// The bridge's boot counter and uptime from its latest HELLO or ST.
  class BridgeClock { const BridgeClock({required this.boot, required this.upMs}); final int boot; final int upMs; }

  sealed class RecordOutcome { String get rid; FeedbackCode get feedback; String get feedbackText; }
  /// Nothing to save (no reading, or room air). Still ACK, then FB.
  class SkipRecord extends RecordOutcome { ... }
  class SaveRecord extends RecordOutcome {
    final String rowId;            // bridgeRowId(bridgeId, rid)
    final NewGasAnalysis analysis; // needsSignoff already decided (true while a print is pending)
    final bool printLabel;         // try printing after the save; clear the flag on success
    final bool live;               // per-cylinder values may be used up (plan 3)
  }

  RecordOutcome recordToAnalysis({
    required BridgeRecord record, required String bridgeId, required LogOnOkSetup setup,
    required BridgeClock clock, required DateTime now,
    required bool active, // the analyzer screen is visible or a session runs
  });

  /// UUID v5 (SHA-1), RFC 4122 URL namespace 6ba7b811-9dad-11d1-80b4-00c04fd430c8,
  /// name 'anchorline-bridge:<bridgeId>/<rid>'. Lowercase, hyphenated.
  String bridgeRowId(String bridgeId, String rid);
  ```
- Test helper (`test/_helpers/solo_capture_log.dart`), reading the `tool/solo_capture.py` logs under `test/fixtures/analyzer/solo_ok_presses_2026-11-03_{a,b}.txt`:
  ```dart
  class CapturedLine { final Duration elapsed; final String line; }   // '<sec> <wall> RX <line>'
  class CaptureGap { final Duration endsAt; final Duration length; }  // '<sec> <wall> GAP <sec>'
  class SoloCaptureLog { final List<CapturedLine> lines; final List<CaptureGap> gaps; }
  /// Unescapes \xNN in RX payloads and strips the trailing CR LF; skips ERROR lines.
  SoloCaptureLog readSoloCaptureLog(String path);
  /// The record a bridge would build for [gap]: held = the last line before the gap;
  /// window = lines in the 30 s up to it, offsets in ms relative to the held line;
  /// upMs = the held line's elapsed ms.
  BridgeRecord recordBeforeGap(SoloCaptureLog log, CaptureGap gap,
      {String rid = 'cap-1', int boot = 1, bool live = true, int wallMs = 0});
  ```

**The decision.** Spec §5, in this order. Every branch has a test below.

1. Parse `heldLine`. If O2 is null, NaN or ≤ 0, or He is NaN → `SkipRecord(error, 'NO READING')`.
2. `he = max(he, 0)`. If `isRoomAir(o2, he)` → `SkipRecord(skipped, 'AIR - NOT LOGGED')`.
3. `stable`: a fresh `StabilityDetector`. Feed every window line, then the held line at offset 0, with `elapsed = offset − firstOffset`. `stable` is whether the state after the held line is `ReadingStability.stable`.
4. `analysedAt`:
   - same boot → `now − (clock.upMs − record.upMs)`;
   - otherwise `wallMs` if it isn't 0;
   - otherwise the SOLO's `deviceTime`;
   - otherwise `now`, with the note `Time of OK unknown; delivered <yyyy-MM-dd HH:mm>`.
5. `live = record.live && record.boot == clock.boot && clock.upMs − record.upMs ≤ 30000 && active`.
6. Setup fields (analysed by, desired mix, role, for, cylinder, fill pressure, notes) are used **only if live**. A late record gets `GasRole.bailout` and nulls. `modPpo2s` always comes from `setup`.
7. `level = desiredMix == null ? null : gradeMix(...).level`.
8. `printLabel = live && printOnOk && printerConfigured && analysedBy is not blank && desiredMix != null && stable && level ∈ {match, orange}`.
9. `needsSignoff = printLabel || !live || analysedBy is blank || desiredMix == null || !stable || level ∈ {red, hard}`.
10. Feedback, first match wins. `mix` is `gasMixName(o2, he)`:

    | Condition | Feedback |
    |---|---|
    | `printLabel` | `(printed, mix)` |
    | `!stable` | `(check, 'NOT STABLE')` |
    | `level` is red or hard | `(check, 'MISMATCH')` |
    | `!live` | `(saved, 'SIGN OFF LATER')` |
    | no desired mix | `(saved, 'NO MIX SET')` |
    | no name | `(saved, 'NO NAME SET')` |
    | otherwise | `(saved, mix)` |

11. The analysis:
    - `captureSource: bridgeOk`, `bridgeRecordId: '<bridgeId>/<rid>'`;
    - `temp_c` and `baro_hpa` only if finite;
    - `notes`: the setup's notes (live only) and the time note, joined by `\n`.

- [ ] **Step 1: Write the capture-log helper and the failing tests**

  Test-file helpers:
  - `soloLine(o2, he, {time = '2026/11/03 15:21:00'})` builds `'He  %5.1f %  O2  %5.1f %  Ti  22.0 ~C  1029.5 hPa   $time'`;
  - `steady(o2, he)` builds 150 window lines at 200 ms spacing, offsets −30000…−200, with the held line equal to the last one;
  - `drifting(from, to)` is the same, with O2 rising linearly from `from` to `to`.

  The shared fixture:
  - `bridgeId = 'a1b2c3d4e5f6'`, `clock = BridgeClock(boot: 3, upMs: 100000)`;
  - records have `boot: 3, upMs: 99000, live: true`;
  - `now = DateTime(2026, 11, 3, 16)`, `active: true`;
  - `full = LogOnOkSetup(analysedBy: 'EdP', desiredMix: DesiredMix(21, 35), gasRole: GasRole.diluent, analysedFor: 'Alex', printOnOk: true, printerConfigured: true, cylinderId: 'cyl-1', fillPressureBar: 210, notes: 'top-up', modPpo2s: [1.1, 1.4, 1.6])`.

  ```dart
  test('complete live Tx21/35 with printing on: save flagged until printed, print', () {
    final r = recordToAnalysis(record: steady(21.0, 35.0), ...full...) as SaveRecord;
    expect(r.printLabel, isTrue);
    expect(r.analysis.needsSignoff, isTrue);
    expect((r.feedback, r.feedbackText), (FeedbackCode.printed, 'Tx21/35'));
    expect(r.analysis.analysedBy, 'EdP');
    expect(r.analysis.cylinderId, 'cyl-1');
    expect(r.analysis.gasRole, GasRole.diluent);
    expect(r.analysis.captureSource, CaptureSource.bridgeOk);
    expect(r.analysis.bridgeRecordId, 'a1b2c3d4e5f6/<rid>');
    expect(r.rowId, bridgeRowId('a1b2c3d4e5f6', '<rid>'));
  });
  test('printing off: complete without a label', () { /* printLabel false, needsSignoff false, (saved, 'Tx21/35') */ });
  test('orange still prints', () { /* desired 32/0, measured 30.5/0 → printLabel true */ });
  test('red does not print and asks to check', () { /* measured 28.5/0 vs 32/0 → (check,'MISMATCH'), needsSignoff */ });
  test('hard does not print and asks to check', () { /* 26.0/0 vs 32/0 */ });
  test('not stable: saved flagged, no label', () { /* drifting(30, 32) → stable false, (check,'NOT STABLE') */ });
  test('no desired mix: saved flagged', () { /* (saved,'NO MIX SET') */ });
  test('no name: saved flagged', () { /* analysedBy '  ' → (saved,'NO NAME SET') */ });
  test('room air is skipped', () { /* steady(20.9, 0.3) → SkipRecord (skipped,'AIR - NOT LOGGED') */ });
  test('room air band edges', () {
    expect(isRoomAir(20.5, 0.9), isTrue);
    expect(isRoomAir(21.5, 0.0), isTrue);
    expect(isRoomAir(20.9, -0.2), isTrue);
    expect(isRoomAir(21.6, 0.0), isFalse);
    expect(isRoomAir(20.4, 0.0), isFalse);
    expect(isRoomAir(20.9, 1.0), isFalse);
  });
  test('sensor error at the hold is skipped', () { /* held 'He ***.* %  O2  32.0 % ...' → (error,'NO READING') */ });
  test('negative He is stored as 0', () { /* steady(32.0, -0.2) → hePercent 0.0 */ });
  test('a late record gets no setup', () {
    // live: false → analysedBy, desiredMix, analysedFor, cylinderId, fillPressureBar null;
    // gasRole bailout; needsSignoff true; printLabel false; (saved,'SIGN OFF LATER');
    // modPpo2s still [1.1, 1.4, 1.6]
  });
  test('late when older than 30 s', () { /* record upMs 69000 → late */ });
  test('late when not on the analyzer screen and not in a session', () { /* active: false */ });
  test('late after a bridge reboot', () { /* record boot 2 → late */ });
  group('analysed_at', () {
    test('same boot: now minus the uptime difference', () {
      // record upMs 95000, clock upMs 100000 → DateTime(2026, 11, 3, 15, 59, 55)
    });
    test('other boot: the wall time', () { /* wallMs = DateTime(2026,11,3,15,30).ms → that time */ });
    test('other boot, no wall time: the SOLO clock', () { /* → DateTime(2026, 11, 3, 15, 21) */ });
    test('nothing known: now, with a note', () {
      // held line without a timestamp → analysedAt == now, notes contains 'Time of OK unknown'
    });
  });
  test('bridgeRowId is a stable UUID v5', () {
    final a = bridgeRowId('a1b2c3d4e5f6', '1a2b3c4d-7');
    expect(a, bridgeRowId('a1b2c3d4e5f6', '1a2b3c4d-7'));
    expect(a, isNot(bridgeRowId('a1b2c3d4e5f6', '1a2b3c4d-8')));
    expect(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$').hasMatch(a), isTrue);
  });
  test('the real capture: the first OK on the bench SOLO', () {
    final log = readSoloCaptureLog('test/fixtures/analyzer/solo_ok_presses_2026-11-03_a.txt');
    final gap = log.gaps.firstWhere((g) => g.length > const Duration(seconds: 20)); // the 28.7 s hold
    final r = recordToAnalysis(record: recordBeforeGap(log, gap), ...) as SaveRecord;
    expect(r.analysis.o2Percent, 19.8);
    expect(r.analysis.hePercent, 0.5);
    expect(r.analysis.stable, isTrue);   // if this fails, check the helper's offsets before anything else
    expect(gasMixName(r.analysis.o2Percent, r.analysis.hePercent), 'Hypoxic 20'); // uncalibrated air, spec §5 caveat
  });
  ```

  The pinned value, computed independently with Python's `uuid.uuid5(uuid.NAMESPACE_URL, 'anchorline-bridge:a1b2c3d4e5f6/1a2b3c4d-7')`, goes into that test: `expect(a, '141b9635-6dd7-5df7-b454-b11799913348');`

- [ ] **Step 2: Run them and see them fail**

  Run: `flutter test test/analyzer/bridge/record_to_analysis_test.dart`
  Expected: FAIL; `record_to_analysis.dart` doesn't exist.

- [ ] **Step 3: Implement `lib/analyzer/bridge/record_to_analysis.dart`** as decided above.

  UUID v5: `sha1.convert(namespaceBytes + utf8.encode(name))`. Take the first 16 bytes; byte 6 = `(b & 0x0f) | 0x50`, byte 8 = `(b & 0x3f) | 0x80`. Format it like `GasAnalysesDao._newId`. The note's date uses `intl`'s `DateFormat('yyyy-MM-dd HH:mm')` (`intl` is pure Dart).

- [ ] **Step 4: Run the tests and see them pass**

  Run: `flutter test test/analyzer/`
  Expected: PASS, the existing analyzer tests included.

- [ ] **Step 5: Commit**

  ```bash
  git add lib/analyzer/bridge/record_to_analysis.dart test/_helpers/solo_capture_log.dart test/analyzer/bridge/record_to_analysis_test.dart
  git commit -m "feat(analyzer): turn a bridge OK record into an analysis (pocket rules, room air, late records)"
  ```

---

### Task 4: No label for a flagged entry: `LabelPrintService` guard

**Files:**
- Modify: `lib/labels/label_print_service.dart` (`printAnalysis`, line ~91)
- Test: `test/labels/label_print_service_test.dart`

**Interfaces:**
- Produces: `printAnalysis(a)` throws `LabelPrinterException('Sign off this analysis before printing it.')` when `a.needsSignoff`, before it queues or connects. The message is a public constant, `kSignOffBeforePrintMessage`.

- [ ] **Step 1: Write the failing test**

  `test('a flagged analysis is refused before any connect', ...)`: with the file's fake printer and an analysis with `needsSignoff: true`, `printAnalysis` throws a `LabelPrinterException` whose `message` is `kSignOffBeforePrintMessage`, and the fake records no connect.

- [ ] **Step 2: Run it and see it fail**

  Run: `flutter test test/labels/label_print_service_test.dart`
  Expected: FAIL; it prints.

- [ ] **Step 3: Add the guard.** Return a failed future, so callers' existing `catch (LabelPrinterException)` paths handle it.

- [ ] **Step 4: Run the tests and see them pass**

  Run: `flutter test test/labels/`
  Expected: PASS.

- [ ] **Step 5: Commit**

  ```bash
  git add lib/labels/label_print_service.dart test/labels/label_print_service_test.dart
  git commit -m "feat(labels): refuse to print an analysis that needs sign-off"
  ```

---

### Task 5: Analysis log: flagged badge, count, filter, no print action

**Files:**
- Modify: `lib/ui/screens/gas_analysis_log_screen.dart`
- Test: `test/ui/screens/gas_analysis_log_screen_test.dart`

**Interfaces:**
- Consumes:
  - `GasAnalysis.needsSignoff` (Task 1);
  - `kSignOffBeforePrintMessage` (Task 4).
- Produces:
  - widget keys `analysis-needs-signoff-<id>`, `analysis-log-signoff-count` and `analysis-log-signoff-filter`;
  - the tile's existing `analysis-print-<id>` is absent for flagged entries.

Behaviour:
- **Flagged tile:** a "Needs sign-off" chip in `SafetyColors.warning`, next to the stable icon, and no print action even with a printer configured.
- **Count line:** above the list when at least one entry is flagged. The text is `1 analysis needs sign-off` or `<n> analyses need sign-off`. It has a `FilterChip` labelled `Show only these`, which narrows the list to flagged entries. The export keeps exporting what is shown.
- **`_reprint` guard:** `_reprint` already re-reads the entry after its prompts (copies, mismatch dialog). If the stored entry is flagged by then, show a SnackBar with `kSignOffBeforePrintMessage` and stop.

- [ ] **Step 1: Write the failing tests**

  ```dart
  testWidgets('a flagged entry shows the badge and no print action', ...);
  //   with labelPrinting configured: find.byKey(ValueKey('analysis-needs-signoff-a1')) findsOneWidget;
  //   find.byKey(ValueKey('analysis-print-a1')) findsNothing; an unflagged entry keeps its print action
  testWidgets('the count line counts flagged entries and filters to them', ...);
  //   2 flagged + 1 not: text '2 analyses need sign-off'; tap the filter → 2 tiles; tap again → 3
  testWidgets('no flagged entries: no count line', ...);
  testWidgets('an entry flagged while its print prompt is open prints nothing', ...);
  //   unflagged entry; tap print; while the copies prompt is up, fake.setNeedsSignoff(id, true)
  //   (stands in for sync); confirm the prompt → SnackBar kSignOffBeforePrintMessage, no print call
  ```

- [ ] **Step 2: Run them and see them fail**

  Run: `flutter test test/ui/screens/gas_analysis_log_screen_test.dart`
  Expected: the new tests FAIL.

- [ ] **Step 3: Implement the badge, the count line, the filter state and the guard.** Use theme tokens only (`context.palette`, `SafetyColors`, `Radii`); no hard-coded colours.

- [ ] **Step 4: Run the tests and see them pass**

  Run: `flutter test test/ui/screens/gas_analysis_log_screen_test.dart`
  Expected: PASS, the existing `the busiest tile fits a phone` included (keep the badge compact).

- [ ] **Step 5: Commit**

  ```bash
  git add lib/ui/screens/gas_analysis_log_screen.dart test/ui/screens/gas_analysis_log_screen_test.dart
  git commit -m "feat(analyzer): show and filter analyses that need sign-off; no print until signed off"
  ```

---

### Task 6: Edit sheet: cylinder, fill pressure, "for", delete, sign off

**Files:**
- Modify:
  - `lib/ui/widgets/analysis_edit_sheet.dart`
  - `lib/ui/screens/gas_analysis_log_screen.dart` (handle the outcome)
- Test:
  - `test/ui/widgets/analysis_edit_sheet_test.dart`
  - `test/ui/screens/gas_analysis_log_screen_test.dart`

**Interfaces:**
- Consumes: Task 1's `GasAnalysisEdit` and `GasAnalysesDaoLike` (`update`, `softDelete`, `list(cylinderId:)`, `listCylinderChoices`); `gasRoleForCylinderRole`.
- Produces:
  ```dart
  enum AnalysisEditOutcome { cancelled, saved, signedOff, signOffAndPrint, deleted }
  Future<AnalysisEditOutcome> showAnalysisEditSheet(BuildContext context, {
    required GasAnalysesDaoLike dao, required GasAnalysis analysis,
    required List<DesiredMix> mixOptions,
    String? suggestedAnalysedBy, // used when the entry has no "analysed by"
    bool canPrint = false,       // offers "Sign off and print" on a flagged entry
  });
  ```
  Widget keys:
  - existing: `analysis-edit-save`, `-cancel`, `-diver`, `-notes`, `-role`;
  - new: `analysis-edit-cylinder`, `analysis-edit-pressure`, `analysis-edit-for`, `analysis-edit-delete`, `analysis-delete-confirm`, `analysis-edit-signoff`, `analysis-edit-signoff-print`.

Behaviour (spec §9):
- **Cylinder dropdown,** filled from `listCylinderChoices()`. "No cylinder" is first. If the entry's `cylinderId` isn't in the list, it stays as an item labelled with `analysis.cylinderDisplay` and stays selected.
- **Picking a cylinder:**
  - The role becomes `gasRoleForCylinderRole(choice.role)`.
  - If no desired mix is picked, take the desired mix and role from the newest entry of `list(cylinderId: id)` that has another id and a desired mix.
- **Fill pressure:** in bar, accepting `,` or `.`; blank means null. Anything else shows `Enter a pressure in bar` and disables Save and Sign off.
- **"For":** a free-text field.
- **"Analysed by":** starts from `suggestedAnalysedBy` when the entry has none.
- **Delete:** a confirm dialog, "Delete this analysis?" with Cancel / Delete. Then `softDelete`, close, outcome `deleted`.
- **Flagged entry:**
  - The primary button is `Sign off`. It is enabled only with a non-blank "analysed by" and a desired mix. It saves with `signOff: true` and returns `signedOff`.
  - With `canPrint`, `Sign off and print` does the same and returns `signOffAndPrint`.
  - `Save` stays, keeps the flag, and returns `saved`.
- **Unflagged entry:** Save and Cancel, as today.
- **Measured values:** shown read-only, as today.
- **Log screen:**
  - `suggestedAnalysedBy` is the first non-blank `analysedBy` in the loaded list.
  - `canPrint` is `labelPrinting?.isConfigured == true`.
  - `signOffAndPrint` re-reads the entry and goes through `_reprint`.
  - `deleted` shows `Deleted <mix> analysis.`, as the swipe does.
  - Wherever the old `bool` was used (the "Change desired mix" path), "changed" means any outcome except `cancelled`.

- [ ] **Step 1: Write the failing tests**

  ```dart
  testWidgets('cylinder, fill pressure and for are saved', ...);       // update gets cylinderId 'c2', 210.0, 'Alex'
  testWidgets('picking a cylinder takes the desired mix and role from its latest analysis', ...);
  //   fake has an older entry for 'c2' with DesiredMix(32, 0), bailout → sheet shows EAN32 picked
  testWidgets('an unknown cylinder survives an unrelated edit', ...);
  //   entry cylinderId 'gone' not in choices; change notes, Save → update.cylinderId == 'gone'
  testWidgets('a bad fill pressure blocks saving', ...);              // '21o' → error text, Save disabled
  testWidgets('Delete asks first, then soft-deletes and returns deleted', ...);
  testWidgets('Cancel in the delete dialog deletes nothing', ...);
  testWidgets('a flagged entry signs off only with a name and a desired mix', ...);
  //   no mix → signoff disabled; pick EAN32 + name → enabled; tap → update.signOff true, outcome signedOff
  testWidgets('Save on a flagged entry keeps the flag', ...);         // update.signOff false, outcome saved
  testWidgets('Sign off and print is offered only with canPrint', ...);
  testWidgets('analysed by starts from the suggestion when empty', ...);
  // log screen:
  testWidgets('signing off from the log prints when asked', ...);    // outcome signOffAndPrint → one print call
  testWidgets('deleting from the sheet shows the deleted SnackBar', ...);
  ```

- [ ] **Step 2: Run them and see them fail**

  Run: `flutter test test/ui/widgets/analysis_edit_sheet_test.dart test/ui/screens/gas_analysis_log_screen_test.dart`
  Expected: the new tests FAIL. Existing tests that expect a `bool` from the sheet fail too; update them to the outcome enum in this step.

- [ ] **Step 3: Implement the sheet changes and the log screen's outcome handling.**

  Keep the existing double-tap guard (`_saving`) for every button that writes. The fill-pressure parser follows `cylinder_detail_screen.dart`'s `_parseDecimal` (comma or point).

- [ ] **Step 4: Run the whole suite**

  Run: `flutter analyze && flutter test`
  Expected: analyze reports no issues, and all tests pass.

- [ ] **Step 5: Commit**

  ```bash
  git add lib/ui/widgets/analysis_edit_sheet.dart lib/ui/screens/gas_analysis_log_screen.dart test/ui
  git commit -m "feat(analyzer): sign off, delete and edit cylinder, fill pressure and 'for' in the edit sheet"
  ```

---

## After the last task

- Open the PR, which refers to the issue and to #113. In the description, list:
  - the deploy-0021-first note;
  - what plans 2 and 3 will build on: `bridge_protocol.dart`, `recordToAnalysis`, `addFromBridge`, `setNeedsSignoff`, `AnalysisEditOutcome`.
- Nothing here changes behaviour for today's users until a bridge exists, apart from the CSV's two new columns and the extra fields in the edit sheet.

---

## Tasks 7–9: Log on OK over USB (added 2026-11-03)

Egbert: "Log on OK can be created already for directly connected SOLO." Spec §4c and decision 17. These tasks make Log on OK work with the SOLO on a USB cable (desktop serial, Android OTG) while the analyzer screen is open. They reuse Tasks 1–6 unchanged, apart from the two small additions in Task 7.

### Task 7: Hold detector (pure Dart), `usb_ok` source, printable copy

**Files:**
- Create:
  - `lib/analyzer/hold_detector.dart`
  - `test/analyzer/hold_detector_test.dart`
- Modify:
  - `lib/data/models/gas_analysis.dart`: add `CaptureSource.usbOk` and `GasAnalysis.withNeedsSignoff`
  - `lib/analyzer/bridge/record_to_analysis.dart`: add a `source` parameter
  - `test/_helpers/solo_capture_log.dart`: ERROR times, and a replay helper
  - `test/_helpers/fake_gas_analyses_dao.dart`: replace `_copy` with `withNeedsSignoff` where it fits
- Test:
  - `test/analyzer/hold_detector_test.dart`
  - `test/data/models/gas_analysis_test.dart`
  - `test/analyzer/bridge/record_to_analysis_test.dart`

**Interfaces:**
- Produces:
  ```dart
  // lib/analyzer/hold_detector.dart — the Dart twin of the firmware rule, spec §1 and §4c
  const Duration kHoldSilence = Duration(seconds: 2);
  const Duration kFirstHoldMinFlow = Duration(seconds: 5);
  const Duration kNextHoldMinFlow = Duration(seconds: 3);
  const Duration kHoldWindow = Duration(seconds: 30);
  class DetectedHold {
    final Duration heldAt;                  // elapsed time of the held (last) line
    final String heldLine;
    final List<BridgeWindowLine> window;    // lines within kHoldWindow up to and including the held line; offsets ms relative to heldAt (≤ 0, last is 0), oldest first
  }
  class HoldDetector {
    HoldDetector({this.silence = kHoldSilence, this.firstMinFlow = kFirstHoldMinFlow,
        this.nextMinFlow = kNextHoldMinFlow, this.window = kHoldWindow});
    void addLine(Duration elapsed, String line); // only lines where parseSoloLine(line) != null count
    DetectedHold? tick(Duration elapsed);       // returns a hold at most once per silence
    void detached();                            // transport gone: forget lines, arming and hold count
  }
  // gas_analysis.dart
  //   CaptureSource.usbOk: dbValue 'usb_ok'; fromDb('usb_ok') → usbOk
  //   GasAnalysis withNeedsSignoff(bool value) — a copy with only that flag changed
  // record_to_analysis.dart
  //   recordToAnalysis({..., CaptureSource source = CaptureSource.bridgeOk}) — the saved analysis carries it
  // test/_helpers/solo_capture_log.dart
  //   SoloCaptureLog gains `final List<Duration> errors` (ERROR line times = USB detach)
  //   List<DetectedHold> replayCapture(SoloCaptureLog log, HoldDetector d, {Duration step = const Duration(milliseconds: 100)})
  //     walks time from 0 in `step`s to the last event + 3 s; feeds lines at their elapsed, calls
  //     d.detached() at each error time, collects every tick() result
  ```
- The rule:
  - `flowStart` is set by the first data line after construction or `detached()`, and by the first line after a recorded hold (the resume).
  - A hold fires on `tick(t)` when all of these hold:
    - a line has been seen;
    - `t − lastLineAt ≥ silence`;
    - no hold has fired for this silence yet;
    - `lastLineAt − flowStart` is at least `firstMinFlow` (if no hold has fired since attach) or `nextMinFlow` (otherwise).
  - A silence that didn't fire doesn't move `flowStart`. Dips under 2 s therefore never reset arming.

- [ ] **Step 1: Write the failing tests**
  ```dart
  test('capture a: two holds, at the 28.7 s and the 7.9 s pause', () {
    final holds = replayCapture(readSoloCaptureLog('test/fixtures/analyzer/solo_ok_presses_2026-11-03_a.txt'), HoldDetector());
    expect(holds.map((h) => h.heldAt.inMilliseconds), [58357, 119677]);
    expect(holds[0].heldLine, contains('Ti  22.0'));
    expect(holds[1].heldLine, contains('Ti  22.2'));
    expect(holds[0].window.last.offsetMs, 0);
    expect(holds[0].window.first.offsetMs, greaterThanOrEqualTo(-30000));
  });
  test('capture b: quick double presses and the switch-off make no hold; the 20.9 s pause makes one', () {
    final holds = replayCapture(readSoloCaptureLog('test/fixtures/analyzer/solo_ok_presses_2026-11-03_b.txt'), HoldDetector());
    expect(holds.map((h) => h.heldAt.inMilliseconds), [17518]);
    expect(holds.single.heldLine, contains('Ti  22.5'));
  });
  test('no hold before 5 s of flow', () { /* lines every 200 ms from 0 to 4.8 s, then ticks to 10 s → none */ });
  test('one hold per silence', () { /* 10 s of lines, then ticks every 100 ms for 30 s → exactly one */ });
  test('after a hold, 3 s of flow arms the next one', () { /* hold; resume; 2.8 s of lines + silence → none; then 3.2 s + silence → one */ });
  test('a detach before 2 s of silence cancels the hold', () { /* 10 s of lines, detached() at +1.0 s, ticks to +5 s → none */ });
  test('non-data lines are not flow', () { /* 10 s of 'Divesoft SOLO' banner lines then silence → none */ });
  // gas_analysis_test.dart
  test('usb_ok round-trips', () { expect(CaptureSource.usbOk.dbValue, 'usb_ok'); expect(CaptureSource.fromDb('usb_ok'), CaptureSource.usbOk); });
  test('withNeedsSignoff changes only the flag', () { /* every other field equal */ });
  // record_to_analysis_test.dart
  test('the source is carried into the analysis', () { /* source: CaptureSource.usbOk → analysis.captureSource == usbOk */ });
  ```

- [ ] **Step 2: Run them and see them fail**

  Run: `flutter test test/analyzer/ test/data/models/gas_analysis_test.dart`
  Expected: compile errors (`HoldDetector`, `usbOk` and `withNeedsSignoff` are undefined).

- [ ] **Step 3: Implement** the detector, the model additions, the `source` parameter and the helpers.

  `lib/analyzer/hold_detector.dart` is pure Dart. It imports only `parseSoloLine` and `BridgeWindowLine`. The window is trimmed on each `addLine`, so memory stays bounded.

- [ ] **Step 4: Run the tests and see them pass**

  Run: `flutter analyze && flutter test test/analyzer/ test/data/`
  Expected: clean, PASS.

- [ ] **Step 5: Commit**

  `feat(analyzer): Dart hold detector for OK presses over USB, tested on the SOLO captures`

---

### Task 8: `UsbOkLogger` (pure Dart)

**Files:**
- Create:
  - `lib/analyzer/usb_ok_logger.dart`
  - `test/analyzer/usb_ok_logger_test.dart`

**Interfaces:**
- Consumes:
  - `AnalyzerTransport` (`lib/analyzer/transport/analyzer_transport.dart`: `lines`, `statusChanges`, `status`);
  - from Task 7: `HoldDetector`, `DetectedHold`, `CaptureSource.usbOk`, `GasAnalysis.withNeedsSignoff`;
  - from Task 3: `recordToAnalysis`, `LogOnOkSetup`, `BridgeClock`, `SaveRecord`, `SkipRecord`, `gasMixName`;
  - from Task 2: `BridgeRecord`, `FeedbackCode`.
- Produces:
  ```dart
  typedef OkSetup = ({LogOnOkSetup setup, int copies});
  class OkLogResult {
    final FeedbackCode code; final String text; // the feedback (printed/saved/check/skipped/error)
    final String? analysisId;                   // the saved row's id; null when nothing was saved
    final bool complete;                        // saved with needs_signoff = 0 (printed if a print was wanted)
  }
  class UsbOkLogger {
    UsbOkLogger({
      required Future<bool> Function(String id, NewGasAnalysis a) save,   // dao.addFromBridge
      required Future<void> Function(String id) markComplete,             // dao.setNeedsSignoff(id, false)
      Future<void> Function(GasAnalysis a, int copies)? printLabel,       // throws on failure
      Duration Function()? elapsed,     // monotonic clock; default a started Stopwatch
      DateTime Function()? now,         // default DateTime.now
      Duration? tickInterval = const Duration(milliseconds: 200), // null: no timer; tests call tick()
    });
    OkSetup Function()? setupProvider;  // set by the save card; null → LogOnOkSetup() with 1 copy
    Stream<OkLogResult> get results;    // broadcast
    void attach(AnalyzerTransport t);   // lines → detector; a status other than connected → detector.detached()
    void detach();
    void tick();                        // runs the detector at elapsed(); handles a hold
    Future<void> dispose();
  }
  ```
- Handling a hold, one at a time (chain the futures, so a second hold waits for the first):
  1. `rid = now().microsecondsSinceEpoch.toString()`.
  2. `record = BridgeRecord(rid: rid, boot: 0, upMs: heldAt.inMilliseconds, wallMs: 0, live: true, window: hold.window, heldLine: hold.heldLine)`.
  3. `outcome = recordToAnalysis(record: record, bridgeId: 'usb', setup: provider.setup, clock: BridgeClock(boot: 0, upMs: elapsed().inMilliseconds), now: now(), active: true, source: CaptureSource.usbOk)`.
  4. **Skip:** emit `(outcome.feedback, outcome.feedbackText, null, false)`.
  5. **Save:** `await save(rowId, analysis)`. If it throws, emit `(error, 'SAVE FAILED', null, false)`.
  6. **`printLabel` set, and a print is wanted:**
     - call `await printLabel(GasAnalysis.fromNew(rowId, analysis).withNeedsSignoff(false), copies)`;
     - if it succeeds: `await markComplete(rowId)` and emit `(printed, mixName, rowId, true)`;
     - if it throws: emit `(check, 'PRINT FAILED', rowId, false)`.
  7. **Otherwise:** emit `(outcome.feedback, outcome.feedbackText, rowId, !analysis.needsSignoff)`.

- [ ] **Step 1: Write the failing tests**

  Use a test-file `FakeTransport implements AnalyzerTransport` with `StreamController`s, a manual clock, `tickInterval: null`, and `steadyLine(o2, he)` lines every 200 ms.

  ```dart
  test('an OK on a stable EAN32 with name and mix saves complete', () { /* 25 s steady 32.0/0, setup EdP + DesiredMix(32,0), printOnOk false; 2.2 s silence; tick → save called once with captureSource usbOk, needsSignoff false; result (saved,'EAN32', id, complete: true) */ });
  test('print on OK prints a copy marked complete, then clears the flag', () { /* printOnOk + printerConfigured, printLabel fake records its GasAnalysis: needsSignoff false; save got needsSignoff true; markComplete(id) called after print; result (printed,'EAN32', id, true) */ });
  test('a failed print leaves the entry flagged', () { /* printLabel throws → markComplete not called; result (check,'PRINT FAILED', id, false) */ });
  test('room air is not saved', () { /* steady 20.9/0.3 → save not called; result (skipped,'AIR - NOT LOGGED', null, false) */ });
  test('an OK before stable saves flagged', () { /* 8 s of lines → (check,'NOT STABLE', id, false) */ });
  test('no setup provider: saved, needs sign-off', () { /* (saved,'NO MIX SET', id, false) */ });
  test('a failed save is reported', () { /* save throws → (error,'SAVE FAILED', null, false) */ });
  test('unplugging during the silence saves nothing', () { /* status → disconnected at +1 s; tick at +3 s → no save */ });
  test('analysed_at is the time of the held line', () { /* now = T at tick 2.2 s after the held line → analysedAt == T − 2.2 s (±1 ms) */ });
  ```

- [ ] **Step 2: Run them and see them fail**

  Run: `flutter test test/analyzer/usb_ok_logger_test.dart`
  Expected: FAIL; the file doesn't exist.

- [ ] **Step 3: Implement `lib/analyzer/usb_ok_logger.dart`** to the interface.

  It is pure Dart: `dart:async` only, with no Flutter or DAO imports, because the DAO is passed in as functions.

- [ ] **Step 4: Run the tests and see them pass**

  Run: `flutter analyze && flutter test test/analyzer/`
  Expected: clean, PASS.

- [ ] **Step 5: Commit**

  `feat(analyzer): UsbOkLogger saves and prints an analysis on the SOLO's OK press`

---

### Task 9: "Log on OK" on the analyzer screen and the save card

**Files:**
- Modify:
  - `lib/ui/notifiers/settings_notifier.dart`
  - `lib/ui/screens/analyzer_screen.dart`
  - `lib/ui/widgets/analysis_save_card.dart`
- Test:
  - Create `test/ui/screens/analyzer_log_on_ok_test.dart`.
  - Extend `test/ui/screens/analyzer_save_analysis_test.dart` only if an existing expectation changes.

**Interfaces:**
- Consumes: Task 8's `UsbOkLogger`, `OkSetup`, `OkLogResult`; Task 6's `showAnalysisEditSheet` / `AnalysisEditOutcome`; Task 3's `isRoomAir` and `LogOnOkSetup`; the `addFromBridge`, `setNeedsSignoff` and `softDelete` DAO methods.
- Produces:
  - **Settings**, following the `labelUse14ForDeeperMixes` pattern, device-local:
    - `analyzerLogOnOk` (bool, key `analyzer_log_on_ok`, default false) with `setAnalyzerLogOnOk(bool)`;
    - `analyzerAnalysedBy` (String?, key `analyzer_analysed_by`) with `setAnalyzerAnalysedBy(String?)`.
  - **`AnalyzerScreen`** gains `@visibleForTesting UsbOkLogger Function()? okLoggerFactory`. The default factory builds a real logger wired to `analysesDao` and `labelPrinting`.
  - **`AnalysisSaveCard`** gains:
    - `UsbOkLogger? okLogger` (non-null means Log-on-OK mode);
    - `String? initialAnalysedBy`;
    - `ValueChanged<String?>? onAnalysedByChanged`.
  - **Widget keys:** `analyzer-log-on-ok`, `analysis-for`, `analysis-print-on-ok`, `analysis-ok-hint`, `analysis-ok-result`, `analysis-ok-edit`, `analysis-ok-delete`.

Behaviour (spec §4 and §4c):
- **Analyzer screen:**
  - A `SwitchListTile` (`analyzer-log-on-ok`) titled "Log on OK", subtitle "Press OK on the SOLO to save. Keep this screen open."
  - It is shown when `analysesDao != null` and the selected source isn't the demo.
  - With the switch on and a non-demo session connected, the screen builds the logger, attaches it to `_controller.transport` and passes it to the card. On disconnect, switch-off or dispose: `detach()` / `dispose()`.
- **The card, in both modes:**
  - a "For" field (`analysis-for`), saved as `analysedFor`;
  - "Analysed by" starts from `initialAnalysedBy` and reports edits through `onAnalysedByChanged`. The screen persists them with `setAnalyzerAnalysedBy`.
- **The card, in Log-on-OK mode:**
  - It sets `okLogger.setupProvider` to its current fields:
    - analysed by, desired mix, role, for, cylinder, fill pressure, notes;
    - "Print label on OK" (`analysis-print-on-ok`, default on when a printer is configured; shown only in this mode);
    - `printerConfigured`, `modPpo2s` and copies.
  - The Save buttons are replaced by `analysis-ok-hint`, "Press OK on the SOLO to save", **unless** the live reading is room air (`isRoomAir`). Then the Save buttons stay, with the hint "Air isn't logged on OK. Tap Save."
  - **On each `OkLogResult`:**
    - Show `analysis-ok-result`:
      - printed → "Printed <text>";
      - saved and complete → "Saved <text>";
      - saved and not complete → "Saved, needs sign-off: <text>";
      - check → "Needs sign-off: <text>";
      - skipped → "Room air: not logged";
      - error → "Not saved: <text>".
    - With an id, add **Edit** (`analysis-ok-edit`, opens `showAnalysisEditSheet` on the stored entry) and **Delete** (`analysis-ok-delete`, a confirm, then `softDelete`).
    - When `complete`, clear the cylinder, fill pressure and notes.
    - Keep the name, desired mix, role, "for" and print switch. The desired mix stays picked here, a deliberate exception to the clear-after-save rule (spec §4).
- **Not in this task:** preselecting the Blend target (plan 3, spec §4c).

- [ ] **Step 1: Write the failing tests**

  Use the screen with a fake transport option (non-demo), `FakeGasAnalysesDao`, and an `okLoggerFactory` that builds a logger with a manual clock and `tickInterval: null`, held by the test.

  ```dart
  testWidgets('Log on OK is offered for USB, not for the demo', ...);
  testWidgets('with Log on OK on, the card shows the OK hint instead of Save', ...);
  testWidgets('room air brings Save back', ...);
  testWidgets('an OK press saves, shows the result and offers Edit and Delete', ...);  // dao.addedFromBridge.length == 1
  testWidgets('Delete on the result asks, then soft-deletes', ...);
  testWidgets('a complete save clears cylinder, pressure and notes, keeps name, mix and role', ...);
  testWidgets('analysed by is remembered', ...);  // settings.analyzerAnalysedBy == 'EdP' after typing; prefilled on a new screen
  ```

- [ ] **Step 2: Run them and see them fail**

  Run: `flutter test test/ui/screens/analyzer_log_on_ok_test.dart`
  Expected: FAIL.

- [ ] **Step 3: Implement the settings, the screen and the card.**

  Use theme tokens only, and keep the card's existing double-tap guard. Don't change the manual flow outside Log-on-OK mode, except for the new "For" field and the remembered name.

- [ ] **Step 4: Run the whole suite**

  Run: `flutter analyze && flutter test`
  Expected: clean, all pass.

- [ ] **Step 5: Commit**

  `feat(analyzer): Log on OK over USB on the analyzer screen`
