# Blend to Analysis (open blends) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Finishing a recipe on the Blend tab saves an *open blend*; the analysis of that cylinder closes it, carries its target mix and role, and warns when the gas is off. A residual analysis feeds the Blend tab.

**Architecture:** A new synced PowerSync table `open_blends`, with a DAO whose "open" is derived from the link to a live analysis. The matching (which blend an analysis closes), the settle colour, the role guess and the mismatch warning are pure Dart in `lib/analysis/open_blend_match.dart`, and every save path uses them: the analyzer card, Log on OK (USB and bridge) and sign-off. Closing goes through one DAO transaction that only closes a blend that is still open, so a second OK press can't close the same blend twice. This replaces the single 24 h Blend target (`unusedRecentTarget`, `markRecentTargetUsed`) and the lease logic built around it.

**Tech Stack:** Flutter/Dart, PowerSync (client schema plus Supabase Postgres), SharedPreferences, flutter_test.

**Spec:** `docs/superpowers/specs/2026-11-12-blend-to-analysis-design.md` (approved 2026-11-13, PR #209, issue #112). Read it before any task. The plan argues from it and doesn't repeat it.

## Global Constraints

- Work on a new branch `feat/112-open-blends` off `main`, in a worktree. One PR, which closes #112.
- **Migration `0025`**, unless another migration lands first; then take the next free number. Egbert deploys it, and the sync-config line, **before** a build with this ships. The upload connector sends whole rows, so Supabase rejects uploads from the new build until the columns exist.
- **Every new synced table** gets:
  - RLS
  - `revoke all … ; grant select, insert, update, delete … to authenticated, service_role;` (`supabase/lint_migrations.sh` enforces it)
  - the `powersync` publication block
  - the client schema
  - a line in `infra/powersync-sync-rules.yaml`
  - an entry in the `cloud_data_wiper.dart` list and the `owner_id_backfiller.dart` list

  Mirror `0023_user_acknowledgements.sql` and #186 (`git show d226413 --stat`).
- **The sync-config line:** if PR #208 (Sync Streams) is merged by then, add `- SELECT * FROM open_blends WHERE owner_id = auth.user_id()` under `streams.user_data.queries`. Its guard test `test/sync/cloud/sync_streams_config_test.dart` fails without it. Otherwise add `- SELECT * FROM open_blends WHERE owner_id = request.user_id()` under `bucket_definitions.user_data.data`.
- **No foreign key** from `open_blends.closed_by_analysis_id` to `gas_analyses`. It's a soft reference, like `gas_analyses.cylinder_id`, so upload order can't fail and the connector's orphan-drop logic never touches it.
- Times are epoch **milliseconds** (`bigint` / `integer`), and metric everywhere. No `boolean` or `timestamptz` columns. Flags are `integer` 0/1.
- **Never** run `dart format` on an existing file. Match the style around your edit by hand.
- **Old builds:**
  - `GasRole.fromDb` must keep mapping any unknown string to `bailout`.
  - `is_residual` must default to 0 in Postgres, so a row from an old build is not residual.
- **Settings stay device-local** (`SharedPreferences` in `SettingsNotifier`):
  - `blendSettleMinutes`: int, default **60**, range 0–1440
  - `blendDiluentMaxL`: double, default **3.0**, range 0.5–50
- **Copy uses "O2" in ASCII**, like `mixMatchText`.
- **Role guess thresholds:**
  - O2 **above 32** % → bailout
  - otherwise, water capacity **≤** diluent size → diluent
  - otherwise → bailout
- **Settle colour:**
  - red: elapsed < half the settle time
  - orange: half ≤ elapsed < full
  - green: elapsed ≥ full

  A settle time of 0 is always green. An elapsed time below zero (a clock that moved back) is red.
- **The loud warning's PPO2** is `bailoutModPpo2(o2PercentForRule: target.o2Percent, use14ForDeeperMixes: settings.labelUse14ForDeeperMixes)` from `lib/labels/cylinder_label.dart`.
- Each task ends with `flutter analyze` clean and the task's tests green. The final task runs the full `flutter test`.

## Decisions this plan makes (the spec left them to the builder)

1. **Which blend an analysis closes** (`blendForAnalysis`, Task 3), the same rule on every path:
   - residual → none
   - the diver picked a blend or "none" → that
   - the diver picked a **mix** (chip or "Other…") → the oldest open blend whose target **equals** that mix, or none
   - automatic → the best-ranked open blend if it grades match or orange, else none

   Sign-off uses the same rule. A signed-off entry with a desired mix closes the oldest open blend of exactly that mix. One without a desired mix matches by reading, and then takes the blend's target and role.
2. **Role order:** a tapped role, then the blend's role, then the cylinder's Equipment role, then the mix rule (`gasRoleForMix`). `LogOnOkSetup.gasRole` therefore splits into `tappedRole` and `cylinderRole`.
3. **An open blend whose closing analysis isn't on this device yet** (the link is set, the row is missing) counts as **closed**, so a sync in flight doesn't briefly reopen it. Only a link to a soft-deleted analysis reopens it.
4. **Where things show:**
   - The open-blends list sits on the **Blend** tab, under the plan band, with Dismiss per row.
   - The count shows as a badge on the Gas tab bar's **Blend** label, on every Gas tab.
   - The Analyse card shows one "Closes …" row with a Change action and the warning.
   - The log shows a "Residual" tag and the warning line.
5. The residual flag is set at save and **isn't editable** afterwards, like `capture_source`.
6. The Blend tab keeps its device-local target memory for its inputs. `recentTarget`, `unusedRecentTarget`, `markRecentTargetUsed` and the `blend_target_used` / `blend_target_edited_at` keys go away. The mix chips offer open-blend targets where they offered the Blend target.
7. `MixPickSource.blendTarget` keeps its name; its UI text becomes ", an open blend".

## Review Focus

1. **Two OK presses in quick succession, one open Tx18/45:** the first closes it. The second saves with desired mix Tx18/45 and closes nothing; no error, no double close. Task 4 (DAO) and Task 10 (processor) test this.
2. **The closing analysis is deleted on another device:** after sync the blend is open again and counted. An analysis that isn't synced yet keeps the blend closed. Task 4 tests both.
3. **A blend's `blended_at` is in the future** (another device's clock): the row shows "just now" and red, never a negative time or a crash. Task 3 (`settleState`) and Task 8 (row text) test this.
4. **Residual with Log on OK on:**
   - the press saves `is_residual = 1`
   - no label prints, even with "Print a label on each OK" on
   - no blend closes
   - the Blend tab's residual mix fills from it
   - a residual with no fill pressure leaves the Blend residual pressure as it was

   Task 10 and Task 11 test this.
5. **The picked blend is dismissed or closed elsewhere while the unstable-reading dialog is up:** the save still succeeds. `closeBlend` falls back to the oldest open blend of the same target, or closes nothing; no exception reaches the diver. Task 4 and Task 9 test this.

---

### Task 1: Four gas roles

**Files:**
- Modify: `lib/data/models/gas_analysis.dart` (enum `GasRole`)
- Modify: `lib/ui/widgets/analysis_save_card.dart:~190` (role segmented button)
- Modify: `lib/ui/widgets/analysis_edit_sheet.dart:~430` (role segmented button)
- Test: `test/data/models/gas_analysis_test.dart`, `test/labels/cylinder_label_test.dart`, `test/ui/widgets/analysis_edit_sheet_test.dart`

**Interfaces:**
- Produces:
  - `enum GasRole { bailout, diluent, backgas, deco }` with `dbValue` `'bailout' | 'diluent' | 'backgas' | 'deco'`
  - `GasRole.fromDb(String?)`: known values map to themselves, anything else to `bailout`
  - `String get label`: `'Diluent' | 'Bailout' | 'Backgas' | 'Deco'`
  - `bool get isDiluent`

- [ ] **Step 1: Write the failing tests**
  - `fromDb round-trips all four roles`: for each `r` in `GasRole.values`, `GasRole.fromDb(r.dbValue) == r`.
  - `fromDb maps unknown, null and empty to bailout`: `'stage'`, `null` and `''` all give `GasRole.bailout`.
  - In `cylinder_label_test.dart`: `deco and backgas print like bailout`. The same analysis (EAN50, desired 50/0) with role `deco` or `backgas` gives `kind == CylinderLabelKind.bailout` and the same `headlineMeters` as with `bailout`.
  - In `analysis_edit_sheet_test.dart`: `the role control offers four roles`. Find the texts `Diluent`, `Bailout`, `Backgas`, `Deco`; tapping `Deco` and saving gives an update with `gasRole == GasRole.deco`.
- [ ] **Step 2: Run them and see them fail.** Run `flutter test test/data/models/gas_analysis_test.dart test/labels/cylinder_label_test.dart test/ui/widgets/analysis_edit_sheet_test.dart`. Expect a compile error on `GasRole.deco`.
- [ ] **Step 3: Implement the enum change.** Then make both segmented buttons use `GasRole.values` with `role.label`, in that order: Diluent, Bailout, Backgas, Deco. Use `ButtonSegment` labels short enough for a phone. `cylinder_label.dart` already branches on `== GasRole.diluent`, so leave it as is. Update existing finders that look for `'Bailout/deco'`.
- [ ] **Step 4: Run the three files plus `test/ui/widgets/analysis_save_card_print_test.dart` and `test/ui/widgets/analysis_save_defaults_test.dart`. Expect them to pass.**
- [ ] **Step 5: Commit:** `feat(gas): backgas and deco gas roles (#112)`

### Task 2: Migration 0025, the client schema and the residual flag

**Files:**
- Create: `supabase/migrations/0025_open_blends.sql`
- Modify: `lib/sync/cloud/powersync_schema.dart`, `infra/powersync-sync-rules.yaml`, `lib/sync/cloud/cloud_data_wiper.dart`, `lib/sync/cloud/owner_id_backfiller.dart`
- Modify: `lib/data/models/gas_analysis.dart`, `lib/data/db/gas_analyses_dao.dart`, `test/_helpers/fake_gas_analyses_dao.dart`
- Test: `test/sync/cloud/powersync_schema_test.dart`, `test/sync/cloud/owner_id_backfiller_test.dart`, `test/data/db/gas_analyses_dao_test.dart`

**Interfaces:**
- Produces:
  - Postgres and PowerSync table `open_blends`, columns:
    - `owner_id`
    - `target_o2_percent`, `target_he_percent` (int), `target_pressure_bar` (real)
    - `residual_o2_percent`, `residual_he_percent` (int), `residual_pressure_bar` (real)
    - `topoff_o2_percent`, `topoff_he_percent` (int)
    - `water_capacity_l` (real), `gas_role` (text), `blended_by` (text, nullable), `blended_at` (int ms)
    - `closed_by_analysis_id` (text, nullable)
    - `created_at`, `updated_at`, `deleted_at`, `version`, `sync_status`

    In Postgres, the ints are `integer`, the reals `double precision` and the times `bigint`. Everything is NOT NULL except `blended_by`, `closed_by_analysis_id` and `deleted_at`. Index `(owner_id, deleted_at)`.
  - Column `gas_analyses.is_residual`: `integer NOT NULL DEFAULT 0`, and `Column.integer('is_residual')` in the client schema.
  - `NewGasAnalysis.isResidual` and `GasAnalysis.isResidual` (`bool`, default false), carried by `fromNew`, `applyEdit` (unchanged by an edit) and `withNeedsSignoff`. The DAO writes it on insert and reads it (`!= 0`). `update` never touches it.

- [ ] **Step 1: Write the failing tests**
  - `powersync_schema_test.dart`: add `'open_blends'` to the expected table list, and assert that `gas_analyses` has a column `is_residual`.
  - `owner_id_backfiller_test.dart`: add an `open_blends` insert to the per-table map, the way `user_acknowledgements` is done (line ~214).
  - `gas_analyses_dao_test.dart`:
    - `is_residual round-trips and an edit keeps it`: add with `isResidual: true`, then `list().single.isResidual` is true; `update(...)` and it's still true.
    - `a row without is_residual reads as not residual`: a raw insert that omits the column gives `isResidual == false`.
- [ ] **Step 2: Run the three test files and see them fail.**
- [ ] **Step 3: Write `0025_open_blends.sql`.** Mirror 0023:
  - a header comment explaining open blends, the soft link, and "deploy before a build that writes these"
  - the table, the index, RLS "owner can rw", the revoke and grant, the publication block
  - `ALTER TABLE gas_analyses ADD COLUMN IF NOT EXISTS is_residual integer NOT NULL DEFAULT 0;`
  - `NOTIFY pgrst, 'reload schema';`

  Then:
  - add the `Table('open_blends', [...])` to `powersync_schema.dart`
  - add the sync-config line (see Global Constraints)
  - add `'open_blends'` to the wiper list before `'gas_analyses'`, with a comment that it soft-references analyses
  - add `'open_blends'` to the backfiller's `_syncedTables`
  - add the model field and the DAO column, and update `FakeGasAnalysesDao`
- [ ] **Step 4: Run `supabase/lint_migrations.sh` (expect OK), the three test files, and `test/sync/cloud/sync_streams_config_test.dart` if it exists. Expect them to pass.**
- [ ] **Step 5: Commit:** `feat(sync): open_blends table and gas_analyses.is_residual, migration 0025 (#112)`

### Task 3: Matching, settling, role guess and warning (pure Dart)

**Files:**
- Create: `lib/data/models/open_blend.dart`, `lib/analysis/open_blend_match.dart`
- Test: `test/analysis/open_blend_match_test.dart`

**Interfaces:**
- Produces, in `open_blend.dart`:
  ```dart
  class OpenBlend { final String id; final DesiredMix target; final double targetPressureBar;
    final DesiredMix residual; final double residualPressureBar; final DesiredMix topoff;
    final double waterCapacityL; final GasRole role; final String? blendedBy; final DateTime blendedAt; }
  class NewOpenBlend { /* same fields minus id */ }
  ```
- Produces, in `open_blend_match.dart`:
  ```dart
  typedef RankedBlend = ({OpenBlend blend, MixMatch grade});
  List<RankedBlend> rankOpenBlends({required double o2Percent, required double hePercent, required List<OpenBlend> open});
  sealed class BlendChoice {}  // AutoBlend(), NoBlend(), PickedBlend(OpenBlend blend)
  OpenBlend? blendForAnalysis({required double o2Percent, required double hePercent,
    required BlendChoice choice, DesiredMix? chosenMix, required bool residual, required List<OpenBlend> open});
  RankedBlend? nearestUnmatched({required double o2Percent, required double hePercent, required List<OpenBlend> open});
  enum SettleState { red, orange, green }
  SettleState settleState({required Duration sinceBlended, required int settleMinutes});
  typedef RoleGuess = ({GasRole role, String reason});
  RoleGuess guessBlendRole({required int targetO2Percent, required double waterCapacityL, required double diluentMaxL});
  enum WarningLevel { mild, loud }
  typedef MixWarning = ({WarningLevel level, String text});
  MixWarning? mixWarning({required GasRole role, required double o2Percent, required double hePercent,
    required DesiredMix target, required bool use14ForDeeperMixes});
  ```
- Rules:
  - `rankOpenBlends` sorts by grade level, then `o2Off`, then `heOff`, then `blendedAt`, oldest first.
  - `blendForAnalysis`:
    - `residual` → null
    - `PickedBlend` → its blend
    - `NoBlend` → null
    - `AutoBlend` with a non-null `chosenMix` → the oldest blend with `target == chosenMix`
    - `AutoBlend` with a null `chosenMix` → the first ranked blend if its level is match or orange, else null
  - `nearestUnmatched` is the first ranked blend when it grades red or hard, and null when there are no open blends or one matches.
  - `mixWarning`:
    - null for a match
    - `loud` when `!role.isDiluent` and the O2 is above the target
    - `mild` otherwise
  - Copy:
    - loud: `'O2 ${o2.toStringAsFixed(1)}% instead of ${target.o2Percent}%: MOD at $ppo2 is ${actual} m, not ${planned} m.'`, where `actual = limitDepthMeters(o2, ppo2, desiredO2Percent: target.o2Percent)`, `planned = limitDepthMeters(target.o2Percent.toDouble(), ppo2)`, and the PPO2 is written `1.6` or `1.4`
    - mild: `'Analysed ${gasMixName(o2, he)}, target ${target.name}'`
  - Role reasons: `'O2 above 32%'`, `'${capacity} L'` (whole when whole: `3 L`, `11.1 L`).

- [ ] **Step 1: Write the failing tests** (`open_blend_match_test.dart`, with an `ob(id, o2, he, {minutesAgo, role})` helper):
  - `oldest of two equal mixes is chosen`: two 18/45 blends, 30 and 90 min old; reading 18.4/44.5; `blendForAnalysis(choice: AutoBlend())` returns the 90-minute one.
  - `match beats orange, then the smaller O2 difference`: 21/35 and 18/45 open; reading 20.6/34.0 gives 21/35.
  - `no blend within orange closes nothing`: 50/0 open, reading 55.0/0 gives null; `nearestUnmatched` gives 50/0 with level `hard`.
  - `a chosen mix closes the oldest blend of exactly that mix`: `chosenMix: DesiredMix(21,35)`, 21/35 and 18/45 open, reading 18.0/45.0, gives 21/35.
  - `a chosen mix with no blend of that mix closes nothing`.
  - `PickedBlend closes a hard-mismatched blend`: picked 50/0, reading 55/0, returns it.
  - `residual never closes`: `residual: true` with a perfect match gives null.
  - `settleState`, with 60 min: 29 min red, 30 min orange, 59 min orange, 60 min green; `settleMinutes: 0` with 0 min green; −5 min red.
  - `guessBlendRole`:
    - 33 % in 3 L gives bailout, reason `'O2 above 32%'`
    - 32 % in 3 L gives diluent, reason `'3 L'`
    - 21 % in 3.0 L with max 3.0 gives diluent (≤)
    - 21 % in 7 L with max 3 gives bailout, reason `'7 L'`
    - 21 % in 7 L with max 7 gives diluent
  - `mixWarning`:
    - deco, reading 52.0 against 50/0, `use14: false`: level loud, text `'O2 52.0% instead of 50%: MOD at 1.6 is 20 m, not 21 m.'` (check the numbers against `limitDepthMeters` and fix the expectation to what that function returns, not by hand)
    - backgas 22.5/35 against 21/35: loud
    - deco 48.5 against 50: mild, `'Analysed EAN48, target EAN50'` (the mix name as `gasMixName` gives it)
    - diluent 23.0/35 against 21/35: mild
    - deco 50.4 against 50: null (a match)
- [ ] **Step 2: Run `flutter test test/analysis/open_blend_match_test.dart`. Expect a compile error.**
- [ ] **Step 3: Implement both files.** No Flutter imports; it's pure Dart like `standard_mix_pick.dart`.
- [ ] **Step 4: Run it and expect it to pass.**
- [ ] **Step 5: Commit:** `feat(gas): open-blend matching, settle colour, role guess and mix warning (#112)`

### Task 4: OpenBlendsDao

**Files:**
- Create: `lib/data/db/open_blends_dao.dart`, `test/_helpers/fake_open_blends_dao.dart`
- Test: `test/data/db/open_blends_dao_test.dart`

**Interfaces:**
- Consumes: `OpenBlend` and `NewOpenBlend` (Task 3), the `open_blends` table (Task 2).
- Produces:
  ```dart
  abstract class OpenBlendsDaoLike {
    Future<String> add(NewOpenBlend b);
    Future<List<OpenBlend>> listOpen();            // oldest first
    Stream<List<OpenBlend>> watchOpen();           // emits on open_blends or gas_analyses changes
    Future<bool> closeBlend(OpenBlend b, String analysisId); // b if still open, else oldest open of b.target; false if none
    Future<String?> closeOldestOpen(DesiredMix target, String analysisId); // id closed, or null
    Future<void> dismiss(String id);               // soft delete
  }
  class OpenBlendsDao implements OpenBlendsDaoLike { OpenBlendsDao(PowerSyncDatabase ps, SessionSource session); }
  ```
- Open SQL: `b.deleted_at IS NULL AND (b.closed_by_analysis_id IS NULL OR EXISTS (SELECT 1 FROM gas_analyses a WHERE a.id = b.closed_by_analysis_id AND a.deleted_at IS NOT NULL))`, scoped by owner as `GasAnalysesDao.list` does. The closing methods check "still open" with the same predicate **inside one `writeTransaction`**, then set `closed_by_analysis_id`, bump `version` and set `updated_at`.
- Follow `GasAnalysesDao`: a Dart UUID, `owner_id` from the session, `version` 1, `sync_status` 0.
- The fake keeps the same semantics in memory, including the deleted-analysis reopen: the fake takes a `Set<String> deletedAnalysisIds`.

- [ ] **Step 1: Write the failing tests** (`openPowerSyncForTest()` and `FakeSessionSource`, as in `user_acknowledgements_dao_test.dart`):
  - `add stores owner, fields and sync metadata`
  - `listOpen is oldest first and leaves out dismissed and closed`
  - `closeBlend twice on one blend closes it once`: the first call gives true; the second, with no other blend of that target, gives false
  - `closeBlend falls back to the oldest open blend of the same target`: two 18/45 blends; close A with x1, then `closeBlend(A, x2)` closes B
  - `closeOldestOpen picks the oldest of the target and ignores other mixes`
  - `deleting the closing analysis reopens the blend`: insert an analysis row, close against it, soft-delete the analysis (`GasAnalysesDao.softDelete`), and the blend is back in `listOpen()`
  - `a closing analysis not on this device keeps the blend closed`: close against `'missing-id'`, and `listOpen()` is empty
  - `dismiss is a soft delete with a version bump`
  - `watchOpen emits after a close`
- [ ] **Step 2: Run `flutter test test/data/db/open_blends_dao_test.dart` and expect it to fail.**
- [ ] **Step 3: Implement the DAO and the fake.**
- [ ] **Step 4: Run it and expect it to pass.**
- [ ] **Step 5: Commit:** `feat(gas): OpenBlendsDao with race-free closing (#112)`

### Task 5: Settle time and diluent cylinder size settings

**Files:**
- Modify: `lib/ui/notifiers/settings_notifier.dart`, `lib/ui/screens/settings/gas_tab.dart`
- Test: the existing settings notifier test file (`grep -l SettingsNotifier test/ui/notifiers`), and `test/ui/screens/settings/` for the gas tab if there's a test there; otherwise the gas-tab widget test that covers "Fill pressure starts at"

**Interfaces:**
- Produces:
  - `int get blendSettleMinutes` (default 60) and `Future<void> setBlendSettleMinutes(int)`, which clamps to 0–1440
  - `double get blendDiluentMaxL` (default 3.0) and `Future<void> setBlendDiluentMaxL(double)`, which clamps to 0.5–50
  - prefs keys `blend_settle_minutes` and `blend_diluent_max_l`

- [ ] **Step 1: Write the failing tests:** the defaults (60 and 3.0); a setter that persists and reloads; clamping (−5 → 0, 2000 → 1440, 0.1 → 0.5); and a widget test where entering `90` in the "Settle time" field updates the notifier.
- [ ] **Step 2: Run them and see them fail.**
- [ ] **Step 3: Implement.** Mirror `setAnalyzerFillPressureStartBar`. In `gas_tab.dart`, add both fields to the blending section, labelled "Settle time (min)" and "Diluent cylinder up to (L)", using the field widgets in `settings_fields.dart`.
- [ ] **Step 4: Run them and expect them to pass.**
- [ ] **Step 5: Commit:** `feat(settings): settle time and diluent cylinder size (#112)`

### Task 6: BlendNotifier, draft open blend, role chip state and residual fill-in

**Files:**
- Modify: `lib/ui/notifiers/blend_notifier.dart`
- Test: `test/ui/notifiers/blend_notifier_target_test.dart` (rename the groups), plus a new `test/ui/notifiers/blend_notifier_open_blend_test.dart`

**Interfaces:**
- Consumes: `guessBlendRole` (Task 3), `blendDiluentMaxL` (Task 5), `NewOpenBlend` (Task 3).
- Produces:
  - `RoleGuess get roleGuess`: from the target O2, the water capacity and `settings.blendDiluentMaxL`
  - `GasRole get role`: the override, or `roleGuess.role`
  - `bool get roleOverridden`
  - `void overrideRole(GasRole r)`
  - `NewOpenBlend draftOpenBlend({String? blendedBy, required DateTime now})`
  - `void openBlendSaved()`: clears the override
  - `void applyResidualAnalysis({required double o2Percent, required double hePercent, double? pressureBar})`: rounds to whole percents through `setCurrentMix`, and calls `setCurrentPressure` only when `pressureBar != null`
- Removes: `recentTarget`, `unusedRecentTarget`, `markRecentTargetUsed`, `_kLastEditedAt`, `_kTargetUsed`, `_lastEditedAt`, `_targetUsed`, `_recentTargetWindow` and the `now` constructor parameter, if nothing else uses it. Keep the target mix and pressure persistence (`loadTarget`) for the inputs, and update the library comment.

- [ ] **Step 1: Write the failing tests:**
  - `role guess follows target O2 and capacity`: target 18/45 with capacity 3 gives diluent; capacity 11.1 gives bailout; target 50/0 gives bailout with reason `'O2 above 32%'`
  - `diluent size setting changes the guess`: set `blendDiluentMaxL` to 7; capacity 7 gives diluent
  - `override applies to this blend only`: `overrideRole(GasRole.deco)` gives `role == deco`; after `openBlendSaved()` the role is the guess again
  - `draftOpenBlend carries target, residual, top-off, capacity, role, name and time`
  - `applyResidualAnalysis rounds and fills; null pressure keeps the pressure`
  - **Replace** the cases in the `recentTarget` groups: keep the `loadTarget` persistence cases (the target mix and pressure survive a restart; an edit before load wins) and delete the 24 h and "used" cases. They become open-blend cases in Tasks 9–11, as the spec asks.
- [ ] **Step 2: Run both files and see them fail.**
- [ ] **Step 3: Implement.** Also listen for `blendDiluentMaxL` changes through the existing `_onSettingsChanged`, so the guess updates.
- [ ] **Step 4: Run them and expect them to pass.** Callers of the removed API won't compile until Tasks 9–11. Do this task on the branch together with a temporary shim only if a commit has to build on its own; otherwise commit Tasks 6 and 9–11 as one series and run `flutter analyze` at the end of Task 11.
- [ ] **Step 5: Commit:** `feat(blend): role guess, draft open blend and residual fill-in (#112)`

### Task 7: Blend tab, the "Blended" action, the role chip and the open-blends list

**Files:**
- Create: `lib/ui/widgets/open_blends_section.dart`
- Modify: `lib/ui/screens/blend_screen.dart`, `lib/ui/screens/gas_screen.dart`, `lib/ui/app_shell.dart`
- Test: `test/ui/screens/blend_screen_test.dart`, `test/ui/widgets/open_blends_section_test.dart`, `test/ui/screens/gas_screen_test.dart`

**Interfaces:**
- Consumes: `OpenBlendsDaoLike` and `FakeOpenBlendsDao` (Task 4), `settleState` (Task 3), the BlendNotifier API (Task 6), `blendSettleMinutes` (Task 5).
- Produces:
  - `BlendScreen({required notifier, required settings, OpenBlendsDaoLike? openBlends})`
  - `OpenBlendsSection({required OpenBlendsDaoLike dao, required SettingsNotifier settings, DateTime Function() now = DateTime.now})`
  - `GasScreen(..., OpenBlendsDaoLike? openBlendsDao)`
  - `app_shell` builds `OpenBlendsDao(widget.powerSyncDb, SupabaseAuthSessionSource(...))` next to `_gasAnalysesDao`
- UI:
  - Under the plan band: the role chip `'${role.label} (${reason})'` with key `blend-role-chip`. Tapping it opens a menu of the four roles. An overridden role shows without the reason.
  - A `FilledButton.tonal` "Blended" with key `blend-save-open`. It adds `draftOpenBlend(blendedBy: settings.yourInitials, now: now())`, calls `openBlendSaved()` and shows the SnackBar "Tx18/45 added to open blends".
  - The list is titled "Not yet analysed (N)". Each row shows the mix name, the role label, the target pressure in bar and the time since blending (`'just now'` under a minute or below zero, `'12 min'`, `'1 h 05 min'`), with a settle dot coloured by `settleState`.
  - A trailing menu offers "Dismiss", and the SnackBar that follows has Undo. Undo is optional; skip it if it needs a DAO "undismiss".
  - A `Timer.periodic(1 min)` refreshes the colours; cancel it in `dispose`.
- The Gas tab bar's Blend label gets a count badge (key `gas-tab-blend-count`) from `watchOpen()`, hidden at 0.

- [ ] **Step 1: Write the failing widget tests** (`FakeOpenBlendsDao` and an injected `now`):
  - `Blended saves the draft and shows it in the list`
  - `role chip shows the guess with its reason and an override sticks for one blend`
  - `rows colour by settle time`: blends 10, 40 and 70 minutes old with settle 60 give a red, an orange and a green dot. Find by key `settle-dot-<id>` and check `decoration.color` against `AppColors`, or the theme colours `mix_match_indicator.dart` uses for red, orange and green.
  - `a blend from the future shows just now`
  - `Dismiss removes the row and the count`
  - `gas tab shows the open count`: 2 open gives the badge text `2`; 0 gives no badge
- [ ] **Step 2: Run them and see them fail.**
- [ ] **Step 3: Implement.** Reuse the colours of `mix_match_indicator.dart` for red, orange and green. Mind the Blend tab's height on a phone: the list goes below the existing content inside its scroll view.
- [ ] **Step 4: Run them, plus the existing `blend_screen_test.dart` and `gas_screen_test.dart`, and expect them to pass.**
- [ ] **Step 5: Commit:** `feat(blend): save as open blend, role chip and not-yet-analysed list (#112)`

### Task 8: The log, residual tag, warning line and no label for a residual

**Files:**
- Modify: `lib/ui/screens/gas_analysis_log_screen.dart`, `lib/ui/widgets/analysis_edit_sheet.dart`
- Test: `test/ui/screens/gas_analysis_log_screen_test.dart`, `test/ui/widgets/analysis_edit_sheet_test.dart`

**Interfaces:**
- Consumes: `GasAnalysis.isResidual` (Task 2), `mixWarning` (Task 3).
- Produces: none beyond the UI.
- Behaviour:
  - A residual entry shows a "Residual" tag (key `analysis-residual-<id>`).
  - An entry with a desired mix and a non-null `mixWarning` shows its text under the mix, red for loud and muted for mild. Use the analysis's own role and `labelUse14ForDeeperMixes`; the log screen takes `SettingsNotifier? settings` if it doesn't already reach it through `labelPrinting`.
  - A residual entry has no print action: the edit sheet's `canPrint` is false for it, and `_reprint` returns early with the SnackBar "A residual analysis has no label".

- [ ] **Step 1: Write the failing tests:**
  - `residual entries are tagged and cannot print`
  - `a rich deco entry shows the loud warning`: deco, 52.0 against 50/0, shows the Task 3 text
  - `a matching entry shows no warning`
- [ ] **Step 2: Run them and see them fail.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run them and expect them to pass.**
- [ ] **Step 5: Commit:** `feat(gas-log): residual tag, mix warning, no label for residuals (#112)`

### Task 9: The analyzer card's save path, which blend closes and the residual toggle

**Files:**
- Modify: `lib/ui/widgets/analysis_save_controller.dart`, `lib/ui/widgets/analysis_save_card.dart`, `lib/ui/widgets/analysis_fields.dart:~51`, `lib/ui/screens/analyzer_screen.dart`, `lib/analysis/standard_mix_pick.dart` (`resolveGasRole`)
- Create: `lib/ui/widgets/blend_close_row.dart`
- Test: `test/ui/widgets/analysis_save_controller_test.dart`, `test/ui/widgets/analysis_save_defaults_test.dart`, `test/ui/widgets/analysis_save_card_print_test.dart`, `test/ui/screens/analyzer_save_analysis_test.dart`, `test/analysis/standard_mix_pick_test.dart`

**Interfaces:**
- Consumes: `OpenBlendsDaoLike` (Task 4), `blendForAnalysis`, `nearestUnmatched`, `rankOpenBlends`, `mixWarning` and `BlendChoice` (Task 3), `BlendNotifier.applyResidualAnalysis` (Task 6).
- Produces:
  - `resolveGasRole({GasRole? tapped, GasRole? blendRole, String? cylinderRole, required double o2PercentForRule})`, in the order tapped, blend, cylinder, mix
  - `AnalysisSaveController({..., OpenBlendsDaoLike? openBlends, void Function(double o2, double he, double? bar)? onResidualSaved})`. It subscribes to `openBlends.watchOpen()` in the constructor and cancels in `dispose`.
  - Controller getters:
    - `List<OpenBlend> get openBlends`
    - `OpenBlend? get blendToClose`: `blendForAnalysis` for the current reading, the choice, the `chosenMix` (the diver's mix when `!mixIsAutomatic`) and `residual`
    - `RankedBlend? get nearestUnmatched`
    - `MixWarning? get warning`: against `blendToClose?.target ?? desiredMix`, with role `role`
    - `bool get residual`
    - `List<RankedBlend> get blendChoices`: everything, ranked
  - Controller actions: `void chooseBlend(BlendChoice c)` and `void setResidual(bool on)`. A manual save resets the choice to `AutoBlend()`; residual stays on until it's turned off.
  - `update(...)` loses `blendTarget` and `unusedBlendTarget`. `mixOptions` uses the open-blend targets, deduplicated, in place of `_blendTarget`. The automatic mix pick passes the auto-matched blend's target as `pickDesiredMix(blendTarget:)`.
  - Removes: `onBlendTargetUsed`, `_useBlendTarget`, `_targetOfferedTo`, `_releaseTarget`, `blendTarget` and `unusedBlendTarget`.
- Save:
  - The desired mix is `blendToClose?.target ?? <today's pick>`, and the role `_roleFor` with `blendRole: blendToClose?.role`.
  - `isResidual: residual`. With residual on, no desired mix and no print: "Save & print" is disabled.
  - Snapshot `blendToClose` before the first await, with the reading.
  - After the add: `if (blend != null) await openBlends.closeBlend(blend, savedId)`, inside a try. A failure is `debugPrint`ed; the analysis stays saved.
  - For a residual: `onResidualSaved?.call(gas.o2, gas.he, pressure.bar)`.
  - The "Saved …" SnackBar text gets `' · closes ${blend.target.name}'`, or `' · No open blend matches. Nearest: ${n.blend.target.name} (${n.grade.level.name})'`.
- `BlendCloseRow` (key `blend-close-row`) sits under the mix row:
  - "Closes Tx18/45 · blended 1 h 05 min ago", or "No open blend", or "No open blend matches. Nearest: Tx50 (red)"
  - a trailing "Change" that opens a bottom sheet listing `blendChoices` (match and orange first, as ranked) plus "None"
  - the `warning` text below it, loud in error colour
  - a "Residual analysis" switch (key `analysis-residual-toggle`)
  - hidden when there are no open blends and residual is off, except the switch

  Keep it to two lines in the card's height budget.
- `AnalyzerScreen` passes `openBlends` and `onResidualSaved: widget.blend?.applyResidualAnalysis` when it makes the controller. It gets `OpenBlendsDaoLike? openBlends` from `GasScreen`.

- [ ] **Step 1: Write the failing tests.** These **replace** the target cases at `analysis_save_controller_test.dart:~120-170` and `~270-350`, `analysis_save_defaults_test.dart:~600-645` and `analysis_save_card_print_test.dart` (every `blendTarget:` use becomes an open blend in `FakeOpenBlendsDao`).
  - `auto pick prefers an open blend over a standard mix` (was "prefers the Blend target")
  - `save closes the oldest matching open blend and takes its target and role`: two 18/45 blends, role diluent, reading 18.5/44.0; the saved analysis has desired 18/45 and role diluent, and the older blend is closed
  - `a tapped role still wins over the blend's role`
  - `a manual mix chip closes the oldest blend of that mix`
  - `choosing None closes nothing`
  - `picking a hard-mismatched blend closes it and shows the loud warning`: 50/0 deco, reading 55.0; `warning.level == loud`; after the save the blend is closed and the desired mix is 50/0
  - `an unmatched reading names the nearest blend in the SnackBar`
  - `residual: saved as residual, no desired mix, no print, closes nothing, fills the Blend tab`: check that `onResidualSaved` was called with (o2, he, 230)
  - `the chosen blend closed elsewhere while the unstable dialog is up still saves` (Review Focus 5): close it in the fake while the dialog is open, then confirm; the save succeeds and there's no exception
  - `resolveGasRole: blend role wins over cylinder and mix; tapped wins over blend` (in `standard_mix_pick_test.dart`)
- [ ] **Step 2: Run the listed test files and see them fail.**
- [ ] **Step 3: Implement.** Change `analysis_fields.dart`'s `', the Blend target'` to `', an open blend'`.
- [ ] **Step 4: Run them and expect them to pass.**
- [ ] **Step 5: Commit:** `feat(analyzer): analyses close open blends; residual toggle (#112)`

### Task 10: Log on OK (USB and bridge) closes at capture

**Files:**
- Modify: `lib/analyzer/bridge/record_to_analysis.dart`, `lib/analyzer/ok_record_processor.dart`, `lib/analyzer/usb_ok_logger.dart`, `lib/ui/notifiers/analyzer_session.dart`, `lib/ui/widgets/analysis_save_controller.dart` (`okSetup`, `_onOkResult`)
- Test: `test/analyzer/bridge/record_to_analysis_test.dart`, `test/analyzer/usb_ok_logger_test.dart`, `test/analyzer/bridge/bridge_ok_handler_test.dart`, `test/ui/notifiers/analyzer_session_test.dart`, `test/ui/screens/analyzer_log_on_ok_test.dart`

**Interfaces:**
- Consumes: `blendForAnalysis` and `BlendChoice` (Task 3), `OpenBlendsDaoLike.closeBlend` (Task 4).
- Produces:
  - `LogOnOkSetup`:
    - `blendTarget` is replaced by `List<OpenBlend> openBlends` (default `const []`) and `BlendChoice blendChoice` (default `AutoBlend()`)
    - `gasRole` splits into `GasRole? tappedRole` and `GasRole? cylinderRole`
    - new `bool residual` (default false)
  - `SaveRecord` gains `OpenBlend? blendToClose`.
  - `recordToAnalysis`, step 6, for a live record:
    - `blend = blendForAnalysis(o2, he, choice: setup.blendChoice, chosenMix: setup.desiredMix, residual: setup.residual, open: setup.openBlends)`
    - `desiredMix = setup.residual ? null : (blend?.target ?? <today's logic>)`
    - `gasRole = tappedRole ?? blend?.role ?? cylinderRole ?? gasRoleForMix(...)`
    - `isResidual: setup.residual`
    - `printLabel` is false when residual

    A late (non-live) record gets no blend.
  - `OkRecordProcessor({..., Future<bool> Function(OpenBlend b, String analysisId)? closeBlend})`. It calls `closeBlend` exactly when it returns `complete: true` with an `outcome.blendToClose`: after `_markComplete` on the print path, or right after the save when `!needsSignoff` and there's no print. It's caught and reported through `onError`, and never changes the result.
  - `buildOkLogger(..., OpenBlendsDaoLike? openBlends)` wires `closeBlend: openBlends?.closeBlend`. Do the same where `analyzer_session.dart:~446` constructs the bridge's `OkRecordProcessor`. `AnalyzerSession` takes `OpenBlendsDaoLike? openBlends`, and `app_shell` passes it.
  - Removes: `AnalyzerSession._watchOkResults`, `_useTargetIfSaved`, `_okResultSubs` (if nothing else uses it), and the `blend` dependency of the session if it's then unused.
  - `AnalysisSaveController.okSetup()` passes `openBlends`, the current choice and `residual`. `_onOkResult` for a press whose setup was residual calls `onResidualSaved` with the result's reading. Read the stored entry by `analysisId`, as `_readStored` does.

- [ ] **Step 1: Write the failing tests.** These **replace** the target cases at `analyzer_session_test.dart:~340-450` and `analyzer_log_on_ok_test.dart:~910-1015`.
  - `record_to_analysis`:
    - `a live record takes the matching open blend's target and role`
    - `the oldest of equal open blends is the one to close`
    - `a late record gets no blend`
    - `residual: no desired mix, no print, no blend, is_residual set`
    - `tapped role beats blend role, blend role beats cylinder role`
  - `ok_record_processor` (through `usb_ok_logger_test.dart` or a new `test/analyzer/ok_record_processor_test.dart`):
    - `a complete press closes its blend`
    - `a press that needs sign-off does not close`
    - `a print that fails does not close`
    - `a closeBlend that throws is reported and the result stays complete`
  - `two quick presses, one open blend: one close` (Review Focus 1): this uses a `FakeOpenBlendsDao` with the real semantics; the second press's `closeBlend` returns false, and both analyses are saved
  - `analyzer_log_on_ok_test`: `a residual press fills the Blend tab and prints nothing`
- [ ] **Step 2: Run the listed files and see them fail.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run them and expect them to pass.**
- [ ] **Step 5: Commit:** `feat(log-on-ok): OK presses close open blends at capture (#112)`

### Task 11: Sign-off closes

**Files:**
- Create: `lib/analyzer/blend_closer.dart`
- Modify: `lib/ui/screens/gas_analysis_log_screen.dart` (`_useBlendTarget` → `_closeBlendOnSignOff`), `lib/ui/widgets/analysis_save_controller.dart` (`editResult`)
- Test: `test/analyzer/blend_closer_test.dart`, `test/ui/screens/gas_analysis_log_screen_test.dart`

**Interfaces:**
- Consumes: `OpenBlendsDaoLike` (Task 4), `GasAnalysesDaoLike.update`, `blendForAnalysis` (Task 3).
- Produces: `Future<void> closeBlendOnSignOff({required GasAnalysis signedOff, required OpenBlendsDaoLike openBlends, required GasAnalysesDaoLike analyses})`:
  - It does nothing when the entry still needs sign-off, is residual or was deleted (null is the caller's).
  - With `signedOff.desiredMix != null`, it calls `openBlends.closeOldestOpen(desiredMix, id)`.
  - Without one, it ranks the reading against `listOpen()`. On a match or orange blend, it calls `closeBlend` and then `analyses.update(id, GasAnalysisEdit(desiredMix: blend.target, gasRole: blend.role, …the rest as stored…))`.
  - Failures are caught and `debugPrint`ed.
- `GasAnalysisLogScreen` takes `OpenBlendsDaoLike? openBlends` (from `GasScreen`) in place of using `blend` for the target. `AnalysisSaveController.editResult` calls the same function after a sign-off.

- [ ] **Step 1: Write the failing tests:**
  - `sign-off of an entry with a desired mix closes the oldest blend of that mix`
  - `sign-off without a desired mix matches by reading and gives the entry the blend's target and role`
  - `sign-off of a residual closes nothing`
  - `an entry still needing sign-off closes nothing`
  - **Replace** the `unusedRecentTarget` cases at `gas_analysis_log_screen_test.dart:~1510-1700` with: `signing off on the Log tab closes the open blend`, and `signing off an entry of another mix leaves the blend open`
- [ ] **Step 2: Run them and see them fail.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run them and the whole suite (`flutter analyze` and `flutter test`). Expect both clean, with no remaining reference to `recentTarget`, `unusedRecentTarget` or `markRecentTargetUsed` (`grep -rn` gives nothing).**
- [ ] **Step 5: Commit:** `feat(gas-log): sign-off closes open blends (#112)`

### Task 12: Deploy notes and PR

**Files:**
- Modify: `supabase/README.md` (if it lists migrations), `infra/README.md` (only if it lists tables)

- [ ] **Step 1:** Run `flutter analyze`, `flutter test`, `supabase/lint_migrations.sh` and (from `packages/subsurface_core`) `dart test`. All green.
- [ ] **Step 2:** Push and open a PR titled `feat(gas): open blends closed by an analysis (#112)`. The body has:
  - a summary
  - the spec link
  - **Deploy before shipping:** run migration 0025 in the SQL Editor, then deploy `infra/powersync-sync-rules.yaml`
  - **Older builds:** they read backgas and deco as bailout, ignore `is_residual` and keep their single-target behaviour
  - `Closes #112`
- [ ] **Step 3:** Don't merge. Egbert tests a macOS build first (blend two cylinders, analyse one, OK-press one, sign off one, a residual), then deploys and merges.
