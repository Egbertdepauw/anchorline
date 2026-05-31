# Merge Dives — Design

**Date:** 2026-05-31
**Status:** Approved design, pending implementation plan
**Author:** Egbert (with Claude)

## Goal

Let the user select 2+ dives in the dive list and merge them into a single
displayed dive. The time gap between consecutive dives is shown as a **surface
interval**. Merging is a **stored grouping** (a synced relationship), not a
rewrite of the dive records — the underlying dives stay immutable and the merge
is fully reversible.

This honors two load-bearing CLAUDE.md principles:

- **Principle 1** — the dive computer is the source of truth; imported data is
  immutable. We never concatenate or rewrite stored samples.
- **Principle 5** — single-segment dives in the data model, merge in the UI.
  We promote "merge" from a transient view concern to a *stored* relationship
  (the Phase-2 evolution the principle anticipated), but the combining still
  happens at view time.

## Prior art: how Subsurface does it

Confirmed against Subsurface's `core/divelist.cpp` / `core/dive.cpp`
(`subsurface/subsurface` on GitHub):

- **Manual merge imposes no surface-interval cap.** `dive_table::merge_dives()`
  folds whatever the user selected, pairwise, trusting the explicit selection.
  Their only time windows (12 h / 48 h) are in auto-trip/CNS look-back, never to
  gate a manual merge.
- **Offset model:** `merge_two_dives(a, b, offset)` places `b` at
  `offset = b.when - a.when` seconds after `a` and builds one combined sample
  stream. This validates our synthetic-`SampleSet` approach.
- **Surface interval = `next.start − prev.end`** (`get_surface_interval` returns
  `when − prev_end`, negative when overlapping). Our builder computes the gap the
  same way.
- **CNS decays (90-min half-time) and tissues off-gas on air at surface pressure**
  across the surface interval in their deco walk. This is the *correct* version
  of the v1 simplification we accept below — a documented future refinement, not
  a v1 requirement.

We deliberately **diverge** from Subsurface on one point: the user has chosen a
**1 h hard cap** on the gap (see Guardrails), where Subsurface has none.

## Approach

### Chosen: synthetic combined `SampleSet` at view time

The profile chart and the entire analysis layer (`computeDensitySeries`,
`computeEndSeries`, deco replay) are **sample-index-driven with a uniform
`sampleIntervalMs`** — there are no absolute timestamps anywhere in the chart.
Therefore, when a merged group is opened, a pure builder produces:

1. A synthetic `SampleSet` — each member dive's columns concatenated, with a
   flat **surface-interval block** inserted between consecutive dives.
2. A "virtual" merged `Dive` — merged gas-mix list (with remapped
   `gasMixIndex`), max depth across segments, summed in-water duration, etc.

These feed the **existing** `ProfileChart` and analysis functions with **zero
changes** to those consumers. Surface blocks sit at depth 0 (top of chart);
density/END already skip surface via the `≥ 1.0 m` underwater filter.

### Rejected: a multi-segment-aware chart

Rendering each segment at its own time offset would require threading segment
boundaries through `ProfileChart`, `computeDensitySeries`, `computeEndSeries`,
and the deco replay engine — touching every analysis file and inviting
off-by-one bugs at every consumer. The synthetic-`SampleSet` approach is
"merge in the UI" performed at the data-shaping layer, keeping the immutable
principle intact and the blast radius tiny.

## Data model

One new PowerSync-backed table. A dive belongs to **at most one** merge group,
so `diveId` is the primary key.

```
DiveMergeLinks
  diveId     TEXT  PK, references dives.id
  groupId    TEXT  shared id for the dives in one group
  ownerId    TEXT  nullable, stamped from Supabase session (RLS)
  createdAt  INT   millis
  updatedAt  INT   millis
  deletedAt  INT   nullable millis (soft delete)
  version    INT   default 1
  syncStatus INT   default 0
```

- A group **exists** while ≥ 2 non-deleted links share a `groupId`.
- **Unmerge** = soft-delete all links with that `groupId` (set `deletedAt`).
- **Demote-to-single**: if a soft-delete leaves a group with one member, that
  member becomes a normal un-merged dive (no special handling — the grouping
  logic simply stops collapsing it).
- The originals (`dives`, `dive_samples`) are **never touched** — re-import,
  re-parse, and undo all stay safe.

`groupId` is generated as a fresh random/uuid-like id at merge time (avoid
`Date.now()`/`Math.random()` constraints do not apply here — this is app code,
not a workflow script; use the project's existing id-generation convention,
e.g. `uuid` or a hash of member dive ids + first `createdAt`).

**v1 scope note (YAGNI):** no group-level title/notes field. The merged tile
derives its label from the segments. A second `DiveMergeGroups` table for
group-level annotation is a clean later addition if wanted.

### Sync

Add to `infra/powersync-sync-rules.yaml` under `user_data.data`:

```yaml
- SELECT * FROM dive_merge_links WHERE owner_id = bucket.user_id
```

…and the matching entry in `lib/sync/cloud/powersync_schema.dart`. **The sync
rules file must actually be deployed to the PowerSync dashboard** for
cross-device merge to work end-to-end (per CLAUDE.md Principle 7). Editing on
iPhone must surface on macOS without extra thought.

## Guardrails

Validated when the user triggers **Merge**. All three must pass:

1. **Same dive computer** — every selected dive shares the same `dcSerial`.
   (Different units → merge action disabled with a reason.)
2. **Chronologically adjacent** — no un-selected, non-deleted dive falls between
   the earliest and latest selected dive (by `startTime`). Prevents "merging
   across" an unrelated dive.
3. **Surface-interval hard cap** — if **any** gap between consecutive selected
   dives (`next.startTime − prev.endTime`) exceeds **`kMergeMaxSurfaceGap`**, the
   merge is **refused** (action disabled / errors with a clear message naming the
   offending gap).

```dart
/// Maximum allowed surface interval between two consecutive dives in a merge.
/// Tunable: raising this re-enables merging repetitive dives with longer
/// surface intervals. Subsurface imposes no such cap on manual merges.
const Duration kMergeMaxSurfaceGap = Duration(hours: 1);
```

**Known trade-off (accepted by the user):** a 1 h hard cap rejects merges of
repetitive dives with normal 60–120 min surface intervals. The single-constant
design makes relaxing this a one-line change.

Overlapping dives (negative gap) are also rejected — they aren't a
surface-interval case and likely indicate the same dive recorded twice.

## Selection UI

- **Long-press** any dive tile → enters selection mode. Tiles show checkboxes;
  tapping toggles selection. Tapping outside / back exits selection mode.
- Selection state lives on `DiveListNotifier` (the existing ChangeNotifier),
  exposed so both the list body and the app chrome can read it:
  - `bool selectionMode`
  - `Set<String> selectedDiveIds`
  - `void enterSelectionMode(String firstDiveId)` / `exitSelectionMode()`
  - `void toggleSelected(String diveId)`
  - `MergeEligibility get mergeEligibility` — derived: `canMerge` bool +
    optional `reason` string for the disabled state (drives the button + a
    snackbar/tooltip).
- **`AppShell` renders a contextual app bar** when `selectionMode` is true:
  shows the selected count and a **Merge** action (enabled only when
  `mergeEligibility.canMerge`). When the selection is exactly one existing
  merged group, the action becomes **Unmerge** instead.
- This list ↔ chrome wiring is the one real integration seam and is done in the
  foreground (an agent can't see both ends).

## List rendering

- `DiveListNotifier` loads merge links (and watches them for sync changes,
  mirroring the existing annotations watch) and **collapses** member dives into
  **one synthetic group tile**, positioned at the group's earliest `startTime`.
- Un-merged dives render exactly as today.
- The group tile shows:
  - date (single date, or a range if segments span days),
  - a **"⛓ N dives"** badge,
  - total **in-water** time (sum of segment durations) as the headline number,
  - **max depth** across segments,
  - the surface interval(s) (e.g. "SI 1h 12m" for two dives; "+2 SIs" for more).
- Search/filter (`diveMatchesQuery`, `diveMatchesFilters`) operate on a group by
  matching **any** member; month-grouping uses the group's earliest start.

## Merged detail

- Reuses `DiveDetailScreen` + `ProfileChart`, fed the synthetic `SampleSet` and
  the virtual merged `Dive`.
- The profile is one continuous trace with flat surface stretches between
  segments. Crosshair, gas-change markers, and trace toggles all work because
  indices are contiguous in the synthetic set.
- Optional polish (not required for v1): faint vertical segment dividers / a
  surface-interval label on the chart at each join. Listed so scope is honest;
  implement only if cheap.
- **Unmerge** is available from the merged detail (overflow menu) and from
  selection mode.

### Summary-stat semantics (v1, documented simplifications)

- **CNS / OTU / surfGF** are computed over the stitched set as one continuous
  dive — i.e. they accumulate across the surface interval. The physically
  correct behavior (CNS 90-min decay, tissue off-gas on air at surface pressure,
  as Subsurface does) is a **future refinement**, not a v1 requirement. The
  merged view labels these as approximate where shown.
- **Deco replay** runs across the whole stitched set; tissues off-gas during the
  flat surface block (a reasonable repetitive-dive approximation). Flag the
  merged surfGF as "experimental" in the merged view.

## The synthetic builder (`MergedSampleBuilder`)

A **pure, Flutter/BLE-free** unit (lives in `lib/analysis/` or
`lib/data/`, no I/O) — heavily unit-tested.

**Input:** an ordered list of `(Dive, SampleSet)` for the group's members,
sorted by `startTime`.

**Output:** `(SampleSet stitched, Dive virtual)`.

**Algorithm:**

1. Sort members by `startTime`.
2. Choose a common `sampleIntervalMs`. **Common case:** all members share the
   same interval (same DC, same trip) → use it directly. **Mismatch:** snap to
   the finest interval and nearest-neighbor resample the coarser segments onto
   that grid (documented; rare). Fall back gracefully if intervals are
   wildly incompatible.
3. For each consecutive pair, compute `gapSeconds = next.start − prev.end`
   (matching Subsurface). Convert to `gapSamples = round(gap / intervalSeconds)`.
4. Concatenate each member's columns. Between members, insert `gapSamples` of
   surface block:
   - `depthMeters = 0.0` (renders as flat line at chart top),
   - `ppo2Bar`, `setpointBar`, `cellMv0/1/2`, `cns`, deco fields, tank pressures
     = **`NaN`** so traces *break* across the surface rather than drawing a false
     line. (`ProfileChart` already skips `NaN` segments.)
   - `gasMixIndex` = a sentinel pointing at no/last gas (density/END skip it via
     the underwater filter anyway).
5. **Gas-mix remap:** build a merged `gasMixes` list (union of members'), and
   rewrite each member's `gasMixIndex` entries to indices into the merged list.
   This is the fiddly part — unit-test it explicitly.
6. Synthesize the virtual `Dive`: `id = groupId`, `maxDepthMeters = max` across
   segments, `duration = sum` of segment durations (in-water; surface excluded),
   `startTime = first.start`, `endTime = last.end`, `diveMode` = members' (all
   same DC; assume consistent), gas mixes = merged list, calibration/scrubber
   from first segment (documented choice).

**Edge cases to test:** two dives same interval; three+ dives; mismatched
intervals; OC dives (empty tank/cell columns); a segment with zero samples;
overlapping dives (should have been rejected by guardrails, but assert/handle).

## Build units (each independently testable)

1. **`DiveMergeLinks` table + DAO** (create group, fetch links, group by
   `groupId`, soft-delete/unmerge, watch changes) + Drift migration + sync-rules
   + `powersync_schema.dart` entry. — *agent*
2. **`MergedSampleBuilder`** (pure: `(Dive, SampleSet)[]` → synthetic
   `SampleSet` + virtual `Dive`, gas remap, surface blocks) — heavily
   unit-tested. — *agent*
3. **Grouping logic in `DiveListNotifier` + merged list tile** (collapse,
   badge, SI display, search/filter/month-group integration). — *agent*
4. **Selection mode + guardrail validation + `AppShell` contextual app bar**
   (the list ↔ chrome seam). — *foreground*
5. **Merged detail wiring + unmerge** (feed synthetic set into
   `DiveDetailScreen`; overflow unmerge). — *foreground integration*

## Verify-before-done

- `flutter analyze` clean.
- `flutter test` green, including new unit tests for `MergedSampleBuilder`,
  the merge-links DAO, and guardrail validation (same-DC, adjacency, 1 h cap,
  overlap rejection).
- Manual: merge two real Petrel dives, confirm stitched profile + surface
  interval render; unmerge; confirm originals intact; confirm the merge survives
  an app restart (local) and appears on a second signed-in device (sync).

## Out of scope (v1)

- Group-level title/notes (`DiveMergeGroups` table).
- Physically-correct CNS decay / tissue off-gas across the surface interval.
- Exporting merged dives to Subsurface as a single merged dive (the write-back
  sync path stays per-original-dive; revisit later).
- Auto-merge on import. This is manual-only.
