# Dive renumbering — design

**Date:** 2026-06-05
**Status:** Approved design, ready for implementation plan
**Source:** Wendy's wishlist, item "Dive renumbering" (third of three; deco = PR #60, statistics = PR #61)

## Goal

Let the user assign **persistent, synced dive numbers** — renumber all dives (or a selected subset) from a chosen starting number in date order, and reset back to the automatic date sequence. The displayed dive number becomes the user's number when set, falling back to today's auto-computed date sequence otherwise.

## Why a stored number (context)

Today the shown dive number is **not stored** — `DiveListNotifier.sequenceByDiveId` computes it live from `start_time` order (oldest = #1). The dive-computer's own `dcDiveNumber` is part of the dive identity hash and must never change. So renumbering needs a **new, user-assignable, synced** number that overrides the auto sequence. It is *user data*, so it lives on the editable **`dive_annotations`** layer — the imported `dives` table stays immutable.

## Non-goals (v1)

- No per-dive number editor in the dive-detail screen (bulk + selection cover it; selecting one dive renumbers it).
- No uniqueness enforcement (duplicate numbers are allowed; renumber-all/selection produce clean sequences by construction).
- No auto-continuation for dives imported *after* a renumber (see Known limitation).
- No change to `dcDiveNumber` or dive identity.

## Storage (all layers — it's a synced column)

A nullable integer `user_dive_number` on `dive_annotations`, added at every layer a synced annotations column lives in (the same path `display_deco_algorithm` / `0010` took):

1. **Supabase/Postgres** — new migration `supabase/migrations/0015_dive_user_number.sql`:
   `ALTER TABLE dive_annotations ADD COLUMN IF NOT EXISTS user_dive_number INTEGER;` (+ a `COMMENT`). **Must be deployed to the live DB before the feature ships** (else CRUD upload of the new column fails). Deploy per `reference_supabase_migration_deploy` (session pooler / SQL editor; `supabase/*.sh`).
2. **PowerSync client schema** — `lib/sync/cloud/powersync_schema.dart`: add `Column.integer('user_dive_number')` to the `dive_annotations` `Table`.
3. **Drift schema** — `lib/data/db/tables.dart`: `IntColumn get userDiveNumber => integer().nullable()();` on `DiveAnnotations`; bump `schemaVersion` 19 → 20 in `database.dart` with `if (from < 20) await m.addColumn(diveAnnotations, diveAnnotations.userDiveNumber);`; run codegen.
4. **Sync rules** — none. `SELECT * FROM dive_annotations` already includes the column; no dashboard deploy.

## Model + DAO

- `lib/data/models/annotation.dart`: add `final int? userDiveNumber;` (+ constructor, `copyWith`, and the row↔model mapping). An annotation that exists only to carry a dive number (no site/notes) is valid — `upsert` already creates the row.
- `lib/data/db/dive_annotations_dao.dart`:
  - Thread `user_dive_number` through the existing `upsert` INSERT/UPDATE column lists and the `_rowToModel` reader.
  - Add a **batch** writer for renumber:
    `Future<void> setUserDiveNumbers(Map<String, int?> byDiveId)` — one PowerSync `writeTransaction` that upserts `user_dive_number` (null clears it) for every entry, stamping `owner_id`/`updated_at`/`version`/`sync_status` like the other writes. One transaction matters for renumber-all (~700 dives).

## Display

`DiveListNotifier.sequenceByDiveId` already holds `_annotationsByDiveId`. Change the returned value per dive to **`annotation.userDiveNumber ?? autoSequenceValue`** (auto value unchanged: date order, oldest = #1). The dive tile (`'#${sequenceNumber ?? dcDiveNumber}'`) and the detail header read this map — **no display-widget changes**.

## Renumber semantics

- **Targets:** the selected **visible dive-list items** (selection mode), or all of them (via Select all). A merged group counts **once**, via its representative real dive id (`annotationsDiveId` — the earliest member; see `reference_merged_dive_synthetic_id`), never the synthetic group id. Numbering visible items (not raw member dives) keeps the resulting sequence gap-free.
- **Compute (pure, testable):** sort targets by `start_time` ascending; assign `start, start+1, …`. A pure helper in a new **Flutter-free** file `lib/ui/notifiers/dive_renumber.dart`: `Map<String, int> computeRenumber(List<({String diveId, int startTime})> targets, int start)` — trivially unit-testable in isolation.
- **Apply:** `DiveListNotifier.renumberSelected(int start)` builds the map from the current selection (or all) and calls `dao.setUserDiveNumbers(map)`, then exits selection mode. The annotations watch-stream already refreshes `_annotationsByDiveId`, re-deriving the sequence.
- **Reset:** `resetNumberingSelected()` calls `setUserDiveNumbers({for each target: null})`.

## UI (mirrors dive-merge)

The merge UI is a selection-mode app bar in `app_shell.dart` (~562: `leading` = exit, `title` = "N selected", `actions` = Merge). Add to that same selection app bar:
- **Select all** action — `IconButton(Icons.select_all)` → `notifier.selectAll()` (selects every visible list item — a merged group via its representative id; new method on the notifier).
- **Renumber** action — `IconButton(Icons.format_list_numbered)`, enabled when ≥1 selected → opens a **Renumber dialog**.

**Renumber dialog** (`lib/ui/widgets/renumber_dialog.dart`):
- A numeric "Start number" field (default 1).
- A live **preview**: "#{start} → #{start + n − 1} for {n} dives (by date)".
- **Apply** → `notifier.renumberSelected(start)`.
- **Reset to automatic** (secondary) → `notifier.resetNumberingSelected()` (clears the targets' custom numbers).

So: select all + Renumber = renumber-all; select a subset + Renumber = renumber-selection; the dialog's Reset = reset. All within the merge-style selection flow.

## Known limitation (v1)

A dive imported *after* a renumber-all has no `user_dive_number`, so it shows its auto date-rank (which may look out of place beside custom numbers) until the user renumbers again. Documented; auto-continuation is a later nicety.

## Edge cases

- **Empty selection:** Renumber action disabled.
- **Reset on dives that were never custom-numbered:** no-op (writes null over null) — harmless.
- **Merged groups:** target the representative real dive id (above); a group displays its representative's number.
- **Duplicate numbers:** allowed; no enforcement.
- **Start number validation:** clamp to ≥ 0 (or ≥ 1); reject empty/non-numeric in the dialog.

## Testing

- **`computeRenumber` (pure unit):** date-order assignment from a start; single dive; ties on start_time (stable); start = 1 and start = 482.
- **Sequence override:** `sequenceByDiveId` returns `userDiveNumber` when the annotation has one, else the auto value (test via the notifier with seeded dives + annotations, or extract the override into a tiny pure function and test that).
- **DAO `setUserDiveNumbers` (round-trip):** set numbers for several dives in one call; read back; null clears.
- **Migration:** v19 → v20 adds `user_dive_number` to `dive_annotations`; bump every `expect(db.schemaVersion, 19)` in `migration_test.dart` to 20 and add a v19→v20 test (learned from the stats migration regression).
- **Verify:** `flutter analyze` clean, `flutter test` green. Manual: long-press → Select all → Renumber from 482 → numbers update across the list and detail; reset restores the date sequence; restart confirms persistence; (cross-device sync verified after the Supabase migration is deployed).

## Files touched

**Create:** `supabase/migrations/0015_dive_user_number.sql`, `lib/ui/notifiers/dive_renumber.dart` (pure `computeRenumber`), `lib/ui/widgets/renumber_dialog.dart`, tests (`computeRenumber`, DAO batch, migration v19→v20).
**Modify:** `lib/sync/cloud/powersync_schema.dart`, `lib/data/db/tables.dart`, `lib/data/db/database.dart` (+ regenerated `database.g.dart`), `lib/data/models/annotation.dart`, `lib/data/db/dive_annotations_dao.dart`, `lib/ui/notifiers/dive_list_notifier.dart`, `lib/ui/app_shell.dart`, `test/data/db/migration_test.dart`.

## Resolved decisions

- **Operations:** renumber all + renumber selection + reset-to-automatic (reset lives inside the renumber dialog).
- **Number direction:** start number on the oldest target, ascending by date (default start = 1; preview shows the resulting range).
- **Storage:** synced `user_dive_number` on `dive_annotations` (Supabase + PowerSync + Drift); display = `userDiveNumber ?? auto`.
- **UI:** mirror dive-merge — Select all + Renumber actions in the selection-mode app bar; reset in the dialog. No per-dive editor in v1.
- **Branch:** stacks on `feat/statistics-tab` (Drift schema 19 → 20); merge order #60 → #61 → renumbering.
