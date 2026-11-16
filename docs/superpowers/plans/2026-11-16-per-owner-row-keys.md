# Per-owner row keys Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Two Anchorline accounts can own rows with the same id in every synced table and both sync. A 42501 on the user's own row is loud instead of silent, and queued edits never cross an account switch.

**Architecture:** Migration 0027 re-keys every synced table by `(owner_id, id)` and makes the child foreign keys composite. 0022 and 0024 scope their deletes by owner. A local Postgres dry run proves it. The PowerSync upload connector reports 42501s once to Sentry, sets aside PATCHes whose local row belongs to another account, and the Sync tab shows "Upload blocked by the server".

**Tech Stack:** Postgres 17 SQL (Supabase), bash, Docker `postgres:17-alpine` (already local), Dart/Flutter, `powersync` 2.1.0, `postgrest` 2.7.0, `sentry_flutter`.

**Spec:** `docs/superpowers/specs/2026-11-16-per-owner-row-keys-design.md`

## Global Constraints

- Branch `fix/per-owner-row-keys`, based on #233's branch `fix/backfill-keep-other-account-uploads` (commit d163d19). Rebase onto `main` once #233 merges.
- Every migration statement is idempotent (`supabase/README.md`); `./supabase/lint_migrations.sh` must print `OK`.
- The 16 synced tables, exactly: `dive_annotations, cylinders, oxygen_cells, scrubber_sessions, pressure_mappings, dive_cylinders, dive_computers, dives, dive_samples, dive_attachments, dive_bailout_carry, dive_plans, dive_merge_links, gas_analyses, user_acknowledgements, open_blends`.
- The connector keeps calling `upsert(data)` with no `onConflict`.
- Sentry gets no ids, owner or message text: only tags `sync.table`, `sync.op`, `sync.sqlstate`, through `captureRedactedException` (`lib/diagnostics/sentry_redaction.dart`).
- Sync tab copy, verbatim: label `🔴 Upload blocked by the server`; helper `The server refused a change. It uploads by itself once the server is fixed.`
- Don't `dart format` whole files (main isn't format-clean); match the surrounding style by hand.
- Everything in git is English. Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Never deploy anything to Supabase or PowerSync. Egbert deploys.

## Review Focus

1. A Sentry reporter that throws must not change what the upload does (the op is still rethrown, and nothing is quarantined). Test in Task 3.
2. The schema-cache window: a 42P10 after the migration is retried, never quarantined and never reported. Test in Task 3.
3. Offline with a 42501 still in `uploadError`: the label reads "🔴 Offline", not blocked. Test in Task 5.
4. No session (`currentSession == null`): a PATCH uploads as before and the local row is never read. Test in Task 4.
5. Fresh-project recreate: 0001–0027 on an empty database, applied twice, ends with the same schema. Covered by the Task 1 runner, which always applies everything from scratch, twice.

---

### Task 1: Migration 0027, owner-scoped deletes, dry-run harness

**Files:**
- Create: `supabase/dry_run/run.sh`
- Create: `supabase/dry_run/stub/supabase_stub.sql`
- Create: `supabase/dry_run/stub/pg_cron.control`, `supabase/dry_run/stub/pg_cron--1.0.sql`
- Create: `supabase/dry_run/checks/0027_per_owner_row_keys_check.sql`
- Create: `supabase/dry_run/scenarios/0027_guard_setup.sql`, `supabase/dry_run/scenarios/0027_guard_assert.sql`
- Create: `supabase/migrations/0027_per_owner_row_keys.sql`
- Modify: `supabase/migrations/0022_delete_my_account.sql` (the two deletes at lines 53–57, plus the header comment)
- Modify: `supabase/migrations/0024_purge_unconfirmed_users.sql` (the two deletes at lines 53–57, plus the header comment)
- Modify: `supabase/README.md` (new "Before deploying 0027" section; the "Deleting an account on request" SQL in step 4)

**Interfaces:**
- Produces: `supabase/dry_run/run.sh` (no arguments, exit 0 = pass). Later migrations add a `checks/NNNN_*_check.sql`.
- Produces: constraint names `dive_samples_owner_dive_fkey`, `dive_bailout_carry_owner_dive_fkey`, `dive_bailout_carry_owner_cylinder_fkey`, `dive_merge_links_owner_dive_fkey`.

- [ ] **Step 1: Write the Supabase stub**

`stub/supabase_stub.sql`, idempotent (DO blocks for roles):
- roles `anon`, `authenticated` (nologin), `service_role` (nologin, bypassrls);
- schema `auth`; `auth.users (id uuid primary key, email text, email_confirmed_at timestamptz, created_at timestamptz not null default now())`; `auth.audit_log_entries (id uuid primary key default gen_random_uuid(), payload jsonb)`;
- `auth.uid()` returns `nullif(current_setting('request.jwt.claims', true)::json->>'sub', '')::uuid`;
- `grant usage on schema auth` and `execute on auth.uid()` to anon, authenticated, service_role.

`pg_cron.control` (`default_version = '1.0'`, `schema = cron`, `relocatable = false`) and `pg_cron--1.0.sql`: tables `cron.job (jobid bigserial primary key, jobname text unique, schedule text, command text)` and `cron.job_run_details (runid bigserial primary key, jobid bigint, end_time timestamptz)`; functions `cron.schedule(text, text, text) returns bigint` (upsert by jobname) and `cron.unschedule(text) returns boolean`.

- [ ] **Step 2: Write `run.sh`**

`set -euo pipefail`. Start `postgres:17-alpine` detached on port 55433 with `POSTGRES_PASSWORD=dryrun` and `--rm`, under a unique container name. `trap` removes it on exit. Copy the two pg_cron files into `/usr/local/share/postgresql/extension/` with `docker cp`, then wait for `pg_isready`. Then:
1. Database `dryrun_main`: stub, then every `supabase/migrations/*.sql` in order, each `psql -v ON_ERROR_STOP=1 --single-transaction -f`. Then all of them a second time (idempotency). Then each `checks/*_check.sql` the same way.
2. Database `dryrun_guard`: stub, every migration numbered below 0027, `scenarios/0027_guard_setup.sql`, then 0027, which must FAIL (non-zero exit; the runner inverts it), then `scenarios/0027_guard_assert.sql`.

Print `✓ dry run passed` at the end. `checks/` may be empty. If `scenarios/0027_guard_setup.sql` is absent, skip step 2 and print a notice.

- [ ] **Step 3: Run the harness before any 0027 file exists**

Run: `supabase/dry_run/run.sh`. Expected: 0001–0026 apply twice with no error, and the guard step is skipped with its notice. This proves the stub.

- [ ] **Step 4: Write the check and the guard scenarios**

`checks/0027_per_owner_row_keys_check.sql` runs `begin; … rollback;`, so it leaves nothing behind. Every assertion is a DO block that does `raise exception` on failure. As `postgres`, insert `auth.users` A = `00000000-0000-0000-0000-00000000000a` and B = `…0b`. Act as a user with `set local role authenticated` and `select set_config('request.jwt.claims', '{"sub":"<uuid>","role":"authenticated"}', true)`, and `reset role` between users. Assertions (spec 6.1):
1. Every table in `pg_publication_tables where pubname = 'powersync'` has primary key columns exactly `{owner_id,id}` in that order (from `pg_index` with `indisprimary`, unnest `indkey` with ordinality, joined to `pg_attribute`). The four named foreign keys exist. No foreign key on the child tables references `dives` or `cylinders` with a single column.
2. A, then B, insert the same ids: `dive_computers` `dc_b89641e4`; `dives` id `d1` with its `dive_samples`; `dive_annotations` id `d1`; `dive_cylinders` `d1:0`; `pressure_mappings` `dc_b89641e4:0`; `dive_merge_links` `d1`; a `cylinders` row each (`cyl_a`, `cyl_b`) and `dive_bailout_carry` `d1:cyl_a` / `d1:cyl_b`; `gas_analyses` with one shared id. B writes through `insert … on conflict (owner_id, id) do update set …`, the statement PostgREST generates. All succeed. Each user's `select count(*)` on each table returns only their own rows.
3. B repeats the dives upsert with a changed `max_depth_mm`, then runs `update dives set deleted_at = 1 where id = 'd1'`. A's row is unchanged.
4. B upserts `dives` `d1` with a lower `parser_version`, and updates `dive_samples` `d1`'s `depth_blob` at the same `parser_version`. Both leave B's row as it was (the 0026 triggers).
5. As B, inserting `dive_samples` id `d2` (no B dive `d2`; give A a dive `d2`) raises 23503.
6. As A, `select public.delete_my_account()` leaves 0 rows with `owner_id = A` in all 16 tables, and B's rows, including B's bailout and merge rows for `d1`, are all still there. Then make B unconfirmed (`email_confirmed_at null`, `created_at` 8 days ago, plus a third user C with the same shared ids), run `public.purge_unconfirmed_users()` as postgres, and confirm B is gone and C's rows are intact.
7. As B, `insert into dives … on conflict (id) do update …` raises SQLSTATE 42P10.

`scenarios/0027_guard_setup.sql`: users A and B; A's dive `d1` and cylinder; B's cylinder; and a B `dive_bailout_carry` row pointing at A's `d1`, inserted as postgres (FK checks ignore RLS). `scenarios/0027_guard_assert.sql`: every synced table's primary key is still `{id}`, and the old single-column foreign keys still exist.

- [ ] **Step 5: Run the harness; expect failure**

Run: `supabase/dry_run/run.sh`. Expected: FAIL in `0027_per_owner_row_keys_check.sql` at assertion 1 (primary key is `{id}`), because 0027 doesn't exist yet.

- [ ] **Step 6: Write `0027_per_owner_row_keys.sql`**

Header comment: why (spec section 1), what it does, and that it must be deployed only after a build with #233 and this PR's app changes has shipped. Body, in this order (spec 5.1):
1. Guard DO block. Count:
   - `dive_samples s where not exists (select 1 from dives d where d.owner_id = s.owner_id and d.id = s.id)`;
   - the same for `dive_bailout_carry.dive_id → dives`, `dive_bailout_carry.cylinder_id → cylinders` and `dive_merge_links.id → dives`.

   If any count is non-zero, `raise exception` naming all four counts and "see supabase/README.md, Before deploying 0027".
2. DO block: for each `(child, parent)` in `(dive_samples, dives), (dive_bailout_carry, dives), (dive_bailout_carry, cylinders), (dive_merge_links, dives)`, drop every `pg_constraint` with `contype = 'f'`, `conrelid = child`, `confrelid = parent` and `cardinality(conkey) = 1`, via `format('alter table public.%I drop constraint %I', …)`.
3. DO block over the 16 tables: if the primary-key columns are not `{owner_id,id}`, drop the primary-key constraint (name looked up by `contype = 'p'`), then `add primary key (owner_id, id)`.
4. DO block: add each of the four foreign keys only if `pg_constraint` has no constraint of that name. `dive_samples_owner_dive_fkey` is `on delete cascade`; the other three use the default (NO ACTION).
5. For the 16 tables, `revoke all on table public.<t> from anon, authenticated, service_role;` then `grant select, insert, update, delete on table public.<t> to authenticated, service_role;`, one statement per line.
6. `NOTIFY pgrst, 'reload schema';`

- [ ] **Step 7: Scope the deletes in 0022 and 0024**

In `delete_my_account()`, replace the bailout and merge deletes with `delete from public.dive_bailout_carry where owner_id = uid;` and `delete from public.dive_merge_links where owner_id = uid;`. In `purge_unconfirmed_users()`, the same with `owner_id = any(doomed)`. Rewrite the comment above each pair: rows are matched by owner because ids repeat across accounts since 0027, and the composite foreign keys keep a child's owner equal to its parent's. Add a line to each file's header: "Amended for 0027 (per-owner keys): edited in place because apply_migrations.sh re-runs every file."

- [ ] **Step 8: Run the harness; expect success**

Run: `supabase/dry_run/run.sh`. Expected: `✓ dry run passed`. The guard database's 0027 run fails with the guard's message, and the assert passes.

- [ ] **Step 9: Lint**

Run: `./supabase/lint_migrations.sh`. Expected: `OK: all migrations are idempotent and every table has explicit Data API grants.`

- [ ] **Step 10: README**

Add a "Before deploying 0027" section:
- **Deploy order** (spec 5.9): don't apply until a build with #233 and this PR has shipped.
- **Pre-flight query**: the guard's four checks as one `select … union all …` listing `table, owner_id, id`. If it lists rows, don't apply; those rows need a decision.
- **What to expect**: PowerSync re-replicates each table once, and clients download those rows again. Deploy at a quiet moment and watch the PowerSync dashboard until replication catches up.
- **Checks after deploying**: apply twice, then `check_migrations.sh`.
- **Dry run**: how to run it (`supabase/dry_run/run.sh`, Docker required).

Also amend the existing "These migrations reference Supabase-only objects… can't be run on a vanilla local Postgres" note: the dry run stubs them. In "Deleting an account on request" step 4, change the two deletes to `where owner_id = '<uid>'`.

- [ ] **Step 11: Commit**

```bash
git add supabase/
git commit -m "feat(db): key every synced table by owner and id (0027)"
```

### Task 2: Lint rule for new synced tables, CLAUDE.md principle 7

**Files:**
- Modify: `supabase/lint_migrations.sh`
- Modify: `CLAUDE.md` (principle 7, the sentence that starts "New PowerSync-backed tables also need")

**Interfaces:**
- Produces: `lint_migrations.sh [migrations_dir]`. With no argument it lints `supabase/migrations` as today.

- [ ] **Step 1: Write the failing check**

In the scratchpad, copy `supabase/migrations` into a temp dir and add `0028_bad.sql`. It creates `t_bad (id text primary key, owner_id uuid not null)` and adds it to the `powersync` publication with the DO-block form. Run: `supabase/lint_migrations.sh <tempdir>`. Expected today: the script ignores the argument and prints OK, so this step shows the gap.

- [ ] **Step 2: Implement the argument and rule 8**

Accept an optional directory. Rule 8: in each file numbered 0027 or higher, every table named in `add table (public.)?<t>` (or `create publication … for table`) must have a `create table if not exists (public.)?<t>` block in the same file containing `primary key (owner_id, id)` (case-insensitive, whitespace-tolerant). On failure, print `  <file>  synced table <t> needs primary key (owner_id, id)` and exit 1 with a FAIL line that points at CLAUDE.md principle 7.

- [ ] **Step 3: Verify both directions**

Run: `supabase/lint_migrations.sh <tempdir>` (with the bad 0028). Expected: FAIL naming `t_bad`. Change 0028 to `primary key (owner_id, id)` and rerun. Expected: OK. Then `./supabase/lint_migrations.sh` with no argument. Expected: OK. Delete the temp dir.

- [ ] **Step 4: CLAUDE.md**

In principle 7, after the grant sentence, add: "They also need `primary key (owner_id, id)`, not `id` alone: ids are computed from hardware and dive data, so two accounts can share one (0027; `lint_migrations.sh` enforces it)."

- [ ] **Step 5: Commit**

```bash
git add supabase/lint_migrations.sh CLAUDE.md
git commit -m "chore(db): lint new synced tables for per-owner primary keys"
```

### Task 3: Report 42501 uploads once to Sentry

**Files:**
- Modify: `lib/sync/cloud/powersync_schema.dart` (add `kSyncedTableNames`)
- Modify: `lib/sync/cloud/ccrlogger_backend_connector.dart`
- Create: `lib/sync/cloud/upload_permission_report.dart`
- Modify: `lib/main.dart:109-112` (pass the reporter)
- Test: `test/sync/cloud/ccrlogger_backend_connector_test.dart`
- Test: `test/sync/cloud/upload_permission_report_test.dart`

**Interfaces:**
- Produces: `final Set<String> kSyncedTableNames = {for (final t in appSchema.tables) t.name};` in `powersync_schema.dart`.
- Produces: `typedef UploadPermissionReporter = Future<void> Function(String table, UpdateType opType, Object error, StackTrace stack);` in the connector file.
- Produces: `bool isPermissionDenied(Object? error)`, top-level in the connector file. True for a `PostgrestException` with `code == '42501'`, and for a `CrudUploadException` whose `cause` is one. Task 5 uses it.
- Produces: named parameter `UploadPermissionReporter? onPermissionDenied` on both `CcrloggerBackendConnector(...)` and `.forTesting(...)`.
- Produces: `Future<void> reportUploadPermissionDenied(String table, UpdateType opType, Object error, StackTrace stack)` in `upload_permission_report.dart`.

- [ ] **Step 1: Write the failing connector tests**

In `group('replayCrud')`, use a `_RecordingReporter` that records `(table, opType)` and `_CodePoisonUploader(failTable: …, code: '42501')`:
- `a 42501 on an owned PUT is rethrown and reported once`: session `uid-b`, PUT `dive_computers` `dc_b89641e4` with `owner_id: 'uid-b'`. Expect `CrudUploadException`, reporter records `[('dive_computers', UpdateType.put)]`, quarantine empty.
- `a repeated 42501 on the same table and op is not reported again`: two `replayCrud` calls on the same connector → one record.
- `an ownerless PUT's 42501 is rethrown but not reported`.
- `a 42501 on a PATCH is reported`: PATCH `dives` → `[('dives', UpdateType.patch)]`.
- `a 42501 from the self-heal parent upsert is reported under the parent's table`: an uploader that throws 23503 for `dive_samples` and 42501 for `dives`. `fetchLocalRow` returns `{'owner_id': 'uid-b'}` for `dives`. Expect `CrudUploadException` and `[('dives', UpdateType.put)]`.
- `other errors are not reported`: codes `22001`, `503` → reporter empty.
- `a 42P10 is retried, not quarantined or reported` (Review Focus 2).
- `a throwing reporter does not change the outcome` (Review Focus 1): the reporter throws, and `replayCrud` still throws `CrudUploadException` with the 42501 cause, with quarantine empty.
- `isPermissionDenied`: true for `PostgrestException(code: '42501')` and for `CrudUploadException(op, thatException)`. False for `'42501'` as a string, code `23503`, and `null`.

- [ ] **Step 2: Run them; expect failure**

Run: `flutter test test/sync/cloud/ccrlogger_backend_connector_test.dart`. Expected: compile errors (`onPermissionDenied`, `isPermissionDenied` undefined).

- [ ] **Step 3: Implement**

In `replayCrud`'s `on PostgrestException catch (e, st)`, before the existing classification: if `e.code == '42501'` and the op is not an ownerless PUT (`op.op == UpdateType.put && op.opData?['owner_id'] == null`), call `_reportPermissionDenied(op.table, op.op, e, st)`. In `_healMissingParents`, wrap the parent `upsert` in `on PostgrestException catch (e, st)`: if 42501 and `row['owner_id'] != null`, call `_reportPermissionDenied(parentTable, UpdateType.put, e, st)`, then rethrow. `_reportPermissionDenied` dedupes on `'$table/${opType.name}'` in a `Set<String>` field, then awaits the reporter inside `try { … } catch (_) {}`. Rewrite the `_permanentSqlStates` doc comment's 42501 reason, per spec 5.3: after 0027 an own-row 42501 is a server defect a server fix resolves; it is retried, shown in the Sync tab and reported once.

- [ ] **Step 4: Run them; expect success**

Run: `flutter test test/sync/cloud/ccrlogger_backend_connector_test.dart`. Expected: all pass, including #233's existing tests.

- [ ] **Step 5: Write the failing reporter test**

`upload_permission_report_test.dart`, using `test/_helpers/sentry_capture.dart`. `reportUploadPermissionDenied('dive_computers', UpdateType.put, PostgrestException(message: 'new row violates row-level security policy for table "dive_computers" dc_b89641e4', code: '42501'), StackTrace.current)` sends one event. Its tags are exactly `{'sync.table': 'dive_computers', 'sync.op': 'put', 'sync.sqlstate': '42501'}`, and no exception value or message contains `dc_b89641e4` or `row-level`. With table `'not_a_table'`, `sync.table` is `'other'`.

- [ ] **Step 6: Run it; expect failure, implement, run it; expect success**

Implement `reportUploadPermissionDenied` as `captureRedactedException(error, stack, tags: {...})`. `sync.table` is the table if it is in `kSyncedTableNames`, else `'other'`. Run: `flutter test test/sync/cloud/upload_permission_report_test.dart`. Expected: PASS.

- [ ] **Step 7: Wire it in `main.dart`**

Pass `onPermissionDenied: reportUploadPermissionDenied` to the `CcrloggerBackendConnector(...)` at `lib/main.dart:109`.

- [ ] **Step 8: Commit**

```bash
git add lib/sync/cloud/ lib/main.dart test/sync/cloud/
git commit -m "feat(sync): report permission-denied uploads to Sentry once"
```

### Task 4: Set aside PATCHes of another account's rows

**Files:**
- Modify: `lib/sync/cloud/ccrlogger_backend_connector.dart` (`replayCrud`, beside #233's `_queuedByAnotherAccount`)
- Test: `test/sync/cloud/ccrlogger_backend_connector_test.dart` (the `// ── Account switch` block)

**Interfaces:**
- Consumes: `kSyncedTableNames` (Task 3); `OtherAccountOpException` and `_queuedByAnotherAccount` (#233); the existing `fetchLocalRow` parameter of `replayCrud`.

- [ ] **Step 1: Write the failing tests**

Session `uid-b`. `fetchLocalRow` is backed by a map `{('dive_annotations', 'd1'): {'owner_id': 'uid-a'}, …}` that records every call:
- `a PATCH whose local row names another account is quarantined unsent`: PATCH `dive_annotations` `d1` (local owner `uid-a`), then PUT `dives` `d2` owned by `uid-b`. The quarantine records `[d1]` with an `OtherAccountOpException` cause (extend `_RecordingQuarantine` to keep causes). The uploader sees no `_Update` for `d1` and one `_Upsert` for `d2`.
- `a PATCH whose local row is ownerless, the signed-in account's, or missing is uploaded`: three PATCHes, with local owner `null`, owner `uid-b`, and no local row. All three become `_Update` calls, and the quarantine is empty.
- `a DELETE is uploaded and never looks up the local row`: DELETE `oxygen_cells` `c1` → one `_Delete`, and `fetchLocalRow` is not called.
- `a PATCH on a table outside the synced tables never reaches the local-row lookup`: PATCH `ps_untyped` → `fetchLocalRow` not called, `_Update` sent.
- `with no session, a PATCH uploads without a local lookup` (Review Focus 4).

- [ ] **Step 2: Run them; expect failure**

Run: `flutter test test/sync/cloud/ccrlogger_backend_connector_test.dart`. Expected: the first test fails (`d1` is uploaded).

- [ ] **Step 3: Implement**

Add `Future<bool> _patchOfAnotherAccount(CrudEntry op, String? signedInUserId, Future<Map<String, dynamic>?> Function(String, String)? fetchLocalRow)`. It returns false unless the op is a PATCH, `signedInUserId` and `fetchLocalRow` are non-null, and `kSyncedTableNames.contains(op.table)`. It then reads the local row's `owner_id` and returns `owner != null && owner != signedInUserId`. Call it in the loop right after #233's PUT check, with the same quarantine and `continue`. Extend the `replayCrud` doc comment with spec 5.4's PATCH and DELETE reasoning, including the PowerSync guarantee and the "revisit if a table with repeating ids gets hard deletes" warning.

- [ ] **Step 4: Run them; expect success**

Run: `flutter test test/sync/cloud/ccrlogger_backend_connector_test.dart`. Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add lib/sync/cloud/ccrlogger_backend_connector.dart test/sync/cloud/ccrlogger_backend_connector_test.dart
git commit -m "fix(sync): set aside queued edits of another account's rows"
```

### Task 5: "Upload blocked by the server" in the Sync tab, runbook entry

**Files:**
- Modify: `lib/sync/cloud/sync_status_source.dart` (`SyncStatusSnapshot`)
- Modify: `lib/ui/screens/settings/sync_tab.dart` (`_formatSyncStatus`, `_statusLabel`)
- Create: `test/ui/screens/settings/sync_tab_upload_blocked_test.dart`
- Modify: `.claude/skills/sync-recovery/SKILL.md`

**Interfaces:**
- Consumes: `isPermissionDenied(Object?)` (Task 3).
- Produces: `final bool uploadBlockedByServer;` on `SyncStatusSnapshot`, default `false`, set in `fromPowerSync` as `isPermissionDenied(s.uploadError)`. On native, PowerSync passes the thrown `CrudUploadException` through the isolate port as an object (`isolate_completer.dart`), so the type check works.

- [ ] **Step 1: Write the failing widget tests**

Copy the setup of `sync_tab_sign_out_test.dart`: a fake auth client signed in, and a fake `SyncStatusSource` returning a given snapshot.
- `a blocked upload shows the blocked label and helper`: `SyncStatusSnapshot(connected: true, uploadBlockedByServer: true)` → text contains `🔴 Upload blocked by the server` and `The server refused a change. It uploads by itself once the server is fixed.`, and not `Syncing…`.
- `a blocked upload outranks uploading`: connected, `uploading: true`, blocked → blocked label.
- `offline outranks blocked` (Review Focus 3): `connected: false`, blocked → `🔴 Offline`, no blocked label.
- `no block shows Synced`: connected, not blocked → `🟢 Synced`.

- [ ] **Step 2: Run them; expect failure**

Run: `flutter test test/ui/screens/settings/sync_tab_upload_blocked_test.dart`. Expected: compile error (`uploadBlockedByServer` undefined).

- [ ] **Step 3: Implement**

Add the field. In `_statusLabel`, check it after the offline check and before the syncing check. In `_formatSyncStatus`, when blocked, append `'\n'` plus the helper sentence after the existing `Last synced` part.

- [ ] **Step 4: Run them; expect success**

Run: `flutter test test/ui/screens/settings/`. Expected: all pass, including #233's `sync_tab_sign_out_test.dart`.

- [ ] **Step 5: Runbook entry**

In `SKILL.md`, add "### Upload blocked by the server (42501)":
- **Symptom**: the Sync tab label.
- **Cause**: since 0027, an own-row 42501 means a server defect.
- **Steps**: find the `sync.table` tag on the Sentry event, then check the table's grants (`has_table_privilege('authenticated', 'public.<t>', 'INSERT')`), its RLS policy, and that its primary key is `(owner_id, id)`.
- **Recovery**: the queue drains by itself after the server fix; don't run Re-assign or Push stuck uploads for this.

- [ ] **Step 6: Commit**

```bash
git add lib/sync/cloud/sync_status_source.dart lib/ui/screens/settings/sync_tab.dart test/ui/screens/settings/sync_tab_upload_blocked_test.dart .claude/skills/sync-recovery/SKILL.md
git commit -m "feat(sync): show when the server blocks uploads"
```

### Task 6: Whole-branch verification

- [ ] **Step 1:** `flutter analyze`. Expected: `No issues found!`
- [ ] **Step 2:** `flutter test`. Expected: all tests pass (run it in the background, it takes several minutes).
- [ ] **Step 3:** `supabase/dry_run/run.sh` and `./supabase/lint_migrations.sh`. Expected: `✓ dry run passed` and `OK`.
- [ ] **Step 4:** `git diff --stat origin/fix/backfill-keep-other-account-uploads` touches only the files listed in Tasks 1–5, plus the spec and this plan. `packages/subsurface_core` is untouched, so `dart test` there isn't needed.
