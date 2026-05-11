# Subsurface write-direction — Phase 1 design

**Status:** approved 2026-05-11. Implementation plan to follow via `writing-plans`.

**Owner:** CCRLog sync.

**Context:** The CCRLog → Subsurface git write-direction sync has been disabled behind an unconditional `throw` in `lib/sync/subsurface_git/sync_orchestrator.dart` since 2026-05-08. That date's incident overwrote 13 dives' correct Subsurface-side Divecomputer recordings with CCRLog-emitted output that used the older sparse-`dc_supplied_ppo2` / frequent-`po2` format, destroying the diver's authoritative records. The user's working tree at `~/Dev/CCRLog/ss_git/` retained the correct content; the bad commit was on Subsurface Cloud. Recovery was a force-push from the user's local repo. The safety hold prevents recurrence but blocks every legitimate use case (pushing BLE-imported dives, pushing annotation edits).

This document specifies the Phase 1 redesign that lifts the safety hold safely.

## Goals (Phase 1)

1. Push BLE-imported dives that Subsurface does not yet have.
2. Push annotation edits made in CCRLog (notes, rating, buddies, tags, conditions stars, etc.) back to Subsurface's `Dive-NNN` file for dives Subsurface already has.
3. **Never** modify a Subsurface-side `Divecomputer` file for an existing dive — the sample stream is sacred to the dive computer that recorded it.
4. Surface conflicts as actionable status rather than silent overwrites.

## Non-goals (deferred)

- Pushing CCRLog's `Divecomputer` recording as a `Divecomputer-1` / `-2` sibling when CCRLog has data from a different DC than Subsurface (Phase 2).
- Bidirectional conflict resolution UI where the user picks per-field which side wins (Phase 3).
- Pulling Subsurface-side annotation edits back into CCRLog (Phase 4 — bootstrap import is currently the only path).

## Architecture

`SyncOrchestrator.syncNow()` already has the right outer shape (ensureCloned → pull → snapshot → plan → write → stage → commit → push, with up-to-3 retries on push rejection). Only the planner's "for existing dive" branch changes.

```
SyncPlanner.plan(...)
  for each CCRLog dive bundle:
    classify: NEW (no matching (dcSerial, startTime) in remote) or EXISTING.
    if NEW:
      emit full Dive-NNN  (existing behaviour)
      emit full Divecomputer  (existing behaviour)
    if EXISTING:
      build merged Dive-NNN  ← line-by-line substitution against on-disk file
      pre-write diff check  ← abort if foreign edits touch owned lines, or
                              if non-owned lines would change at all.
      Divecomputer: always omitted from filesToWrite for existing dives.
  return SyncPlan + abort list (per-dive reason)
```

The orchestrator's git-side code (`_planAndPush`, retry loop, commit, push) does not change.

## CCRLog-owned lines in Dive-NNN

For an existing dive, the merge only ever replaces lines from this allow-list when CCRLog holds a non-empty value:

| Subsurface line key | CCRLog source | Owned because |
|---|---|---|
| `rating` | `DiveAnnotation.rating` | dedicated 0–5 picker in the Details tab |
| `visibility` | `DiveAnnotation.visibility` | Information tab star row |
| `wavesize` | `DiveAnnotation.wavesize` | Information tab star row |
| `current` | `DiveAnnotation.current` | Information tab star row |
| `surge` | `DiveAnnotation.surge` | Information tab star row |
| `chill` | `DiveAnnotation.chill` | Information tab star row |
| `airtemp` | `DiveAnnotation.airTempC` | Information tab numeric field |
| `watertemp` | `DiveAnnotation.waterTempC` | Information tab numeric field |
| `tags` | `DiveAnnotation.tags` | tags chip input |
| `buddy` | `DiveAnnotation.buddies` | buddies chip input |
| `suit` | `DiveAnnotation.suit` | Equipment tab |
| `notes` | `DiveAnnotation.notes` | notes field |
| `divesiteid` | derived from `siteLatitude`/`siteLongitude` via existing `_siteIdFor()` | when CCRLog has GPS, it owns the site reference |
| `weightsystem` (repeating) | `DiveAnnotation.weights` list | Equipment tab Weights editor |

Anything else — including `duration`, `cylinder` lines, `divemaster`, `watersalinity`, `divetype`, and any unknown lines that future Subsurface versions may emit — is **left verbatim** in the merged output.

If CCRLog has a value for an owned line that does not exist in the existing file (e.g. user added `chill` in CCRLog for a dive that did not have it before), the line is appended in the conventional position (the existing mapper already has insertion-order logic that the merge re-uses).

## Merge implementation

The merge is a **parsed line-by-line substitution**, not a parse-emit-reserialize. Concretely:

1. Parse the existing `Dive-NNN` file from the local clone working tree into `List<SsLine>` via the existing `parseSubsurfaceFile()`.
2. For each existing line, if its key is in the owned allow-list AND CCRLog has a value for that key:
    - Replace that line with the CCRLog-emitted value (using the same `QuotedLine` / `ScalarLine` / `TagsLine` factories the current mapper uses, so the rendered text matches Subsurface's output style exactly).
3. For each owned key CCRLog has a value for that is **absent** in the existing file:
    - Insert at the conventional position (mapper's existing emission order is the source of truth).
4. Repeating lines (`weightsystem`, `cylinder`): the allow-list contains `weightsystem`; if CCRLog has the weights list it replaces the entire group of `weightsystem` lines with CCRLog's emission. `cylinder` is **not** owned and is left untouched.
5. Serialise with `serializeSubsurfaceFile()`.

This preserves byte-level fidelity to Subsurface's output for everything we do not own — formatting, quoting, ordering, comments. A pure-Dart `_mergeDiveLines` helper sits next to the existing `_mergeSiteLines` / `_mergeTopLevel` helpers in `sync_planner.dart`.

## Defense-in-depth: pre-write diff check

Even with the merge constrained to owned lines, the file's on-disk state at write time may have drifted between `pull` and our write (a concurrent edit, a half-applied earlier sync, a `git pull` race). Before staging any file we read its current bytes back and compare:

| File category | Diff result | Action |
|---|---|---|
| New dive's `Dive-NNN` or `Divecomputer` | n/a — file does not exist on disk | write |
| Existing dive's `Divecomputer` | n/a — never in `filesToWrite` to begin with | skip |
| Existing dive's `Dive-NNN` | merged output == on-disk content | drop from `filesToWrite` (no-op) |
| Existing dive's `Dive-NNN` | only owned lines differ | write merged output |
| Existing dive's `Dive-NNN` | a non-owned line differs from what the existing file already has | **abort that dive's plan**, do not stage either of its files, surface `foreign-edit-conflict` with the differing line keys |
| `Site-<id>` | existing merge logic in `_mergeSiteLines` already correct | unchanged |
| `00-Subsurface` | existing merge logic in `_mergeTopLevel` already correct | unchanged |

Aborts return up through `SyncPlan` as a new `abortedDives` list: `{ dive: Dive, reason: AbortReason, conflictingLines: [String] }`. The orchestrator emits them in `SubsurfaceSyncResult`. Aborts are not exceptions — sync still succeeds for the other dives.

## Settings UX

`subsurface_sync_section.dart` gains a "Push" button under the existing bootstrap-import card. After a sync:

```
Last sync: 12:34
Pushed 3 new dives, merged annotations on 8 dives.

Skipped 2 dives (no overwrite):
  • #705 — cylinder edits in Subsurface
  • #706 — duration differs
```

The "Skipped" lines are styled informational, not error. The user resolves them by editing in CCRLog to match, or by accepting that CCRLog's data stays unsynced for those dives. No automatic retry on aborts.

## Tests required before lifting the hold

1. **Incident replica fixture.** `test/fixtures/subsurface_incident_replica/` carries the bad-flavour Divecomputer (sparse `dc_supplied_ppo2`, frequent rounded `po2`) and the user's correct working-tree Divecomputer for one of the 13 dives. Test asserts the new planner *aborts* for this dive rather than emitting the bad flavour.
2. **New-dive push.** Planner emits full `Dive-NNN` + `Divecomputer` when no matching (dcSerial, startTime) exists in the remote snapshot.
3. **Existing-dive merge — happy path.** CCRLog has edited `notes` and `rating`. Planner produces a merged `Dive-NNN` where only those two lines differ from the on-disk file. `Divecomputer` is not in `filesToWrite`.
4. **Existing-dive merge — added owned line.** CCRLog has a `chill 5` for a dive whose Dive-NNN had no chill line. Merged output includes the new line at the conventional position.
5. **Foreign-edit conflict.** Subsurface has edited a `cylinder` line. Planner aborts the dive with reason `foreign-edit-conflict` and conflictingLines `[cylinder]`. No files for that dive are staged.
6. **Divecomputer-protected.** For every existing dive in a fixture, `Divecomputer` is never in `filesToWrite` regardless of whether CCRLog's mapped output would match.
7. **Idempotent re-sync.** Running the planner twice on identical state produces an empty plan the second time (no-op).
8. **Hold removed.** `syncNow()` no longer throws; the `skip:` clause on the orchestrator tests at `test/sync/subsurface_git/sync_orchestrator_test.dart:142` (and any sibling `skip:` lines added at the same time) is removed and those tests pass on a clean state.

`flutter test test/sync/subsurface_git/` must pass with all of these green before merging. Manual smoke against a *throwaway clone* of the user's repo (not the live `ss_git` working tree) is required before pushing to `main`.

## Code changes (anticipated)

- `lib/sync/subsurface_git/sync_orchestrator.dart` — remove the safety throw, remove the `ignore_for_file: dead_code` pragma, surface `abortedDives` on `SubsurfaceSyncResult`.
- `lib/sync/subsurface_git/sync_planner.dart` — replace the existing-dive branch with the merge path; add `_mergeDiveLines` helper alongside the existing `_mergeSiteLines` / `_mergeTopLevel`; add diff check before staging.
- `lib/sync/subsurface_git/mapper.dart` — extract the owned-line emission so the merge helper can call into a single source of truth for "what does CCRLog emit for `rating`" etc.
- `lib/ui/widgets/subsurface_sync_section.dart` — add the Push button and skipped-dives status block.
- `test/sync/subsurface_git/sync_planner_test.dart` — new merge / abort / idempotent tests.
- `test/fixtures/subsurface_incident_replica/` — new fixture set.

The current planner's full-file write path for existing dives is **deleted** in this change, not left dormant. Phase 2's bidirectional logic will be a new code path, not a resurrection of the old one — keeping it dormant is what allowed the 2026-05-08 incident.

## Out-of-scope notes captured for future phases

- **Phase 2 — Divecomputer-N as a second recording.** When CCRLog has Petrel 3 data for a dive that Subsurface only has from an older DC, CCRLog could push the new recording as `Divecomputer-1` (or `-2`) alongside Subsurface's. Subsurface natively supports multiple Divecomputer files per dive folder.
- **Phase 3 — interactive conflict resolution.** When the diff check aborts a dive, surface the differing lines and let the user pick a resolution per line.
- **Phase 4 — annotation backflow.** Today CCRLog only ingests Subsurface annotations on bootstrap. A future phase pulls Subsurface-side edits back into CCRLog so a round-trip works in both directions.
