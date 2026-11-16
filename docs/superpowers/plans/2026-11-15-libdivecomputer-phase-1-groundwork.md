# libdivecomputer phase 1: groundwork — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prepare the data model, sync and import path so libdivecomputer dives can arrive in phase 2, and add the in-place refresh that ends today's Shearwater duplicates after a Subsurface Cloud bootstrap. No new brands become visible.

**Architecture:** Six PRs, each mergeable on its own, in an order where nothing reaches a device that an installed build would mishandle. The database and sync gate go first (additive columns, a server-side guard, the sync parameter), then the brand fields, then one download shape with Shearwater wrapped behind it, then the refresh, and last the Shearwater reader version bump that re-parses stored dives.

**Tech Stack:** Dart 3 / Flutter 3.44, PowerSync 2.1.0 (dives and samples), Drift (raw blobs and device-local state), Supabase Postgres, `packages/subsurface_core` (pure Dart).

**Spec:** `docs/superpowers/specs/2026-11-15-libdivecomputer-brands-design.md` (PR #214, sections 6, 7, 7a, 11, 12). Read it from `main` once #214 is merged, before that from branch `spec/libdivecomputer-brands`.

## Global Constraints

- Dives and samples live in PowerSync. Read and write them through `_ps`, never `_drift.select(_drift.dives)` or `_drift.diveSamples`.
- Every new Postgres column ships in a migration that restates the table's grants (`grant select, insert, update, delete on table public.<t> to authenticated, service_role;`), plus the matching `lib/sync/cloud/powersync_schema.dart` change and a check of `infra/powersync-sync-rules.yaml`.
- A migration is applied to the live database **before** any build containing the matching app change runs signed in. Otherwise uploads fail on unknown columns and land in the poison-op quarantine.
- Spec: "Existing dive ids and analysis for Shearwater must not change, and its import changes only by gaining the refresh." Shearwater dive ids are `generateDiveId(serial, diveNumber, startTimestamp)` and stay so.
- Spec: "a refresh replaces a dive's imported data and keeps everything else." Imported data changes only through the refresh.
- `parser_version = -1` (`kSubsurfaceImportedParserVersion`) marks a Subsurface Cloud copy. It is never written over a download.
- Subsurface copy match window: start times within **60 seconds** (`kSameDiveWindowSeconds = 60`).
- `dc_model` stays NOT NULL and keeps the `ShearwaterModel` index. Spec: libdivecomputer dives store `ShearwaterModel.unknown` (index 13); not written in phase 1.
- Metric in the database. The raw blob is kept forever.
- `packages/subsurface_core` stays pure: only `lib/data/sample_codec/column_packer.dart` may import `dart:io`, and every new `lib/` file is exported from `lib/subsurface_core.dart` (`test/purity_test.dart` enforces both).
- Never remove the write-direction safety hold in `sync_orchestrator.dart`.
- Don't run `dart format` on whole files. Match the surrounding style by hand.
- Every PR: `flutter analyze` clean, `flutter test` passing, `dart test` in `packages/subsurface_core` passing, `./supabase/lint_migrations.sh` passing. `main` is protected: PR plus a green "analyze + test".
- Git text in English. Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Build agents run on `model: "sonnet"`; design, debugging and review agents on `"opus"`.

## Review Focus

1. **An installed build from before phase 1 (1.1.0+47 and older) on the same account as a phase-1 build.** Expected: it keeps syncing and displaying its dives, and its uploads never lower a refreshed dive's `parser_version` or replace its data with an older parse. Pinned by the trigger check in Task 1 and the old-row decode test in Task 4.
2. **A phase-1 build reading rows written by a later build:** an events blob with an unknown event type or a newer format version, four ppO2 channels, or a `dives` row with brand fields set. Expected: no crash, unknown events kept as `other`, an unknown format read as "no events". Pinned in Tasks 2 and 3.
3. **The first Petrel download after a Subsurface bootstrap,** where Subsurface's start time differs by a few seconds and its serial is hex, and then "download everything again". Expected: every copy is refreshed under its own id, nothing is duplicated, and refreshed copies are not offered as new on the next scan. Pinned in Tasks 10–13.
4. **A refresh whose gas list differs from the stored one:** reordered, a mix gone, or two mixes with the same O2/He. Also a refresh of a soft-deleted dive. Expected: every cylinder assignment survives (moved with its mix, or kept as unassigned), and a deleted dive stays deleted. Pinned in Tasks 10 and 11.
5. **The background re-parse when it is interrupted, or hits a raw blob that no longer parses.** Expected: it carries on at the next launch, reports a failing dive to Sentry once per reader version, and never starts before this launch's first completed sync when signed in. Pinned in Task 16.

---

## PR map

| PR | Branch | Tasks | Ships safely because | Egbert, outside the code |
|---|---|---|---|---|
| 1 Storage groundwork | `feat/libdc-p1-storage` | 1–4 | Columns are additive. Old builds ignore columns they don't know. The trigger only refuses an update that lowers `parser_version`, which nothing does today. | Apply `0026` and run its check **before** any build of this branch runs signed in. |
| 2 Sync gate | `feat/libdc-p1-sync-gate` | 5 | Every existing row has `dc_family` NULL, so every client keeps getting exactly what it gets today. Phase-1 builds send `dc_engines: 1`, so they won't get libdivecomputer rows either. | Needs #208 merged first. Validate in the dashboard, deploy together with #208 (one full re-sync), then run the fake-row check. Must be live before any phase-2 build exists. |
| 3 Brands for computers and copies | `feat/libdc-p1-brands` | 6–7 | Old builds upsert `dive_computers` by id, and the id scheme for Shearwater is unchanged. Bootstrap ids are unchanged. | — |
| 4 Shared download shape | `feat/libdc-p1-download-shape` | 8–9 | No data change. | Petrel 3 check (Task 9). |
| 5 In-place refresh | `feat/libdc-p1-refresh` | 10–14 | Old builds receive refreshed rows as updates of rows they already have. The trigger from PR 1 stops their uploads from undoing a refresh. | Petrel 3 check after a bootstrap, on a test account first (Task 14). |
| 6 Reader v2 and background re-parse | `feat/libdc-p1-reparse` | 15–16 | Same as PR 5. Old builds download the refreshed rows again (bandwidth only). | Petrel 3 check (Task 16). |

PRs 2 and 3 only depend on PR 1. PR 4 only needs `main`. PR 5 needs PRs 1, 3 and 4. PR 6 needs PR 5. Work PRs that touch the same file one at a time: `import_notifier.dart` changes in PRs 3, 4 and 5, and `dive_dao.dart` changes in PRs 1 and 5.

Migration number: `0025` belongs to #210 (open blends). Use `0026`. If another migration took 0026 by then, use the next free number and rename everywhere.

---

## PR 1 — Storage groundwork

### Task 1: Migration 0026 (columns, dive_computers key, keep-newer guard)

**Files:**
- Create: `supabase/migrations/0026_dive_brands_events_refresh.sql`
- Create: `supabase/checks/0026_keep_newer_parse.sql` (manual check, run in a transaction that rolls back)

**Interfaces:**
- Produces (Postgres):
  - `dives`: `dc_vendor text`, `dc_product text`, `dc_family integer`, `dc_model_code integer`, `match_candidates_json text`. All nullable. A NULL `dc_vendor` means "Shearwater" on a download and "unknown" on a Subsurface copy (Task 10's `effectiveVendor`). No backfill: the update would replicate every dive to every device for a value the app can derive.
  - `dive_samples`: `cell_ppo2_blob text`, `events_blob text`, `parser_version integer`, `dc_family integer`. All nullable.
  - `dive_computers`: `dc_vendor text not null default 'Shearwater'` (backfilled before `set not null`), `dc_product text`, `dc_family integer`, `dc_model_code integer`. Unique key moves from `(owner_id, serial)` to `(owner_id, dc_vendor, serial)`.
  - `dive_bailout_carry`: `dc_family integer` (a copy of the dive's, so the sync gate in Task 5 can filter it).
  - Function `public.keep_newer_parse()` plus `before update` triggers `dives_keep_newer_parse` and `dive_samples_keep_newer_parse`.

- [ ] **Step 1: Look up the live constraint name.** In the Supabase SQL editor run `select conname from pg_constraint where conrelid = 'public.dive_computers'::regclass and contype = 'u';`. Expected: `dive_computers_owner_id_serial_key`. If the name differs, use the live name in Step 2.

- [ ] **Step 2: Write the migration.** Follow `0023_user_acknowledgements.sql` for layout and comments. Add every column before creating the function and triggers, since the `dive_samples` trigger reads the new `parser_version`. Every `add column` uses `if not exists`. The `dive_computers` part runs in this order: add the columns; `update dive_computers set dc_vendor = 'Shearwater' where dc_vendor is null;`; `alter column dc_vendor set default 'Shearwater'`; `alter column dc_vendor set not null`; `alter table dive_computers drop constraint if exists dive_computers_owner_id_serial_key;`; `create unique index if not exists dive_computers_owner_vendor_serial_key on public.dive_computers (owner_id, dc_vendor, serial);`. Restate the grants for `dives`, `dive_samples`, `dive_computers` and `dive_bailout_carry`. End with `NOTIFY pgrst, 'reload schema';`.

  The guard function (the one block of SQL the plan fixes):

  ```sql
  create or replace function public.keep_newer_parse() returns trigger
  language plpgsql set search_path = public as $$
  begin
    -- A Subsurface copy (-1) may be replaced by any reader. Otherwise an
    -- update may never lower parser_version: an older reader's upload
    -- (an old build, or a device that hadn't synced yet) keeps the newer
    -- row. Returning OLD makes the update a no-op; the uploading client
    -- gets the server row back through sync.
    if old.parser_version is not null and new.parser_version is not null
       and old.parser_version >= 0
       and new.parser_version < old.parser_version then
      return old;
    end if;
    return new;
  end $$;
  ```

  Then `drop trigger if exists ... ; create trigger ... before update on public.dives for each row execute function public.keep_newer_parse();`, and the same on `public.dive_samples`.

- [ ] **Step 3: Run the lint.** Run: `./supabase/lint_migrations.sh`. Expected: exit 0.

- [ ] **Step 4: Write the check script.** `supabase/checks/0026_keep_newer_parse.sql` runs `begin;`, then for a throwaway dive id owned by `auth.uid()`: inserts a `dives` row at `parser_version 2` and a `dive_samples` row at `parser_version 2`. It updates both to 1 and selects: expect 2. It updates the dive to 3 and selects: expect 3. It inserts a second dive at -1, updates it to 1, selects: expect 1. It inserts a `dive_computers` row for serial 1 with vendor 'Shearwater' and one for serial 1 with vendor 'Divesoft': both succeed. A second 'Shearwater'/1 row fails with a unique violation. Ends with `rollback;`. A header comment says how to run it.

- [ ] **Step 5: Commit.**

  ```bash
  git add supabase/migrations/0026_dive_brands_events_refresh.sql supabase/checks/0026_keep_newer_parse.sql
  git commit -m "feat(supabase): brand, events and per-cell ppO2 columns, dive_computers keyed by vendor, keep-newer-parse guard"
  ```

- [ ] **Step 6 (Egbert): apply and check.** Apply with `./supabase/apply_migrations.sh` (Session pooler, see `supabase/README.md`), run the check script in the SQL editor, and run `./supabase/check_migrations.sh`. Expected: no drift, and every check in the script returns its expected value. Nothing else in PR 1 may run signed in before this.

### Task 2: Domain models and codecs in subsurface_core

**Files:**
- Modify: `packages/subsurface_core/lib/data/models/dive.dart`
- Modify: `packages/subsurface_core/lib/data/models/sample_set.dart`
- Modify: `packages/subsurface_core/lib/data/sample_codec/sample_codec.dart`
- Modify: `packages/subsurface_core/lib/data/sample_codec/column_packer.dart`
- Create: `packages/subsurface_core/lib/data/models/dive_event.dart`
- Create: `packages/subsurface_core/lib/data/sample_codec/event_codec.dart`
- Modify: `packages/subsurface_core/lib/shearwater/parser/parsed_dive.dart` (move `DiveEvent` / `DiveEventType` out, re-export)
- Modify: `packages/subsurface_core/lib/shearwater/parser/hardware.dart`
- Modify: `packages/subsurface_core/lib/shearwater/parser/dive_converter.dart` (`ConvertedDive.events` only; `convert()` unchanged until Task 15)
- Modify: `packages/subsurface_core/lib/subsurface_core.dart` (barrel)
- Test: `packages/subsurface_core/test/data/sample_codec/event_codec_test.dart`, `packages/subsurface_core/test/data/sample_codec/cell_ppo2_codec_test.dart`, `packages/subsurface_core/test/data/models/shearwater_product_test.dart`

**Interfaces:**
- Produces:
  - `Dive`: new optional named fields `String? dcVendor`, `String? dcProduct`, `int? dcFamily`, `int? dcModelCode` (default null).
  - `const String kShearwaterVendor = 'Shearwater';` and `String? shearwaterProductName(ShearwaterModel m)` in `hardware.dart`. Names: predator 'Predator', petrel 'Petrel', petrel2 'Petrel 2', petrel3 'Petrel 3', nerd 'NERD', nerd2 'NERD 2', perdix 'Perdix', perdixAi 'Perdix AI', perdix2 'Perdix 2', teric 'Teric', peregrine 'Peregrine', peregrineTx 'Peregrine TX', tern 'Tern', unknown → null. These are the names the Subsurface mapper already reads after "Shearwater ".
  - `SampleSet.cellPpo2Bar`: `List<Float32List>`, default `const []`. One channel per cell, ppO2 in bar. Empty for Shearwater, which keeps writing mV.
  - `SampleCodec.encode` writes key `'cellPpo2'` only when `cellPpo2Bar` is not empty, in the same multi-channel layout as `'tankPressures'` (rename the private helpers to `_packChannels` / `_unpackChannels` and use them for both). `decode` reads an absent key as `const []`.
  - `DiveEvent` (moved to `data/models/dive_event.dart`): `int timeMs`, `DiveEventType type`, `int rawType` (default 0; the engine's own event number), `int? value`, `int? bearing`. Existing constructor calls in `dive_parser.dart` keep compiling.
  - `enum DiveEventType` with a fixed `int wire`: `other(0)`, `bookmark(1)`, `gasSwitch(2)`, `setpointChange(3)`, `decoWarning(4)`, `ceilingViolation(5)`, `ascentWarning(6)`. `static DiveEventType fromWire(int)` returns `other` for unknown codes.
  - `ColumnPacker.packBytes(Uint8List) → Uint8List` and `unpackBytes(Uint8List) → Uint8List` (zlib, like the other columns).
  - `EventCodec.formatVersion = 1`, `static Uint8List? encode(List<DiveEvent> events)` (null when empty), `static List<DiveEvent> decode(Uint8List? blob)`. Layout before zlib, big-endian: `uint8 formatVersion`, `uint16 count`, then 16 bytes per event: `uint32 timeMs`, `uint8 type.wire`, `uint8 flags` (bit 0 value present, bit 1 bearing present), `uint16 rawType`, `int32 value`, `int32 bearing` (0 when absent).
  - `ConvertedDive.events`: `List<DiveEvent>`, default `const []`.

- [ ] **Step 1: Write the failing tests.**

  ```dart
  // event_codec_test.dart
  test('round-trips every field, value and bearing optional', ...);
    // events: bookmark at 125000 ms with value 7 and bearing 270, and
    // setpointChange at 600000 ms, rawType 0x0D, no value, no bearing.
    // expect decode(encode(e)) to equal e field by field.
  test('no events encodes to null and null decodes to empty', ...);
  test('an unknown type code decodes as other and keeps rawType', ...);
    // hand-build a v1 blob with wire 42 and rawType 0x1234:
    // expect type == DiveEventType.other, rawType == 0x1234.
  test('a newer format version decodes as no events, without throwing', ...);
  test('a truncated blob decodes as no events, without throwing', ...);

  // cell_ppo2_codec_test.dart
  test('four cell channels round-trip', ...);
    // channels [0.70, 1.30, 1.29, 1.31] repeated over 50 samples: equal after decode.
  test('a blob map without cellPpo2 decodes to an empty list', ...); // a samples row from before phase 1
  test('an empty cellPpo2Bar writes no cellPpo2 key', ...);

  // shearwater_product_test.dart
  test('every model except unknown has a distinct product name', ...);
  test('petrel3 is "Petrel 3" and unknown is null', ...);
  ```

- [ ] **Step 2: Run them and check they fail.** Run: `cd packages/subsurface_core && dart test test/data`. Expected: compile errors (no `EventCodec`, no `cellPpo2Bar`, no `shearwaterProductName`).

- [ ] **Step 3: Implement the interfaces above.** In `parsed_dive.dart` replace the two declarations with `export '../../data/models/dive_event.dart' show DiveEvent, DiveEventType;` plus the import. Add both new files to the barrel.

- [ ] **Step 4: Run the package tests.** Run: `cd packages/subsurface_core && dart analyze --fatal-infos && dart test`. Expected: all pass, including `purity_test.dart`.

- [ ] **Step 5: Commit.**

  ```bash
  git add packages/subsurface_core
  git commit -m "feat(core): brand fields, per-cell ppO2 channels and a stored event codec"
  ```

### Task 3: Client schemas (PowerSync and Drift)

**Files:**
- Modify: `lib/sync/cloud/powersync_schema.dart`
- Modify: `lib/data/db/tables.dart`, `lib/data/db/database.dart` (schemaVersion 20 → 21), regenerate `lib/data/db/database.g.dart`
- Modify: `lib/data/db/dive_dao.dart` (`rowToDive` only)
- Test: `test/sync/cloud/powersync_schema_test.dart`, `test/data/db/migration_test.dart`, `test/data/db/dive_dao_test.dart`

**Interfaces:**
- Produces:
  - `appSchema`: on `dives`, `dc_vendor` / `dc_product` / `match_candidates_json` as text and `dc_family` / `dc_model_code` as integer. On `dive_samples`, `cell_ppo2_blob` / `events_blob` as text and `parser_version` / `dc_family` as integer. On `dive_computers`, `dc_vendor` / `dc_product` as text and `dc_family` / `dc_model_code` as integer. On `dive_bailout_carry`, `dc_family` as integer.
  - Drift `Dives`: nullable `dcVendor`, `dcProduct`, `dcFamily`, `dcModelCode`, `matchCandidatesJson`. Drift `DiveComputers`: nullable `dcVendor`, `dcProduct`, `dcFamily`, `dcModelCode`. Leave the legacy Drift `serial.unique()` alone and add a comment: the Drift table hasn't been written since Phase 2.3, and the live key is `(dc_vendor, serial)` in PowerSync and Postgres.
  - New Drift table `DiveImportMarks` (`dive_import_marks`), device-local and never synced: `diveId` text PK, `rawBlobMissing` bool default false, `reparseFailedVersion` int nullable.
  - `DiveDao.rowToDive` maps the five new `dives` columns. `_rowToDiveComputer` in `equipment_dao.dart` maps the four new `dive_computers` columns.

- [ ] **Step 1: Write the failing tests.** In `powersync_schema_test.dart`, extend 'column types match the Postgres schema' with one `expect` per new column. In `migration_test.dart`, add 'v20 → v21 adds the brand columns and dive_import_marks', following the existing per-version tests. In `dive_dao_test.dart`, add:

  ```dart
  test('rowToDive reads a pre-phase-1 row (new columns NULL)', ...);
  test('rowToDive reads brand fields and match candidates when set', ...);
    // row with dc_vendor 'Divesoft', dc_product 'Liberty', dc_family 0x00060000,
    // dc_model_code 10, match_candidates_json '["a","b"]': all mapped.
  ```

- [ ] **Step 2: Run them and check they fail.** Run: `flutter test test/sync/cloud/powersync_schema_test.dart test/data/db/migration_test.dart test/data/db/dive_dao_test.dart`. Expected: FAIL.

- [ ] **Step 3: Implement.** In the `from < 21` migration step, `addColumn` each new column and `createTable(diveImportMarks)`. Run `dart run build_runner build --delete-conflicting-outputs`.

- [ ] **Step 4: Run them and check they pass.** Same command. Expected: PASS. Then `flutter analyze`: clean.

- [ ] **Step 5: Commit.**

  ```bash
  git add lib/sync/cloud/powersync_schema.dart lib/data/db test/sync/cloud/powersync_schema_test.dart test/data/db
  git commit -m "feat(db): brand, events and per-cell ppO2 columns on the client, device-local import marks"
  ```

### Task 4: DiveDao writes and reads the new columns

**Files:**
- Modify: `lib/data/db/dive_dao.dart` (`importDive`, `getSamples`, new `getEvents`)
- Modify: `lib/analysis/merge/merged_sample_builder.dart`
- Test: `test/data/db/dive_dao_test.dart`, `test/analysis/merge/merged_sample_builder_test.dart`

**Interfaces:**
- Consumes: Task 2's `Dive` brand fields, `SampleSet.cellPpo2Bar`, `EventCodec`, `ConvertedDive.events`. Task 3's columns.
- Produces:
  - `importDive` (signature unchanged in this PR) also writes `dc_vendor`, `dc_product`, `dc_family`, `dc_model_code` from `converted.dive`. On `dive_samples` it writes `cell_ppo2_blob` (base64 of `'cellPpo2'`, or NULL), `events_blob` (base64 of `EventCodec.encode(converted.events)`, or NULL), `parser_version` (the `parserVersion` argument) and `dc_family`.
  - `getSamples` decodes `cell_ppo2_blob` when present.
  - `Future<List<DiveEvent>> getEvents(String diveId)`: decodes `events_blob`; returns `const []` when there is no row or no blob.
  - The merged builder carries `cellPpo2Bar` the way it carries `tankPressuresBar` (`merged_sample_builder.dart:94–166`), and the brand fields the way it carries `dcModel` (line 194).

- [ ] **Step 1: Write the failing tests.**

  ```dart
  test('importDive stores the brand fields', ...);
  test('per-cell ppO2 survives importDive → getSamples', ...);         // three channels
  test('events survive importDive → getEvents', ...);                  // two events
  test('a dive without events or cells stores NULL blobs', ...);       // a Shearwater dive today
  test('the samples row carries parser_version and dc_family', ...);
  test('getSamples and getEvents read a samples row written by an old build', ...);
    // insert a dive_samples row by raw SQL with only the pre-phase-1 columns:
    // getSamples returns cellPpo2Bar == [] and getEvents returns [].
  // merged builder:
  test('a merged dive keeps the first member\'s vendor and product and joins cellPpo2Bar', ...);
  ```

- [ ] **Step 2: Run them and check they fail.** Run: `flutter test test/data/db/dive_dao_test.dart test/analysis/merge/merged_sample_builder_test.dart`. Expected: FAIL.

- [ ] **Step 3: Implement the interfaces above.** Keep the INSERT column lists and placeholder counts in step.

- [ ] **Step 4: Run all tests.** Run: `flutter analyze && flutter test`. Expected: clean, all pass.

- [ ] **Step 5: Commit and open PR 1.**

  ```bash
  git add lib/data/db/dive_dao.dart lib/analysis/merge test/data/db/dive_dao_test.dart test/analysis/merge
  git commit -m "feat(db): store brand fields, per-cell ppO2 and events with each dive"
  ```

  The PR description says that 0026 must be live before anyone runs this branch signed in, and links the check script.

---

## PR 2 — Sync gate

### Task 5: Keep libdivecomputer rows away from builds that can't handle them

Builds the spec's "sync parameter" for both Sync Rules and Sync Streams, choosing **Sync Streams**: Sync Rules are deprecated, and #208 already moves to Streams. Deploying a changed config makes every client re-sync fully once, so deploy this together with #208.

Why the bailout table is gated too: `EquipmentDao.purgeOrphanedBailoutCarry()` runs at every launch since PR #48. It **hard-deletes** `dive_bailout_carry` rows whose dive is missing locally, and the delete uploads. If an old build received bailout rows for dives it can't see, it would delete them on the server. Checked and harmless without a gate: `dive_annotations`, `dive_cylinders`, `dive_attachments` (the purger only touches attachments whose dive exists) and `dive_merge_links`. Old builds load them by dive id and never act on a missing dive. `dive_computers` is gated because old builds look computers up by serial alone.

**Files:**
- Modify: `infra/powersync-sync-rules.yaml` (the Streams file from #208)
- Create: `lib/sync/cloud/sync_params.dart`
- Modify: `lib/sync/cloud/cloud_sync_coordinator.dart`
- Modify: `lib/data/db/equipment_dao.dart` (`addBailoutCarry`)
- Modify: `infra/README.md` (deploy checklist line)
- Test: `test/sync/cloud/sync_streams_config_test.dart` (from #208), `test/sync/cloud/cloud_sync_coordinator_test.dart`, `test/data/db/dive_bailout_carry_dao_test.dart`

**Interfaces:**
- Consumes: Task 1's `dc_family` columns on `dives`, `dive_samples`, `dive_computers`, `dive_bailout_carry`.
- Produces:
  - `const Map<String, Object> kSyncConnectionParams = {'dc_engines': 1};`. The doc comment says: 1 = "this build reads Shearwater only"; phase 2 sets 2 in the same PR that makes the Subsurface writer skip libdivecomputer dives; builds before phase 1 send nothing.
  - `CloudSyncTarget.connect(PowerSyncBackendConnector connector, {Map<String, Object?>? params})`. `PowerSyncCloudSyncTarget` passes it to `_db.connect(connector:, params:)` (present in powersync 2.1.0). `CloudSyncCoordinator` always passes `kSyncConnectionParams`.
  - Streams config. In `user_data`, the four gated tables get `AND dc_family IS NULL`. A new stream:

    ```yaml
      libdc_dives:
        auto_subscribe: true
        queries:
          - SELECT * FROM dives WHERE owner_id = auth.user_id() AND dc_family IS NOT NULL AND connection.parameter('dc_engines') >= 2
          - SELECT * FROM dive_samples WHERE owner_id = auth.user_id() AND dc_family IS NOT NULL AND connection.parameter('dc_engines') >= 2
          - SELECT * FROM dive_computers WHERE owner_id = auth.user_id() AND dc_family IS NOT NULL AND connection.parameter('dc_engines') >= 2
          - SELECT * FROM dive_bailout_carry WHERE owner_id = auth.user_id() AND dc_family IS NOT NULL AND connection.parameter('dc_engines') >= 2
    ```

  - `addBailoutCarry` fills `dc_family` with `(SELECT dc_family FROM dives WHERE id = ?)` in the INSERT, so a bailout row always shares its dive's stream.

- [ ] **Step 1: Check #208.** If #208 isn't merged, stop and ask Egbert to merge it first. This PR is written against the Streams file.

- [ ] **Step 2: Write the failing tests.**

  ```dart
  // sync_streams_config_test.dart: replace "exactly one owner-scoped query per table" with:
  test('ungated tables have one query in user_data and none in libdc_dives', ...);
  test('dives, dive_samples, dive_computers and dive_bailout_carry have one user_data query with "dc_family IS NULL" and one libdc_dives query with "dc_family IS NOT NULL" and "connection.parameter(\'dc_engines\') >= 2"', ...);
  test('libdc_dives selects only the gated tables', ...);
  // cloud_sync_coordinator_test.dart
  test('connect passes {dc_engines: 1}', ...);       // the recording fake gets the params
  // dive_bailout_carry_dao_test.dart
  test('addBailoutCarry copies the dive\'s dc_family', ...);
    // insert a dives row with dc_family 17 by raw SQL; add a carry; expect its dc_family == 17.
  test('addBailoutCarry on a Shearwater dive leaves dc_family NULL', ...);
  ```

- [ ] **Step 3: Run them and check they fail.** Run: `flutter test test/sync/cloud test/data/db/dive_bailout_carry_dao_test.dart`. Expected: FAIL.

- [ ] **Step 4: Implement the interfaces above.**

- [ ] **Step 5: Run all tests.** Run: `flutter analyze && flutter test`. Expected: clean, all pass.

- [ ] **Step 6: Compile check.** The Streams docs show `connection.parameter()` compared with a row column, but not with a constant. Before asking for a deploy, get the config validated: Egbert pastes it into the PowerSync dashboard editor and runs Validate (without deploying). With Egbert's OK to install an npm package, also compile it locally in the scratchpad with `@powersync/service-sync-rules` at the version the dashboard reports (`SqlSyncRules.fromYaml(text, { defaultSchema: 'public', throwOnError: false })`, expect `errors` empty). If the constant comparison is rejected, use this fallback: `libdc_dives` with `auto_subscribe: false` and the `AND connection.parameter(...)` clauses removed. Phase-2 builds then subscribe with `db.syncStream('libdc_dives').subscribe()`, phase 1 keeps sending the parameter unused, and the config test changes to match. Builds that don't know the stream name never subscribe to it. Pick the fallback only after telling Egbert.

- [ ] **Step 7: Commit and open PR 2.**

  ```bash
  git add infra lib/sync/cloud lib/data/db/equipment_dao.dart test/sync/cloud test/data/db/dive_bailout_carry_dao_test.dart
  git commit -m "feat(sync): keep libdivecomputer rows away from builds that can't handle them"
  ```

- [ ] **Step 8 (Egbert): deploy and check end to end.**
  1. Make sure 0026 is live (Task 1).
  2. Let every device finish syncing, then deploy (with #208 if it isn't deployed yet). Expect one full re-sync per device.
  3. In the SQL editor, insert a fake `dives` row for your account with `dc_family = 999`. Check that it does **not** appear on an installed store build or on a build of this PR. Check that it **does** appear on a debug build with `kSyncConnectionParams` temporarily set to `{'dc_engines': 2}` (or subscribed, with the fallback). Then delete the row in SQL and check that it disappears on the debug build.
  4. Check that sync goes green and the dive count matches on one device.

---

## PR 3 — Brands for computers and Subsurface copies

### Task 6: dive_computers keyed by (vendor, serial)

**Files:**
- Modify: `lib/data/db/equipment_dao.dart`
- Modify: `lib/ui/notifiers/import_notifier.dart` (the `upsertDiveComputer` call)
- Modify: `lib/ui/notifiers/dive_detail_notifier.dart:73` (`getDiveComputerBySerial` → `getDiveComputer(vendor: dive.dcVendor ?? kShearwaterVendor, serial: dive.dcSerial)`), `lib/ui/screens/equipment/dive_computer_detail_screen.dart:40` (`recentImportsForComputer` with the computer's `dcVendor ?? kShearwaterVendor`)
- Test: `test/data/db/equipment_dao_test.dart`, `test/data/db/recent_imports_from_powersync_test.dart`

**Interfaces:**
- Produces:
  - `static String EquipmentDao.diveComputerId(String vendor, int serial)`. Shearwater keeps `'dc_${serial.toRadixString(16)}'` (existing ids). Any other vendor gets `'dc_${slug}_${serial.toRadixString(16)}'`, where `slug` is the vendor in lower case with everything outside `[a-z0-9]` removed.
  - `Future<String> upsertDiveComputer({required String vendor, String? product, required int serial, required int model, int? firmwareVersion, int? family, int? modelCode})`. It looks up with `WHERE serial = ? AND COALESCE(dc_vendor, 'Shearwater') = ?` and writes the four brand columns. It keeps `nickname` on update, as today.
  - `Future<DiveComputer?> getDiveComputer({required String vendor, required int serial})` replaces `getDiveComputerBySerial`.
  - `Future<List<Dive>> recentImportsForComputer({required String vendor, required int serial, int limit = 10})`. For Shearwater it matches `dc_vendor = 'Shearwater' OR dc_vendor IS NULL`, which keeps today's results. For other vendors it matches `dc_vendor = ?`.
  - The import notifier passes `vendor: kShearwaterVendor` and `product: shearwaterProductName(modelFromHardware(hardwareId))`.

- [ ] **Step 1: Write the failing tests.**

  ```dart
  test('same serial under two vendors gives two rows', ...);
  test('a Shearwater computer keeps its dc_<hex> id', ...);
  test('a row written by an old build (dc_vendor NULL) is found by a Shearwater upsert', ...); // raw-SQL insert
  test('a non-Shearwater id carries the vendor slug', ...);       // 'Heinrichs Weikamp', 0x2a → 'dc_heinrichsweikamp_2a'
  test('recentImportsForComputer for Shearwater includes dives with NULL dc_vendor', ...);
  ```

- [ ] **Step 2: Run them and check they fail.** Run: `flutter test test/data/db/equipment_dao_test.dart test/data/db/recent_imports_from_powersync_test.dart`. Expected: FAIL.

- [ ] **Step 3: Implement the interfaces above and update callers.**

- [ ] **Step 4: Run all tests.** Run: `flutter analyze && flutter test`. Expected: clean, all pass.

- [ ] **Step 5: Commit.**

  ```bash
  git add lib test
  git commit -m "feat(equipment): key dive computers by vendor and serial"
  ```

### Task 7: The bootstrap keeps Subsurface's model names and reads serials per brand

The read mapper parses every `Serial` as hex today. Shearwater writes hex, but most upstream parsers write decimal. Ids must not change, because a changed id would duplicate every existing copy on the next bootstrap. So the id keeps today's hex reading, and only the stored `dc_serial` uses the corrected one.

**Files:**
- Create: `packages/subsurface_core/lib/sync/subsurface_git/subsurface_model.dart` (+ barrel export)
- Modify: `packages/subsurface_core/lib/sync/subsurface_git/subsurface_to_ccrlog_mapper.dart`
- Test: `packages/subsurface_core/test/sync/subsurface_git/subsurface_model_test.dart`, the mapper's existing test file in `packages/subsurface_core/test/sync/subsurface_git/`, `test/sync/subsurface_git/bootstrap_importer_test.dart`

**Interfaces:**
- Produces:
  - `const List<String> kMultiWordVendors`: the vendor names with a space in upstream libdivecomputer's `src/descriptor.c` (expected: 'Heinrichs Weikamp', 'Atomic Aquatics', 'Dive Rite', 'Deep Six'; check against the file at upstream master).
  - `({String vendor, String product})? splitSubsurfaceModel(String model)`. It splits on a known multi-word vendor prefix, otherwise on the first space. It returns null for a model with no space or for `'manually added dive'`.
  - `int parseSubsurfaceSerial(String? vendor, String text)`. Shearwater (or a null vendor): hex. Others: decimal, falling back to hex, then 0.
  - `ShearwaterModel shearwaterModelFromProduct(String? product)`: the inverse of Task 2's `shearwaterProductName`, replacing the mapper's private name switch.
  - The mapper's `Dive` gets `dcVendor` / `dcProduct` from `splitSubsurfaceModel` and `dcSerial` from `parseSubsurfaceSerial`. The dive id stays `generateDiveId(int.tryParse(serialText, radix: 16) ?? 0, subsurfaceDiveNumber, start)`.

- [ ] **Step 1: Write the failing tests.**

  ```dart
  test('"Shearwater Petrel 3" splits to Shearwater / Petrel 3', ...);
  test('"Heinrichs Weikamp OSTC 4" splits to Heinrichs Weikamp / OSTC 4', ...);
  test('"manually added dive" and a model without a space give null', ...);
  test('Shearwater serial "B89641E4" parses as hex', ...);   // 0xB89641E4
  test('Divesoft serial "1234567" parses as decimal', ...);  // 1234567
  // mapper
  test('the Petrel fixture maps to vendor Shearwater, product from the model line, dcModel unchanged', ...);
  test('a Divesoft Divecomputer keeps vendor and product, decimal dcSerial, and today\'s id', ...);
    // synthetic lines: model "Divesoft Liberty", keyvalue "Serial" "1234567";
    // expect dcSerial == 1234567, id == generateDiveId(0x1234567, n, t).
  // bootstrap_importer_test.dart
  test('a re-run over a copy stored with the old hex serial imports nothing new', ...);
  ```

- [ ] **Step 2: Run them and check they fail.** Run: `cd packages/subsurface_core && dart test test/sync/subsurface_git`, then `flutter test test/sync/subsurface_git/bootstrap_importer_test.dart`. Expected: FAIL.

- [ ] **Step 3: Implement the interfaces above.** Keep the raw `Serial` text on `_DivecomputerMetadata` next to the parsed value. The bootstrap needs no code change in this task. `importDive` already writes the brand fields (Task 4), and the existing id check catches re-runs.

- [ ] **Step 4: Run all tests.** Run: `cd packages/subsurface_core && dart test`, then `flutter analyze && flutter test`. Expected: all pass.

- [ ] **Step 5: Commit and open PR 3.**

  ```bash
  git add packages/subsurface_core test/sync/subsurface_git
  git commit -m "feat(subsurface): keep model names and per-brand serials from Subsurface copies"
  ```

---

## PR 4 — Shared download shape

### Task 8: The download shape, and Shearwater behind it

One shape for every engine (spec section 6): open, download, and emit a `ConvertedDive` plus the raw blob per dive. The source parses; the notifier only commits. libdivecomputer can't list dives before downloading, and learns the computer's identity during the download. So `canListDives` and `DiveSourceIdentified` exist now, even though Shearwater doesn't use the second one.

**Files:**
- Create: `lib/devices/dive_download_source.dart`
- Create: `lib/devices/shearwater/shearwater_download_source.dart`
- Create: `lib/shearwater/ble/shearwater_link.dart`
- Create: `lib/shearwater/parser/parser_version.dart`
- Modify: `lib/shearwater/ble/shearwater_ble_transport.dart`, `lib/shearwater/ble/mock_ble_transport.dart` (`implements ShearwaterLink`; the mock's `readManifest` gains the ignored optional `lastFingerprint`)
- Test: `test/devices/shearwater_download_source_test.dart`

**Interfaces:**
- Produces:
  - `const int kShearwaterParserVersion = 1;`, documented as "bump whenever the Shearwater reader's output changes (Task 15 adds a guard test)".
  - `abstract interface class ShearwaterLink { Future<DeviceInfo> readDeviceInfo(); Future<List<ManifestEntry>> readManifest({Uint8List? lastFingerprint}); Stream<DownloadEvent> downloadDives(List<ManifestEntry> entries); Future<void> disconnect(); }`
  - `class DcIdentity`: `String vendor`, `String? product`, `int serial`, `int? family`, `int? modelCode`, `int? firmware`, `ShearwaterModel dcModel` (`unknown` outside Shearwater), `int computerModel` (what `dive_computers.model` holds: the Shearwater hardware id), `String importStateKey` (Shearwater: `DeviceInfo.serial`, the existing key), plus `String modelLabel`, `serialLabel`, `firmwareLabel` for the screen. Shearwater's labels are exactly today's text: `model.name`, the hex serial and the firmware string.
  - `class DiveListing`: `int diveNumber`, `int startTimestamp`, `int endTimestamp`, `Uint8List fingerprint`, `String diveId` (the computed id).
  - `sealed class DiveSourceEvent` with:
    - `DiveSourceProgress(int diveIndex, int? totalDives, int diveBytes, int? diveTotalBytes, DiveListing? listing)`
    - `DiveSourceIdentified(DcIdentity identity)`
    - `DiveSourceDive(DiveListing? listing, ConvertedDive converted, Uint8List rawBlob, Uint8List fingerprint, int parserVersion)`
    - `DiveSourceDiveFailed(DiveListing? listing, Object error, StackTrace stack)`
  - `abstract class DiveDownloadSource`: `DcIdentity? get identity`, `bool get canListDives`, `Future<List<DiveListing>> listDives({Uint8List? sinceFingerprint})`, `Stream<DiveSourceEvent> download({List<DiveListing>? selection, Uint8List? sinceFingerprint})`, `Future<void> close()`.
  - `ShearwaterDownloadSource implements DiveDownloadSource` with `static Future<ShearwaterDownloadSource> open(ShearwaterLink link)`. `open` reads the device info, so `identity` is known at once. `canListDives` is true. `download` parses each `DownloadedDive` with `ShearwaterDiveParser(model:)` and `DiveConverter.convert`, exactly as `ImportNotifier.downloadAll` does today. A dive that throws becomes `DiveSourceDiveFailed`, and the stream continues.

- [ ] **Step 1: Write the failing tests.** Use `TraceMockBle('test/fixtures/raw/subsurface2.combined.txt')` with `ShearwaterBleTransport(divePipelineWindow: 1)..connectWithIo(...)`, as `test/shearwater/ble/transport_test.dart` does.

  ```dart
  test('identity comes from the device info', ...);
    // vendor 'Shearwater', product 'Petrel 3', serial 0xB89641E4,
    // importStateKey 'B89641E4', modelLabel 'petrel3', firmwareLabel 'V103 DiveCAN'.
  test('listDives returns the manifest, each with the computed dive id', ...);
  test('download gives the same dives as parsing the transport\'s blobs directly', ...);
    // for each dive in the trace: dive fields equal, SampleCodec.encode outputs equal,
    // rawBlob equals DownloadedDive.data, parserVersion == kShearwaterParserVersion.
  test('a dive that fails to parse yields DiveSourceDiveFailed and the next dive still arrives', ...);
    // a fake ShearwaterLink emitting [garbage, a fixture dive].
  test('the mock transport works through the same source', ...);
  ```

- [ ] **Step 2: Run them and check they fail.** Run: `flutter test test/devices`. Expected: FAIL (no such files).

- [ ] **Step 3: Implement the interfaces above.** No change to `ShearwaterBleTransport`'s behaviour beyond `implements ShearwaterLink`.

- [ ] **Step 4: Run them and check they pass.** Run: `flutter test test/devices test/shearwater`. Expected: PASS.

- [ ] **Step 5: Commit.**

  ```bash
  git add lib/devices lib/shearwater test/devices
  git commit -m "feat(import): one download shape for every engine, Shearwater behind it"
  ```

### Task 9: ImportNotifier on the shared shape, verified on a Petrel 3

**Files:**
- Modify: `lib/ui/notifiers/import_notifier.dart`
- Modify: `lib/ui/screens/import_screen.dart`
- Test: `test/ui/notifiers/import_notifier_test.dart` (and any import-screen widget test under `test/ui/`)

**Interfaces:**
- Consumes: Task 8's `DiveDownloadSource`, `DcIdentity`, `DiveListing`, `DiveSourceEvent`.
- Produces:
  - After connecting (real BLE or mock), the notifier holds one `DiveDownloadSource _source` and no `_realTransport` / `_mockTransport` branching past connect. Scanning and connecting are unchanged.
  - Public API: `DcIdentity? identity` replaces `deviceInfo`. `List<DiveListing> newDives`, `DiveListing? currentEntry` and `downloadAll([List<DiveListing>? subset])` take the listing type.
  - Download loop: `DiveSourceDive` → `_dao.importDive(converted:, rawBlob:, parserVersion: event.parserVersion)`. `DiveSourceDiveFailed` → `_failedCount++`. `DiveSourceIdentified` → `upsertDiveComputer` (unused by Shearwater). The fingerprint is saved under `identity.importStateKey`.
  - The import screen shows byte-identical text, now read from `identity.*Label` and `DiveListing`.

- [ ] **Step 1: Update the tests to the new types.** Change only the types: `deviceInfo` → `identity`, `ManifestEntry` → `DiveListing`. Add:

  ```dart
  test('a failed dive counts as failed and the rest still import', ...);
  test('the fingerprint is saved under identity.importStateKey', ...);
  ```

- [ ] **Step 2: Run them and check they fail.** Run: `flutter test test/ui`. Expected: FAIL (compile).

- [ ] **Step 3: Implement.** Move parsing out of the notifier: it no longer imports `dive_parser.dart` or `dive_converter.dart`.

- [ ] **Step 4: Run all tests.** Run: `flutter analyze && flutter test`. Expected: clean, all pass.

- [ ] **Step 5: Commit.**

  ```bash
  git add lib/ui test/ui
  git commit -m "refactor(import): run the import screen on the shared download shape"
  ```

- [ ] **Step 6 (Egbert): Petrel 3 check.** On a build of this branch, compare with the current store build:
  1. Connect: same model, serial and firmware text.
  2. The manifest lists the same new dives.
  3. Download two dives: both appear with the same profile as on the store build.
  4. Run a forced full re-scan: no duplicates, same counts as the store build shows.
  5. The next normal scan shows nothing new.

- [ ] **Step 7: Open PR 4.** The description includes the Step 6 results.

---

## PR 5 — In-place refresh (spec section 7a, Shearwater)

### Task 10: Refresh rules and the Subsurface-copy matcher (pure)

**Files:**
- Create: `lib/data/import/refresh_policy.dart`
- Create: `lib/data/import/same_dive_matcher.dart`
- Create: `lib/data/import/cylinder_remap.dart`
- Test: `test/data/import/refresh_policy_test.dart`, `test/data/import/same_dive_matcher_test.dart`, `test/data/import/cylinder_remap_test.dart`

**Interfaces:**
- Produces:
  - `bool refreshMayWrite({required int storedVersion, required bool storedIsLibdc, required int incomingVersion, required bool incomingIsLibdc})`. True when `storedVersion == kSubsurfaceImportedParserVersion`, or when the engines match and `incomingVersion > storedVersion`. Otherwise false. A row's engine is libdivecomputer exactly when `dc_family` is set.
  - `bool isUsableParse(ConvertedDive c)`: `c.samples.sampleCount > 0 && c.dive.duration > Duration.zero`.
  - `class StoredDiveKey`: `String id`, `String? dcVendor`, `int dcSerial`, `int startTime` (seconds), `int parserVersion`, `int? dcFamily`. Built from a `dives` row.
  - `String? effectiveVendor(String? dcVendor, int parserVersion)`: returns `dcVendor`. A NULL vendor reads as `kShearwaterVendor` on a download and as null ("any brand") on a Subsurface copy from before phase 1.
  - `Set<int> subsurfaceSerialForms(String vendor, int serial)`. Shearwater: `{serial}`. Others: `{serial, int.tryParse('$serial', radix: 16)}` (the old hex reading of a decimal serial, Task 7), dropping a null.
  - `const int kSameDiveWindowSeconds = 60;`
  - `List<StoredDiveKey> findSameDive({required String vendor, required int serial, required int startTimeSeconds, required String excludeId, required Iterable<StoredDiveKey> stored})`. It matches when `effectiveVendor` equals `vendor` (or is null), `dcSerial` is in `subsurfaceSerialForms(vendor, serial)`, `|startTime − startTimeSeconds| ≤ 60` and `id != excludeId`. Soft-deleted rows count, so a deleted copy keeps a download hidden, as a deleted download does today.
  - `Map<int, String?> remapCylinderRows({required List<DiveGasMix> oldMixes, required List<DiveGasMix> newMixes, required Map<int, String?> rowsByIndex})`. It returns the final rows: index → cylinder id. Each row at a valid old index follows its mix to the new index with the same O2 and He, preferring the same `isDiluent` and then the lowest unused index. A row whose mix is gone moves to the next unused negative index (-1, -2, …), meaning "unassigned". A row already at a negative index stays.

- [ ] **Step 1: Write the failing tests.**

  ```dart
  // refresh_policy_test.dart
  test('a Subsurface copy is always refreshed', ...);                 // stored -1, incoming 1 → true
  test('a higher version of the same engine refreshes', ...);         // 1 → 2 → true
  test('the same or a lower version never refreshes', ...);           // 2 → 2, 3 → 2 → false
  test('another engine never refreshes a download', ...);             // Shearwater 1 vs libdc 5 → false
  test('an empty parse is not usable', ...);                          // 0 samples; 0 s duration
  // same_dive_matcher_test.dart
  test('a copy 59 s apart with the same hex serial matches', ...);
  test('61 s apart does not match', ...);
  test('a pre-phase-1 copy (NULL vendor) matches any brand', ...);
  test('a download with NULL vendor counts as Shearwater', ...);
  test('a non-Shearwater copy stored with the old hex reading matches', ...); // stored 0x1234567, serial 1234567
  test('the incoming id itself is excluded', ...);
  test('two copies in the window both come back', ...);
  // cylinder_remap_test.dart
  test('a reordered gas list moves each cylinder with its mix', ...);
  test('a mix that is gone leaves its cylinder unassigned at -1', ...);
  test('two mixes with the same O2/He keep their diluent and bailout cylinders apart', ...);
  test('an unassigned row stays unassigned and keeps its index', ...);
  ```

- [ ] **Step 2: Run them and check they fail.** Run: `flutter test test/data/import`. Expected: FAIL.

- [ ] **Step 3: Implement the interfaces above.** No database or Flutter imports.

- [ ] **Step 4: Run them and check they pass.** Same command. Expected: PASS.

- [ ] **Step 5: Commit.**

  ```bash
  git add lib/data/import test/data/import
  git commit -m "feat(import): refresh rules, Subsurface-copy matcher and cylinder remap"
  ```

### Task 11: DiveDao refreshes in place

**Files:**
- Modify: `lib/data/db/dive_dao.dart`
- Modify: `lib/data/db/equipment_dao.dart` (`removeDiveCylinder`)
- Test: `test/data/db/dive_refresh_test.dart`

**Interfaces:**
- Consumes: Task 10's functions. Task 3's `DiveImportMarks` and `match_candidates_json`.
- Produces:
  - `enum ImportOutcome { inserted, insertedFlagged, refreshed, unchanged, rejected }`
  - `Future<ImportOutcome> importDive({required ConvertedDive converted, required Uint8List rawBlob, required int parserVersion, bool matchSubsurfaceCopies = true})`. In order:
    1. If the id exists: refresh when `refreshMayWrite` and `isUsableParse` allow, `rejected` when only `isUsableParse` fails, `unchanged` otherwise.
    2. Else, if `matchSubsurfaceCopies`: query `dives` with `start_time BETWEEN t-60 AND t+60` and run `findSameDive`. With one match, handle as step 1 under the match's id. With several, insert as new with `match_candidates_json` = their ids and return `insertedFlagged`.
    3. Else insert as today and return `inserted`.

    Whenever the dive is stored or kept, the raw blob is written under the stored id. If that local write throws, upsert `DiveImportMarks(diveId, rawBlobMissing: true)` and return the outcome anyway. A later successful write clears the flag.
  - `Future<ImportOutcome> refreshFromRawBlob({required String diveId, required ConvertedDive converted, required int parserVersion})`: step 1 for a stored id. It doesn't take the download's serial or dive number, and doesn't write a raw blob.
  - Refresh write: one `_ps.writeTransaction`.
    - `UPDATE dives` sets the reader columns from spec section 7a (times, duration, depth, dive mode, deco model and GF, atmospheric pressure, water density, log version, `dc_model`, `dc_firmware`, the four brand fields, sample interval, gas mixes, tanks, calibration, the three stack times, `parser_version`), plus `dc_serial` / `dc_dive_number` only from a download. It also sets `owner_id = COALESCE(owner_id, ?)` and `version = version + 1`.
    - It never touches `id`, `imported_at`, `deleted_at`, `subsurface_uploaded_at` or `match_candidates_json`.
    - `dive_samples` gets every blob, `sample_count`, `parser_version`, `dc_family`, `updated_at` and `version + 1`, with `created_at` kept. It is inserted if missing.
    - `dive_cylinders` rows are rewritten from `remapCylinderRows`. A moved row is soft-deleted at its old id and written (or revived) at `'$diveId:$newIndex'` with its `cylinder_id`.
  - `Future<List<StoredDiveKey>> storedDiveKeys()` (all rows, deleted included).
  - `Future<Set<String>> alreadyDownloadedAmong(List<({String diveId, int startTimeSeconds})> listings, {required String vendor, required int serial})`. It returns the listing ids to hide from "new": the id exists, or `findSameDive` finds exactly one match with `parser_version >= 0` (a copy refreshed earlier). It leaves out ids marked `rawBlobMissing`, so the next download stores the blob again (spec section 6).
  - `Future<List<String>> matchCandidates(String diveId)`.
  - `Future<void> EquipmentDao.removeDiveCylinder(String diveId, int gasMixIndex)`: a soft delete.

- [ ] **Step 1: Write the failing tests** (`dive_refresh_test.dart`, real PowerSync via `openDiveDaoForTest`; fixture dives from `test/fixtures/dives/`).

  ```dart
  test('a higher version refreshes under the same id and keeps annotation, attachments, merge link, bailout carry and cylinders', ...);
  test('the same version only stores the raw blob', ...);               // unchanged; dives.version unchanged
  test('a lower version changes nothing', ...);
  test('an empty parse leaves the stored dive as it was', ...);         // rejected
  test('a refresh keeps deleted_at, imported_at and subsurface_uploaded_at', ...);
  test('a refresh heals a NULL owner_id but keeps a set one', ...);
  test('a download refresh takes the download\'s dc_serial and dc_dive_number; refreshFromRawBlob keeps them', ...);
  test('a Subsurface copy 30 s apart is refreshed under its own id', ...);  // raw blob stored under the copy id
  test('an already refreshed copy only gets the raw blob', ...);
  test('two matching copies: inserted as new and flagged with both ids', ...);
  test('matchSubsurfaceCopies: false never touches a copy', ...);
  test('cylinders follow their mix when the refreshed gas list is reordered', ...);
  test('a cylinder whose mix is gone survives as unassigned', ...);
  test('refreshed rows bump version on dives and dive_samples', ...);
  test('alreadyDownloadedAmong hides a refreshed copy but not an unrefreshed one', ...);
  test('a failed raw-blob write marks the dive and alreadyDownloadedAmong lists it again', ...);
  ```

  Make an "older" stored dive by importing a fixture at `parserVersion: 1`, then importing the same fixture at 2.

- [ ] **Step 2: Run them and check they fail.** Run: `flutter test test/data/db/dive_refresh_test.dart`. Expected: FAIL.

- [ ] **Step 3: Implement the interfaces above.** Read `gas_mixes_json` with `DiveGasMix.fromJson`. Keep `diveExists` and `existingDiveIdsAmong`, since other code uses them. `dive_derived_stats` needs no change: `statistics_notifier.dart:79` already recomputes when the dive's `parser_version` differs from the cached row's. To keep the app compiling until Task 12, map `inserted`, `insertedFlagged` and `refreshed` to `true` in `DaoBootstrapDataSource.importDive` and in the notifier's call.

- [ ] **Step 4: Run them and check they pass.** Run: `flutter test test/data/db`. Expected: PASS (the existing `dive_dao_test` 'dedup' test now expects `ImportOutcome.unchanged`).

- [ ] **Step 5: Commit.**

  ```bash
  git add lib/data/db test/data/db
  git commit -m "feat(import): refresh a dive's imported data in place"
  ```

### Task 12: Callers: import flow, bootstrap, Sentry and what the diver sees

**Files:**
- Create: `lib/data/import/import_problem_reporter.dart`
- Modify: `lib/ui/notifiers/import_notifier.dart`
- Modify: `lib/sync/subsurface_git/bootstrap_importer.dart`
- Modify: `lib/ui/notifiers/dive_annotations_notifier.dart`, `lib/ui/widgets/dive_cylinders_section.dart`
- Modify: `lib/ui/screens/dive_detail_screen.dart` (the flag banner)
- Test: `test/ui/notifiers/import_notifier_test.dart`, `test/sync/subsurface_git/bootstrap_importer_test.dart`, `test/ui/widgets/` (a widget test for the cylinder section and the banner)

**Interfaces:**
- Consumes: Task 11's `ImportOutcome`, `alreadyDownloadedAmong`, `storedDiveKeys`, `matchCandidates`, `removeDiveCylinder`. Task 10's `findSameDive`.
- Produces:
  - `typedef ImportProblemReporter = void Function(Object error, StackTrace? stack, String where);` and `void reportImportProblemToSentry(Object error, StackTrace? stack, String where)`. It calls `Sentry.captureException` with tag `import.where`, and no serial, dive data or user data. The notifier and bootstrap take an optional `ImportProblemReporter`, defaulting to the Sentry one (the `analyzer_session.dart` pattern).
  - Notifier: `inserted`, `insertedFlagged` and `refreshed` count as downloaded and move the saved fingerprint, as `true` did before. `unchanged` counts as neither. `rejected` and `DiveSourceDiveFailed` count as failed and are reported (`where: 'download'`). The manifest filter calls `alreadyDownloadedAmong` instead of `existingDiveIdsAmong`.
  - Bootstrap: `BootstrapDataSource.existingDiveKeys()` becomes `storedDiveKeys()`. A folder is skipped when its id is stored, or when the dive has a vendor and `findSameDive` returns anything. A dive without a vendor (manual) keeps today's exact `(dcSerial, startTime)` check. The importer calls `importDive(..., matchSubsurfaceCopies: false)` and adds what it imports to its in-memory key list.
  - `DiveAnnotationsNotifier.unassignedCylinders`: the `cylinderByMix` entries with a negative index. `removeUnassignedCylinder(int index)` calls `removeDiveCylinder`. `DiveCylindersSection` lists them under the mixes: cylinder label, "No longer matches a gas on this dive", and a remove button.
  - Dive detail: when `matchCandidates` isn't empty, a banner says "This dive may be the same as N other dives in your log." with a link to each candidate (date and number). No dismiss in phase 1; folding duplicate pairs is a follow-up in the spec.

- [ ] **Step 1: Write the failing tests.**

  ```dart
  // import_notifier_test.dart
  test('a refreshed dive counts as downloaded and moves the fingerprint', ...);
  test('an unchanged dive is not counted', ...);
  test('a rejected dive counts as failed and is reported once', ...);   // fake reporter
  test('the manifest hides a copy refreshed by an earlier download', ...);
  // bootstrap_importer_test.dart
  test('a Subsurface dive 40 s from a stored Petrel download is skipped', ...);
  test('a manual dive keeps the exact serial and start-time check', ...);
  test('the importer never refreshes a stored dive', ...);              // matchSubsurfaceCopies: false
  // widget tests
  test('an unassigned cylinder is listed and can be removed', ...);
  test('a flagged dive shows the banner with links to its candidates', ...);
  ```

- [ ] **Step 2: Run them and check they fail.** Run: `flutter test test/ui test/sync/subsurface_git`. Expected: FAIL.

- [ ] **Step 3: Implement the interfaces above.**

- [ ] **Step 4: Run all tests.** Run: `flutter analyze && flutter test`. Expected: clean, all pass.

- [ ] **Step 5: Commit.**

  ```bash
  git add lib test
  git commit -m "feat(import): downloads refresh Subsurface copies; the bootstrap skips downloaded dives"
  ```

### Task 13: A real Subsurface copy next to a replay of the same dives

**Files:**
- Create: `test/fixtures/subsurface_petrel3/` (Subsurface folders for the dives in `test/fixtures/raw/subsurface2.combined.txt`, plus a README)
- Test: `test/data/import/subsurface_copy_refresh_test.dart`

**Interfaces:**
- Consumes: `SubsurfaceBootstrapImporter` with `DaoBootstrapDataSource`, `ShearwaterDownloadSource` over `TraceMockBle`, and `DiveDao.importDive`.

- [ ] **Step 1: Copy the fixture.** From Egbert's local Subsurface repo `/Users/egbert/Dev/CCRLog/ss_git`, copy the dive folders whose start times match the trace's dives (serial `B89641E4`; print the trace's start times with a throwaway test) and the `00-Subsurface` top-level file. Anonymise them the way `packages/subsurface_core/test/fixtures/subsurface/README.md` describes: other people's names in `buddy` lines and notes become made-up names, and nothing else changes. The README lists the dives and says where they came from. If the folders aren't in `ss_git`, stop and ask Egbert.

- [ ] **Step 2: Write the failing test.**

  ```dart
  test('download after bootstrap: no duplicates, copies refreshed under their ids, user data kept', ...);
    // 1. bootstrap the fixture into a test PowerSync db;
    // 2. add a note and a buddy, a dive_cylinders row and a bailout carry to one copy;
    // 3. download every dive in the trace through ShearwaterDownloadSource → importDive;
    // expect: dive count == number of fixture dives; every copy's id unchanged;
    // parser_version == kShearwaterParserVersion; raw blob stored under the copy id;
    // the note, buddy, cylinder and bailout carry still attached; samples equal the download's.
  test('downloading everything again changes nothing', ...);   // all ImportOutcome.unchanged
  test('a bootstrap after the downloads imports nothing', ...); // divesImported == 0
  ```

- [ ] **Step 3: Run it.** Run: `flutter test test/data/import/subsurface_copy_refresh_test.dart`. Expected: PASS. If it fails, fix the cause in Task 10–12 code, not in the test. In particular, if Subsurface's start differs by more than 60 s, tell Egbert instead of widening the window.

- [ ] **Step 4: Commit.**

  ```bash
  git add test/fixtures/subsurface_petrel3 test/data/import/subsurface_copy_refresh_test.dart
  git commit -m "test(import): refresh Subsurface copies from a replayed Petrel 3 download"
  ```

### Task 14: Check on a real Petrel 3 and open PR 5

- [ ] **Step 1: Run all tests.** Run: `flutter analyze && flutter test && (cd packages/subsurface_core && dart test)`. Expected: clean, all pass.

- [ ] **Step 2 (Egbert): Petrel 3 check, on a test account first.**
  1. Sign in with a test account and run the Subsurface bootstrap.
  2. Annotate one bootstrapped dive.
  3. Download from the Petrel 3. Expected: no duplicates, and the annotated dive keeps its note and now shows the downloaded profile.
  4. Run a forced full re-scan. Expected: nothing new.
  5. Repeat on your own account.

- [ ] **Step 3: Open PR 5.** The description lists the Step 2 results and says the spec's follow-up still applies: duplicate pairs created before this PR aren't folded.

---

## PR 6 — Shearwater reader v2 and background re-parse

### Task 15: The reader emits events and brand fields; the version starts counting

**Files:**
- Modify: `packages/subsurface_core/lib/shearwater/parser/dive_converter.dart`
- Modify: `lib/shearwater/parser/dive_parser.dart` (set `rawType: infoEventTagLog` on bookmarks)
- Modify: `lib/shearwater/parser/parser_version.dart` (`kShearwaterParserVersion = 2`)
- Create: `test/shearwater/parser/reader_output_guard_test.dart`
- Test: `test/shearwater/parser/dive_converter_test.dart`

**Interfaces:**
- Produces:
  - `DiveConverter.convert` sets `dcVendor: kShearwaterVendor` and `dcProduct: shearwaterProductName(dcModel)`, and `ConvertedDive.events = parsed.events`.
  - `kShearwaterParserVersion = 2`. Its doc comment lists the history: 1 = before phase 1; 2 = events and brand fields.
  - The guard test pins `kShearwaterParserVersion` plus one SHA-256 per fixture `test/fixtures/dives/dive_711.bin`…`dive_718.bin`. The hash covers the dive's fields (`toJson` of mixes and tanks plus every scalar field, in a fixed order), the raw bytes of every sample array (not the zlib output, which can differ between zlib builds), and every event field. On mismatch it fails with "Shearwater reader output changed: bump kShearwaterParserVersion and update these digests".

- [ ] **Step 1: Write the failing tests.**

  ```dart
  test('converted Shearwater dives carry vendor Shearwater and the product name', ...);  // fixture 711: 'Petrel 3'
  test('a bookmark in the log becomes a stored event', ...);  // the fixture with a tag-log event; if none has one, a synthetic ParsedDive
  test('reader output matches the digests for this version', ...);
  ```

- [ ] **Step 2: Run them and check they fail.** Run: `flutter test test/shearwater/parser`. Expected: FAIL.

- [ ] **Step 3: Implement.** Generate the digests from the new output, check by eye that only events and brand fields changed compared with `main`, and paste them in.

- [ ] **Step 4: Run all tests.** Run: `flutter analyze && flutter test && (cd packages/subsurface_core && dart test)`. Expected: clean, all pass. Existing Shearwater tests pass unchanged, except for assertions on the new fields.

- [ ] **Step 5: Commit.**

  ```bash
  git add packages/subsurface_core/lib/shearwater lib/shearwater test/shearwater
  git commit -m "feat(shearwater): store events and brand fields; reader version 2"
  ```

### Task 16: Background re-parse after a reader update

**Files:**
- Create: `lib/data/import/shearwater_reparser.dart`
- Modify: `lib/data/db/dive_dao.dart` (`reparseCandidates`)
- Modify: `lib/main.dart` (start it after the cloud sync coordinator)
- Test: `test/data/import/shearwater_reparser_test.dart`

**Interfaces:**
- Consumes: `DiveDao.refreshFromRawBlob` and `getRawBlob`, `DiveImportMarks`, `kShearwaterParserVersion`, `ImportProblemReporter`.
- Produces:
  - `Future<List<({String id, int dcModel, int dcSerial, int dcDiveNumber})>> DiveDao.reparseCandidates(int belowVersion)`: the PowerSync side of the candidate query below. The reparser intersects it with Drift `dive_raw_blobs` and `dive_import_marks`.
  - `class ShearwaterReparser({required DiveDao diveDao, required AppDatabase drift, required ImportProblemReporter report, required Future<bool> Function() waitUntilSynced})` with `Future<({int refreshed, int failed, int skipped})> run()`.
  - Candidates are `dives` rows with `dc_family IS NULL AND parser_version < kShearwaterParserVersion AND deleted_at IS NULL`, that have a local raw blob, and no `DiveImportMarks.reparseFailedVersion == kShearwaterParserVersion`. Copies (-1) with a raw blob are included.
  - Per dive:
    1. Parse with `ShearwaterDiveParser(model: ShearwaterModel.values[row.dc_model])` and convert with the stored `dc_serial` and `dc_dive_number`. Run the parse and conversion inside `Isolate.run`.
    2. Call `refreshFromRawBlob`. Each dive is its own transaction, so an interrupted run carries on next launch.
    3. If the parse throws or the outcome is `rejected`: set `reparseFailedVersion = kShearwaterParserVersion` and report (`where: 'reparse'`).
  - `waitUntilSynced`:
    - Signed in: completes `true` once `PowerSyncDatabase.statusStream` shows `connected && !downloading` with `lastSyncedAt` after the reparser started, or `false` after 2 minutes. On `false`, `run()` returns without touching anything, and it tries again next launch.
    - Signed out: completes `true` at once.
  - `main.dart` starts `run()` unawaited after `CloudSyncCoordinator.start()`, catching and reporting errors. It must never block launch.

- [ ] **Step 1: Write the failing tests.**

  ```dart
  test('refreshes every older Shearwater dive with a local raw blob to the current version', ...);
  test('skips dives without a raw blob, deleted dives and libdivecomputer dives', ...);
  test('a blob that fails to parse is reported once and skipped on the next run', ...);
  test('an interrupted run carries on: a second run refreshes only what is left', ...);
  test('nothing runs when waitUntilSynced returns false', ...);
  test('keeps annotations, cylinders and the id', ...);
  ```

- [ ] **Step 2: Run them and check they fail.** Run: `flutter test test/data/import/shearwater_reparser_test.dart`. Expected: FAIL.

- [ ] **Step 3: Implement the interfaces above.**

- [ ] **Step 4: Run all tests.** Run: `flutter analyze && flutter test && (cd packages/subsurface_core && dart test)`. Expected: clean, all pass.

- [ ] **Step 5: Commit.**

  ```bash
  git add lib/data/import/shearwater_reparser.dart lib/data/db/dive_dao.dart lib/main.dart test/data/import/shearwater_reparser_test.dart
  git commit -m "feat(import): re-parse stored Shearwater dives after a reader update"
  ```

- [ ] **Step 6 (Egbert): Petrel 3 check.**
  1. On the device that downloaded your dives, start a build of this branch.
  2. After the first sync, check that dives with bookmarks show the same profile and that a second device receives the refreshed dives.
  3. Download one new dive.
  4. Check that the next launch re-parses nothing.

- [ ] **Step 7: Open PR 6.**

---

## Before phase 2 starts

- PR 2's config is deployed, and the fake-row check passed.
- Phase 2 sets `kSyncConnectionParams` to `{'dc_engines': 2}` (or subscribes to `libdc_dives`) in the same PR that makes the Subsurface writer skip dives with `dc_family` set.
- libdivecomputer dives use `refreshMayWrite` with their own counter, and `DcIdentity` / `DiveSourceIdentified` for identity.

---

## Changes made during execution (2026-11-16)

The six PRs are #216 (PR 1), #224 (PR 2), #217 (PR 3), #218 (PR 4), #222 (PR 5) and #223 (PR 6). Where this plan and the code differ, the code and this list are what was decided. The reviews below found each issue against real code or a reproduction.

- **PR 1, the guard.** `keep_newer_parse()` stays on `dives`. `dive_samples` has its own `keep_newer_samples()`, which also refuses a same-version (or version-omitted) change to any blob or `sample_count` when the stored version is >= 0. Builds before phase 1 never send `dive_samples.parser_version`, so their upserts would otherwise replace refreshed profiles. The two can't share one function, because PL/pgSQL resolves `new.<field>` at parse time. The check script asserts its own results.
- **PR 1, deploy order.** 0026 must be live before PR 1 is *merged*, not only before this branch runs. Without it, every build from `main` stalls its uploads on PGRST204 until the migration lands.
- **PR 3 (Task 7), serials.** In phase 1, Subsurface copies keep storing the legacy hex reading in `dc_serial`. Installed builds key copies by that reading in `RemoteSnapshot` and the bootstrap, so a decimal value would make them overwrite the original Divecomputer file on Subsurface Cloud. The per-brand reading is exposed on the mapper output (`brandSerial`) and used only for matching. Every serial-keyed match uses `subsurfaceSerialForms(vendor, serial)` from `subsurface_core`; Task 10 imports it instead of defining its own. The bootstrap writes a copy's annotation only when it inserted the dive.
- **PR 4, fingerprints (deferred to phase 2).** The shape needs `sinceFingerprint` up front. libdivecomputer only learns the serial at DEVINFO, inside `dc_device_foreach`, and newest-first engines need "keep the first dive's fingerprint, only on a clean finish". So phase 2 moves fingerprint lookup and saving into the source, for example as a `FingerprintStore`, or as a final event that carries the fingerprint to keep.
- **PR 5 (Task 10), matching.** `effectiveVendor(null, v >= 0)` is Shearwater. `findSameDive` takes `int? diveNumber`: when the incoming dive is a download, a stored download (or refreshed copy) matches only with the same dive number. That rule tells apart two short dives from one computer. A candidate with download data is decisive over unrefreshed copies in the window. `remapCylinderRows` keeps a row at its index when the same mix is still there.
- **PR 5 (Task 11), start time.** A refresh never changes `start_time`; `end_time` becomes the stored start plus the incoming duration. The Subsurface writer and every installed build identify a pushed dive by `(serial, start_time)`, and nothing reads `subsurface_uploaded_at`. A refreshed copy therefore keeps Subsurface's start time, a few seconds off the Petrel's at most. Spec 7a's column list is amended accordingly.
- **PR 5 (Task 11), raw blobs and the rest.**
  - A Subsurface copy (-1) or an empty blob never writes a raw blob.
  - `dc_firmware` and `dc_product` are written with `COALESCE`.
  - A change to `dc_family` also moves the dive's `dive_bailout_carry` rows.
  - Merged dives are remapped against the group's merged gas list, but only when the group has two or more live members.
  - An unchanged gas list skips the remap.
- **PR 5 (Task 12), callers.**
  - Sentry gets only the error type and the stack (`redactImportError`). `SqliteException` text carries the statement's parameters.
  - A rejected dive is reported as `UnusableParse`.
  - The dive screen saves only the cylinder assignments changed in that session.
  - After an import that refreshed dives, View dives pops back to the list through the unsaved-changes guards.
- **PR 6 (Task 16), the re-parse.**
  - It only counts non-empty raw blobs; old installs have empty rows for copies.
  - It captures the sync baseline before `CloudSyncCoordinator.start()` and compares whole seconds, because PowerSync's `lastSyncedAt` has no sub-second part.
  - It starts inside Sentry's `appRunner`.
  - It marks a dive only on a parse failure, a bad identity column or `rejected`. A write error stops the run unmarked.
  - "Reset local data" clears only the failure marks.
- **PR 6 (Task 15).** `EventCodec.encode` rejects out-of-range fields. The parser drops a tag-log value above int32, a bounded divergence from libdc that a re-parse can recover. A ninth guarded input with two bookmarks makes the guard see events. Version 1 had been written while the reader's output changed (2026-04-28 and 2026-05-06), so very old dives change in more than events and brand fields.

### Before phase 2, in addition to the list above

- The fingerprint ownership change from PR 4.
- `dc_family` must be write-once per dive id. Otherwise, the dive, its samples and its carry rows must move between streams in one transaction.
- `ArgumentError` from the codecs inside `_encodedSamples` is treated as a write error. A libdivecomputer engine should mark the dive instead.
- On an engine mismatch, `unchanged` still writes the incoming blob under the other engine's row.
- Gated libdivecomputer downloads store decimal serials while copies keep hex. That breaks three things:
  - equipment lookups;
  - the serial shown on the dive screen;
  - the merge validator's equal-serial rule.
- The future server-side Subsurface sync must not use `updated_at` or `version` alone to decide what needs pushing.
