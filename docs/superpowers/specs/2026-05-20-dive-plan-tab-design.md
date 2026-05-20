# Dive Plan tab — design

**Status:** approved, ready for implementation plan
**Author:** brainstorm 2026-05-20
**Scope:** CC + Bailout planner. OC mode designed-in but unimplemented (separate spec).
**Related work:** reuses `lib/analysis/deco/` (ZHL-16C + VPM-B + planDeco), `lib/analysis/bailout/` (planBailout, BailoutSection widget), `lib/analysis/planner/` (new).

---

## 1. Goal

A multilevel dive planner accessible as a new top-level destination. Diver enters a series of (depth, time, gas, setpoint) segments plus bailout bottles; the planner outputs a dive plan (descent + level + deco) and a bailout plan computed from end-of-bottom tissue state. Plans are editable, draft-auto-saved, and explicitly save-as'd to a named library that syncs across devices.

Replaces the "open MultiDeco, type the dive in, run it, transcribe the result" workflow with an integrated tool that uses the same deco engine, bailout planner, and rendering components the app already uses for recorded dives.

## 2. Architecture overview

**New top-level destination.** Add "Plan" to `lib/ui/app_shell.dart`'s BottomNavigationBar as a 5th entry: Dives, **Plan**, Import, Equipment, Settings.

**Two-tier persistence.** The active edit lives in a single special row in the `dive_plans` Drift table identified by `name IS NULL` (the draft). Auto-saves on every edit. "Save as…" copies the draft into a named saved plan. "New plan" clears the draft. Saved plans sync via PowerSync, soft-delete via `deleted_at`, sync-metadata stamped per the project's "all user data syncs across signed-in devices" principle (CLAUDE.md).

**Compute pipeline.** segments + settings → existing deco engine (ZHL-16C or VPM-B by toggle) → schedule + tissue state at end-of-bottom → existing `planBailout()` → bailout plan. Output rendered via a shared `_StopTable` widget extracted from `bailout_section.dart` plus the existing `BailoutSection` inline.

**Scope.** CC + Bailout end-to-end in this spec. OC support is mode-flagged in the data model; UI hard-codes `mode = 'cc'`; OC ships in a follow-up spec.

## 3. Data model

### Drift table `dive_plans`

| column          | type   | nullable | notes                                                  |
| --------------- | ------ | -------- | ------------------------------------------------------ |
| `id`            | TEXT   | PK       | UUID                                                   |
| `name`          | TEXT   | yes      | null = draft, non-null = saved                         |
| `mode`          | TEXT   | no       | `'cc'` or `'oc'` (only `'cc'` exercised by v1 UI)      |
| `gases_json`    | TEXT   | no       | JSON-encoded `List<DivePlanGas>`                       |
| `segments_json` | TEXT   | no       | JSON-encoded `List<DivePlanSegment>`                   |
| `bailout_json`  | TEXT   | no       | JSON-encoded `List<DivePlanBailoutBottle>`             |
| `settings_json` | TEXT   | yes      | per-plan settings overrides (null fields use globals)  |
| `notes`         | TEXT   | yes      | free-text notes                                        |
| `created_at`    | INT    | no       | unix epoch millis                                      |
| `updated_at`    | INT    | no       | unix epoch millis                                      |
| `deleted_at`    | INT    | yes      | soft delete sentinel                                   |
| `owner_id`      | TEXT   | yes      | stamped at insert from Supabase session                |
| `version`       | INT    | no       | sync versioning, monotonic                             |
| `sync_status`   | TEXT   | no       | per-project convention                                 |

**Indexes:**
- Partial unique index on `(owner_id) WHERE name IS NULL AND deleted_at IS NULL` — at most one draft per user.
- Composite index on `(owner_id, deleted_at, updated_at DESC)` — feeds the saved-plans browser.

JSON-encoded body is intentional: gases / segments / bottles are always loaded as a unit and rarely queried by sub-field. Three child tables would add migration weight, JOINs, and sync rules for negligible benefit.

### Dart models (`lib/data/models/dive_plan.dart`)

```dart
class DivePlanGas {
  int oxygenPercent;
  int heliumPercent;
  bool isDiluent;          // CC: diluent vs deco; OC: back gas vs deco
}

class DivePlanSegment {
  double depthMeters;
  int durationMinutes;     // 0 = instant change (setpoint or gas switch)
  int gasMixIndex;         // index into plan.gases
  double? setpoint;        // CC only; null = phase default
}

class DivePlanBailoutBottle {
  int gasMixIndex;         // can match a dive gas (e.g. 21/35 dil + 21/35 stage)
  double waterCapacityL;
  int fillPressureBar;
}

class DivePlanSettings {
  int? gfLow, gfHigh;
  int? vpmbConservatism;
  bool? useVpmb;                 // null/false = ZHL-16C
  int? ascentRateMpm;            // null = reuse bailoutAscentRateSlow
  int? descentRateMpm;
  double? bottomSetpoint, ascentSetpoint, decoSetpoint;
  double? lastStopDepthMeters;   // 3.0 or 6.0 typically
}
```

### Global defaults

Added to `SettingsNotifier`: `plannerGfLow`, `plannerGfHigh`, `plannerVpmbConservatism`, `plannerUseVpmb`, `plannerBottomSetpoint`, `plannerAscentSetpoint`, `plannerDecoSetpoint`, `plannerLastStopDepthMeters`. Ascent/descent rates reuse the existing `bailoutAscentRate*` settings — same physics whether you ascend on the loop or off it.

## 4. Compute pipeline

Five phases under `lib/analysis/planner/`. Each phase is a pure function so the deco/bailout modules stay decoupled.

**Phase 1 — Profile materialisation.** New `PlanSimulator` walks segments in order. Between two segments at different depths it inserts a transit at the configured descent / ascent rate. For each minute of dive time it advances the existing tissue model (`lib/analysis/deco/tissue_model.dart`) by one Schreiner step, using either the inhaled OC gas (mode='oc') or loop pp(N₂)/pp(He) derived from setpoint + diluent (mode='cc'). Time-0 segments update active gas / setpoint without advancing time.

**Phase 2 — Trigger state.** Simulator returns tissue N₂/He loads at end-of-bottom (last sample of the deepest segment with time > 0), plus running totals for CNS %, OTU, and max gas density. These are the dive's summary stats and the inputs for the deco + bailout calls.

**Phase 3 — Deco schedule.** Hand trigger tissues + dive gas list + resolved settings (GF or VPM-B level per `useVpmb`) to the existing `planDeco()`. Returns the ascent ladder.

**Phase 4 — Bailout plan.** Hand trigger tissues + bailout bottles + tank catalogue to the existing `planBailout()` in Scenario A (user-defined tanks). Returns a `BailoutResult` identical to what the dive-detail view renders today.

**Phase 5 — Assembly.** Pack into a `PlanResult`:

```dart
class PlanResult {
  List<AscentStop> diveAscent;        // from planDeco
  BailoutResult bailout;
  double cnsPercent, otuTotal, maxDensityGramsPerLitre;
  Duration totalRuntime;
}
```

Pipeline runs in <50 ms on a typical plan — fast enough to re-execute on every form edit without debouncing computation. (Auto-save IS debounced; compute is not.)

**Files added under `lib/analysis/planner/`:**
- `plan_simulator.dart` — segments → trigger tissues + summary stats
- `plan_runner.dart` — `runPlan(plan, settings) → PlanResult` orchestrator
- `plan_result.dart` — output types

**Re-uses (no new analysis code):** `tissue_model.dart`, `zhl16c.dart`, `vpmb.dart`, `deco_planner.dart`, `bailout_planner.dart`.

## 5. UI structure

Single scrolling page, dark theme matching the rest of the app.

```
[AppBar: "Plan"     ⋯ Saved plans   + New plan]
─────────────────────────────────────────────
Plan name [Cave dive 60m________]  [Save as]
─────────────────────────────────────────────
SETTINGS    (collapsible, shows "30/85 · 1.3/0.7/1.4 · 6 m"  ▼)
─────────────────────────────────────────────
GASES        21/35 dil · 18/45 dil · 50/0 · 100/0    [+ add]
─────────────────────────────────────────────
SEGMENTS
  Depth   Time   Gas       SP     ⨯
   50 m   20     21/35     1.3    ⨯
   50 m    0     50/0       —     ⨯       (time-0 = switch)
   30 m   10     18/45     1.0    ⨯
  [+ add segment]
─────────────────────────────────────────────
BAILOUT BOTTLES   (reuses dive_bailout_carry pattern)
  21/35 · AL40 · 200 bar         ⨯
  50/0  · AL40 · 232 bar         ⨯
  [+ add bottle]
═════════════════════════════════════════════
OUTPUT — DIVE PLAN
  DEPTH  T  RT  GAS    PPO₂  ρ   VOL
  ...stop ladder...
  CNS 65 %  · OTU 200  · ρ_max 5.2 g/L  · TTS 45 min
─────────────────────────────────────────────
OUTPUT — BAILOUT   (existing BailoutSection widget)
```

**Editing pattern.** Segments are a compact list with inline-editable cells: numeric inputs for depth / time, dropdown for gas (populated from `plan.gases`), dropdown for setpoint (0.5 / 0.7 / 1.0 / 1.3 / 1.4 plus custom). Same row patterns for gases and bailout bottles. Reorderable via a drag handle.

**Settings panel.** Collapsed by default, shows resolved values as a one-line summary. Expanded reveals each setting with a "use default" / "override" toggle + input. Mirrors the per-dive GF override on the Equipment tab.

**Saved plans browser.** Modal bottom sheet listing saved plans by `updated_at DESC` with name + last-modified. Tap to load (copies into the draft, replacing current draft contents — confirmation if draft is non-empty unnamed). Swipe to soft-delete.

**State management.** `DivePlanNotifier` holds the editable `DivePlan`, resolved settings, and most recent `PlanResult`. Edits debounce-write the draft row (250 ms) and trigger a synchronous re-compute. Exposes `result: PlanResult?` to output widgets.

**Reused widgets.** The stop-ladder table (`_StopTable` currently inside `bailout_section.dart`) gets extracted to a shared file `lib/ui/widgets/stop_ladder_table.dart` and used by both the dive-plan output and the bailout output. The existing `BailoutSection` renders the bailout output verbatim — same Solo / Team tabs, same ICD warnings, same row colouring.

**OC mode placeholder.** Data model carries `mode = 'cc' | 'oc'`. UI hard-codes `mode = 'cc'` and hides OC-only fields. Mode toggle ships with the OC follow-up spec.

## 6. Sync and storage

**Drift migration.** New schema version adding `dive_plans` with the columns above plus the two indexes. No data backfill — table starts empty.

**PowerSync.** Append to `infra/powersync-sync-rules.yaml`:

```yaml
- name: dive_plans
  parameters: SELECT id FROM auth.users WHERE id = request.user_id()
  data:
    - SELECT * FROM dive_plans WHERE owner_id = bucket.id AND deleted_at IS NULL
```

Plus the matching Supabase RLS policy (`owner_id = auth.uid()` for SELECT/INSERT/UPDATE/DELETE), per the same pattern every other user-owned table uses.

**Owner-id stamping.** DAO inserts stamp `owner_id` from the current Supabase session, same pattern as `dive_attachments_dao`. `OwnerIdBackfiller` extended to cover `dive_plans` so an offline-create-then-sign-in flow doesn't strand the draft (per the sync recovery procedure in CLAUDE.md).

## 7. Testing

- `plan_simulator_test.dart` — known segments → expected tissue state; compared against a reference replay run on synthesised samples.
- `plan_runner_test.dart` — end-to-end: a 40 m / 20 min CC dive on 21/35 produces the expected stop ladder + bailout result.
- `dive_plans_dao_test.dart` — CRUD, soft-delete, draft uniqueness, owner-id stamping.
- `dive_plan_notifier_test.dart` — debounced auto-save fires once per edit burst; Save-as creates a new row and clears the draft.
- Widget tests for segment editing + load / save flow.

## 8. Out of scope

- **OC mode** — separate spec.
- **Plan ↔ recorded-dive linking** ("compare planned vs. actual") — future.
- **Sharing plans between users** — future.
- **Plan templates / cloning a saved plan** — v1 doesn't ship a UI but the DAO already supports copy-on-save; cloning is a trivial later add.
- **Importing plans from MultiDeco / Subsurface XML** — future.
- **Plan output as MultiDeco-style monospace text dump** — could ship as a "copy to clipboard" affordance later if briefing-sheet use case emerges.

## 9. Open risks

**VPM-B in a forward-simulation context.** The existing `vpmb.dart` is wired into the replay engine for recorded dives. We need to confirm it works for forward-simulation (descent + bottom from surface tissues, not replay from samples). Likely needs a small adapter; flagged for the writing-plans phase to size accurately.

**Setpoint phase-switching.** The planner needs to know which segments are "bottom", "ascent transit", and "deco stop" to apply the right phase setpoint as a default. Proposed rule: anything below the first deco stop = bottom setpoint; ascent itself = ascent setpoint; at-or-shallower than 6 m on the deco ladder = deco setpoint. Lives in `plan_simulator`; needs a couple of dedicated tests.

**Inline-editable segment cells on mobile.** Dropdowns + numeric keyboards inside a scrollable list need keyboard-management care. Flutter pattern is mature but worth time-boxing in the plan to avoid a rabbit hole.
