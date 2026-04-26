# Equipment View

## Context

The Equipment tab is currently a `PlaceholderScreen`. This spec covers the first real Equipment view, which surfaces the dive computers, O2 cells, scrubber sessions, and cylinders that ground every dive. The headline payoff is the **per-cell longitudinal mV trend** — the project's most defensible analytical feature, called out in CLAUDE.md as "the single most defensible feature." This is where it lives.

## Scope

**In scope (this spec):**

1. **Dive Computers** — read-mostly. Rows are auto-populated when the import flow connects to a device. User can rename via a `nickname` field. Detail screen also owns the **pressure-channel-to-cylinder mapping** that lets us label "Diluent (bar)" instead of "Tank 0" everywhere downstream.
2. **O2 Cells** — full CRUD. Detail screen shows surface-mV per dive over the cell's lifetime.
3. **Scrubber Sessions** — auto-detected from imported dive data when a scrubber-reset event is present in the parser output, with a manual "+ New pack" fallback that always works.
4. **Cylinders** — full CRUD against a new `Cylinders` table. Cylinders carry a **role** (oxygen / diluent / bailout / offboard) reflecting the CCR-cylinder reality: every CCR diver runs at least three (O2 + diluent + bailout), so the empty state guides the user into that shape.

**Unblocked by this spec but not implemented here:**

- Pressure traces on the dive-detail profile chart, labelled by cylinder role/name. The data join (channel → cylinder → role) becomes possible once `PressureMappings` lands; the rendering work itself stays in the dive-detail spec.

**Deferred (separate specs):**

- Multi-rebreather `diveComputerId` FK on `OxygenCells` (assumes single-rig user for now).
- Cylinder ↔ dive linkage at the per-dive level — i.e. "what was breathed when" — belongs to the upcoming dive-annotations spec. Note this is distinct from `PressureMappings` (which is a static per-DC channel assignment, in scope here).
- Setpoint-mV and linearity-ratio traces on the cell detail screen (Phase 2 cell health).
- Parser-side support for the scrubber-reset event and per-sample scrubber-on time channel — design is forward-compatible but the parser changes are their own work item.

## Layout

Index → list → detail.

- **Equipment landing**: four cards (Computers · Cells · Scrubbers · Cylinders), each with a count badge. Tap → category list.
- **Per-category list**: vertical list of items in that category. Default ordering is active-first; Cylinders departs from this and groups by role (see that section). FAB for "+ Add" where applicable.
- **Per-item detail**: pushed onto the navigation stack (not a modal). Edit forms are inline on the detail screen (the cell detail wants real estate for the chart, and pushing the edit form to its own screen would fragment the flow).

This pattern matches the existing app idiom — bottom nav drills you into a tab, sub-navigation drills further.

## Dive Computers

**List screen**
- Each row: nickname (or model + last-4-of-serial as fallback), firmware, last-imported-at relative time.
- Sorted by `lastImportedAt` desc. No FAB — these are auto-created.

**Detail screen**
- Header: model name, full serial, firmware (read-only).
- Editable: `nickname`.
- **Pressure mapping** section: one row per pressure channel logged by the device (channel count is derived from inspecting recent imports — the parser must surface a per-channel pressure series; flagged for verification during implementation). Each row has a dropdown picking from the user's `Cylinders` plus an "unmapped" sentinel. Saving writes a `PressureMappings` row keyed on `(diveComputerId, channelIndex)`. If the device hasn't logged any pressure channels yet, the section is collapsed with a note ("No pressure channels seen on imports yet").
- "Recent imports" mini-list: last 10 dives imported from this device (date, dive number, runtime).
- No delete in MVP — these are records of devices the user has used.

**Auto-population**
- `ImportNotifier.selectRealDevice` (after `readDeviceInfo`) calls a new `EquipmentDao.upsertDiveComputer` keyed on serial. If the row exists, only `lastImportedAt` is bumped; the user's nickname is preserved.

## O2 Cells

**Schema delta**
- Add `TextColumn label nullable` to `OxygenCells` (e.g., "Analytical R-22D #1234"). Migration is additive.

**List screen**
- Active first (no `retiredDate`), retired below sorted by `retiredDate` desc.
- Row: `Slot N · installed YYYY-MM-DD · age in months · dive count`. Retired badge if applicable.
- FAB: "+ Add cell" — pushes a blank detail screen in edit mode.

**Detail screen**
- Header card: slot, label, installedDate, retiredDate (if any), dive count, lifetime hours of use.
- Chart: per-dive **surface mV** over time. X = dive start date, Y = mV. Single line connecting points. Tap a point → tooltip (date, mV, dive number) + tap to navigate to that dive's detail screen.
- Notes (editable, multi-line).
- Actions:
  - **Edit** — slot, label, installedDate, notes.
  - **Retire** — sets `retiredDate` to today; cell stays in list as retired.
  - **Delete** — only allowed if the cell has zero attributable dives.

**Cell↔dive linkage**
Implicit via date-range overlap: a dive belongs to a cell iff `dive.startTime ∈ [cell.installedDate, cell.retiredDate ?? ∞)`. No FK in MVP. Acknowledged limitation: assumes the user has a single rebreather. A `diveComputerId` FK is the obvious additive change when a multi-rig user appears.

**Surface-mV aggregation**
For each dive `D` in the cell's window:

1. Resolve the cell's slot index (0/1/2 → `cellMv0`/`cellMv1`/`cellMv2` in the parsed sample columns).
2. Iterate samples in the dive where `depthM < 1.0` AND the cell wasn't voted out.
3. Mean of those `cellMv[slot]` values is the dive's surface-mV data point.
4. If no samples qualify (e.g., short dive without surface samples), the dive is omitted from the chart.

**Voted-out heuristic (MVP)**
Until the parser surfaces a real voted-out flag, the chart filters samples where `cellMv[slot] < 5 mV`. This catches disconnected/voted-out cells (a healthy cell at 0.21 ATA reads ~9–13 mV). Documented as a heuristic to be replaced when parser support lands.

## Scrubber Sessions

**Schema** (no changes — existing `ScrubberSessions` table is sufficient; `totalMinutes` is treated as a cached/derived value, not user-entered).

**List screen**
- Active session pinned at top (no `endDate`).
- Closed sessions below by `startedDate` desc.
- Row: `Pack started YYYY-MM-DD · X hours Y minutes used` + media type if set.
- FAB: "+ New pack" (manual creation).

**Detail screen**
- Header: startedDate, endDate (auto-set when next session opens, editable), media type, accumulated minutes, dive count in session.
- Notes.
- Actions: **Edit** (start, media, notes), **Close** (sets endDate to now), **Delete** (with confirmation).

**Auto-detection (forward-compatible wiring)**
- The import flow, after each dive is parsed, calls `EquipmentDao.applyScrubberEvents(parsedDive)`.
- If `parsedDive.scrubberResetAt != null`: close the open session (set `endDate = resetAt`) and create a new one (`startedDate = resetAt`).
- Until the parser populates `scrubberResetAt`, this method is a no-op — manual mode handles everything.

**Accumulated minutes**
Sum of scrubber-on time from dives whose `startTime ∈ [session.startedDate, session.endDate ?? ∞)`. Source preference:

1. Per-sample scrubber-on channel from the parsed sample blob, if present.
2. Otherwise, fall back to the dive's runtime (over-estimates by surface time, acceptable for MVP).

The DAO inspects available columns and chooses; the UI doesn't care which source ran.

## Cylinders (new schema)

```dart
class Cylinders extends Table {
  TextColumn get id => text()();
  TextColumn get label => text()();          // "AL40 stage", "12L steel"
  TextColumn get role => text()();           // 'oxygen', 'diluent', 'bailout', 'offboard'
  IntColumn get bailoutOrder => integer().nullable()(); // 1, 2, ... for role == 'bailout' only
  RealColumn get volumeLiters => real()();
  IntColumn get workingPressureBar => integer()();
  TextColumn get gasMix => text().nullable()(); // "21/35", "100", null = "current fill unknown"
  TextColumn get notes => text().nullable()();

  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  IntColumn get syncStatus => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}
```

The `role` column is enforced as one of the four enum values via Dart-side validation (no DB-level CHECK constraint, matching how the rest of the schema handles enums). `bailoutOrder` is meaningful only when `role == 'bailout'`; the DAO clears it on role changes.

**List screen**
- Grouped by role: **Oxygen**, **Diluent**, **Bailout** (sorted by `bailoutOrder` asc), **Offboard**. Empty role groups are hidden.
- Within a row: label, gas mix, "V L @ P bar". Bailout rows show "#1", "#2", ... prefix from `bailoutOrder`.
- FAB: "+ Add cylinder" — pushes a blank detail screen with role picker focused.
- **Empty-state CTA**: when the table has no non-deleted rows, the list shows a "Set up standard CCR cylinders" button alongside the FAB. Tapping it inserts three rows — `oxygen` (label "O2"), `diluent` (label "Diluent"), `bailout` with `bailoutOrder = 1` (label "Bailout") — each with placeholder volumes/pressures the user fills in. As soon as at least one row exists, the CTA disappears naturally; no dismiss state is persisted.

**Detail screen**
- All fields editable. Soft-delete via `deletedAt`.
- Role picker is a segmented control / dropdown of the four roles. Selecting "bailout" reveals the `bailoutOrder` field (defaulted to one past the highest existing bailout order). Switching away from "bailout" clears `bailoutOrder`.
- No cylinder ↔ dive linkage in this spec.

## Pressure Mappings (new schema)

```dart
class PressureMappings extends Table {
  TextColumn get diveComputerId => text()();
  IntColumn get channelIndex => integer()();   // 0, 1, 2, ... as logged by the device
  TextColumn get cylinderId => text().nullable()(); // FK to Cylinders.id; null = "unmapped"

  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  IntColumn get syncStatus => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {diveComputerId, channelIndex};
}
```

The mapping is static per dive computer — once the user assigns "channel 0 = Diluent" on their X-CCR Petrel, that holds across all imports from that device. Edited from the DiveComputer detail screen. Persisting the mapping in plain SQL (rather than as JSON on the `DiveComputers` row) makes joins from imported pressure samples to cylinder identity straightforward and keeps the sync-metadata story uniform with every other equipment table.

## Data Model Changes

- **Add `label` to `OxygenCells`** (nullable text, additive migration).
- **New `Cylinders` table** with `role` and nullable `bailoutOrder` (above).
- **New `PressureMappings` table** (above).
- **New `EquipmentDao`** covering all equipment categories plus the pressure-mapping methods. Single DAO, logical sections per type, plus the aggregation helpers below. One DAO keeps the surface area discoverable; splitting would be premature.

### EquipmentDao surface (sketch, not the full API)

```
upsertDiveComputer({serial, model, firmware, lastImportedAt})
listDiveComputers()
recentImportsForComputer(serial, limit)
setComputerNickname(id, nickname)

listCells()
getCell(id)
addCell(...)
updateCell(...)
retireCell(id, retiredAt)
deleteCellIfUnused(id)
surfaceMvSeriesForCell(id) -> List<({DateTime date, double mv, String diveId})>

listScrubberSessions()
getScrubberSession(id)
addScrubberSession(...)
closeScrubberSession(id, endedAt)
deleteScrubberSession(id)
applyScrubberEvents(parsedDive) // import-flow hook
accumulatedMinutesForSession(id) -> int

listCylinders()                  // grouped by role for the list screen
addCylinder(...)                 // takes role + (bailoutOrder if role == bailout)
updateCylinder(...)              // clears bailoutOrder on role change away from bailout
softDeleteCylinder(id)
seedStandardCcrCylinders()       // empty-state CTA: O2 + Diluent + Bailout #1

listPressureMappings(diveComputerId)
setPressureMapping(diveComputerId, channelIndex, cylinderId | null)
pressureChannelsSeenForComputer(diveComputerId) -> List<int> // from imports
```

### Equipment notifiers

One `ChangeNotifier` per category screen (`DiveComputersNotifier`, `CellsNotifier`, `ScrubberSessionsNotifier`, `CylindersNotifier`). Same shape as the existing `DiveListNotifier`. Detail screens take a single-item state object; edits hit the DAO and refresh.

## Tests

- DAO unit tests for CRUD against an in-memory Drift database (one suite per category, including `PressureMappings`).
- `surfaceMvSeriesForCell` aggregation tests against synthetic samples covering: empty dive, all-below-threshold (cell voted out), partial qualifying samples, multiple dives within the cell window, dive outside the window.
- `applyScrubberEvents` test with a synthetic `ParsedDive` carrying a reset timestamp; verify the open session closes and a new one is created.
- `seedStandardCcrCylinders` test: from an empty table, seeds three rows with the correct roles and a bailout order of 1.
- `updateCylinder` test: switching a bailout cylinder to another role nulls `bailoutOrder`.
- `setPressureMapping` test: round-trip + override, including the unmapped (null) case.
- Notifier state-machine tests for list → detail → edit → save round-trips.
- Widget smoke tests for each list and detail screen (renders without throwing, basic interactions). Cylinders list smoke test covers the empty-state CTA.

## Open Items / Future Work

- **Verify per-channel pressure samples in the parser** — the DiveComputer pressure-mapping section assumes the parser exposes a per-channel pressure series in the columnar sample blob. Sanity-check during implementation; add parser support if missing.
- **Voted-out flag in `ParsedDive`** — replace the `< 5 mV` heuristic when the parser surfaces a real flag.
- **Scrubber-reset event in `ParsedDive`** — wires up the auto-detection path that's already designed for it.
- **Per-sample scrubber-on time channel** — replaces the dive-runtime fallback for accumulated session minutes.
- **Multi-rebreather `diveComputerId` FK on `OxygenCells`** — additive change when needed.
- **Cylinder ↔ dive linkage** at the per-dive level (what was breathed when) — lands with the dive-annotations spec.
- **Setpoint-mV / linearity-ratio traces on cell detail** — Phase 2 cell health.
- **Pressure traces on the profile chart**, labelled by mapped cylinder role — lands with the dive-detail spec, unblocked by `PressureMappings` from this spec.
