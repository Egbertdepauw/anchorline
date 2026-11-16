# Per-owner row keys on the server

Date: 2026-11-16. Status: approved by Egbert, 2026-11-16. Plan:
`docs/superpowers/plans/2026-11-16-per-owner-row-keys.md`.

## 1. The problem

A second Anchorline account that uses a dive computer another account
already has can never sync again. Its upload queue blocks forever on
Postgres error 42501.

Evidence (Egbert's iPhone, 2026-11-16): an empty test account stayed on
"Syncing…" for more than 20 minutes. Its `ps_crud` held one op, a PUT of
`dive_computers` id `dc_b89641e4` (his Petrel 3) owned by the test
account. The app writes that op as soon as the Petrel connects, before
any dive is imported. His main account already owns `dc_b89641e4` in
Supabase.

Why it happens:

- Every synced table has `id text primary key` on the server
  (`0001_initial_schema.sql`, `0003_dives_and_samples.sql` and later).
- Many ids are computed from hardware or dive data only, with no owner in
  them. The same computer or the same dive gives the same id in every
  account (table in section 3).
- RLS is `using (auth.uid() = owner_id) with check (auth.uid() = owner_id)`.
  The second account's upsert conflicts with the first account's row, the
  `ON CONFLICT DO UPDATE` hits a row it may not touch, and Postgres
  answers 42501.
- `CcrloggerBackendConnector.replayCrud` retries 42501 forever on
  purpose (it is left out of `_permanentSqlStates`), and the Sync tab
  shows "Syncing…" the whole time.
- `0026` already made `dive_computers` unique per owner on
  `(owner_id, dc_vendor, serial)`. The primary key never followed.

The same collision hits every dive two accounts both import, and every
child row keyed by the dive id. Rental and second-hand computers make
this real for users, not only for test accounts.

## 2. Goals, non-goals, anti-goals

Goals:

- Two accounts can hold rows with the same `id` in every synced table.
  Both sync, and neither can read or change the other's rows.
- Builds already installed (1.1.0+47 and earlier) keep working after the
  migration: their uploads resolve against the new keys with no app
  change. The test account's blocked op uploads by itself on its next
  retry.
- Switching accounts on one device never applies one account's queued
  changes to another account's rows, now that two accounts can own the
  same id (5.4). This needs the new build, so 0027 is deployed only after
  a build with it has shipped (5.9).
- A 42501 that keeps coming back is never silent again: the Sync tab says
  the upload is blocked, and Sentry hears about it once.
- A new synced table cannot ship with a global key: the migration lint
  refuses it.

Non-goals:

- Client ids do not change. PowerSync gives each user only their own
  rows, so ids only need to be unique per owner. `dive_id` stays
  `hash(serial, dc_dive_number, start_timestamp_utc)` (CLAUDE.md).
- No re-drive of quarantined ops (see 4.2, option B). #233's quarantined
  other-account ops still have none.
- No change to which foreign keys exist or to their delete behaviour.
  Existing foreign keys only gain `owner_id`.
- No change to `infra/powersync-sync-streams.yaml`.

Anti-goals (a failure even if the collision is gone):

- An account's deletion, or the nightly purge, removes rows of another
  account.
- One account can read another account's rows, through RLS, a foreign key
  or a server function.
- The migration half-applies, or silently drops rows that exist today.

## 3. Which ids repeat across accounts

Surveyed from the code on 2026-11-16 (paths relative to the repo root):

| Table | Id recipe | Repeats across accounts |
|---|---|---|
| `dives` | `generateDiveId(serial, number, start)`, a sha256 prefix (`packages/subsurface_core/lib/data/models/dive.dart`) | yes |
| `dive_samples` | the dive id | yes |
| `dive_annotations` | the dive id (`dive_annotations_dao.dart`) | yes |
| `dive_cylinders` | `"$diveId:$gasMixIndex"` | yes |
| `dive_merge_links` | the member dive id; `group_id` is a hash of the sorted dive ids | yes |
| `dive_computers` | `diveComputerId(vendor, serial)`: `dc_<hex serial>`, or `dc_<slug>_<hex serial>` | yes |
| `pressure_mappings` | `"$diveComputerId:$channel"` | yes |
| `gas_analyses` | random v4; bridge and USB captures use a UUIDv5 of `bridgeId/rid`, and USB always uses bridge id `usb` | yes, for bridge and USB captures |
| `dive_bailout_carry` | `"$diveId:$cylinderId"` | no in practice (the cylinder id is per account), but its `dive_id` foreign key points at a repeating id |
| `cylinders` | `cyl_<ms>_<role>` | unlikely, possible |
| `oxygen_cells` | `cell_<ms>_<slot>` | unlikely, possible |
| `scrubber_sessions` | `scrub_<µs>` | unlikely |
| `dive_attachments` | random v4 (`parent_id` holds a dive id) | no |
| `dive_plans` | random v4 | no |
| `open_blends` | random v4 | no |
| `user_acknowledgements` | random v4 | no |

Cross-account child rows can already exist today. A foreign-key check
ignores RLS, so a `dive_bailout_carry` or `dive_merge_links` row of
account B can point at account A's dive when B's own dive never reached
the server. The migration has to find these, not silently orphan or
drop them (5.1).

## 4. Approaches

### 4.1 Making ids per owner

- **Per-owner keys on the server (chosen).** Primary key `(owner_id, id)`
  on every synced table, and composite foreign keys for the child tables.
  The client keeps its ids. Installed builds need no change: PostgREST
  picks the conflict target from the primary key (below), PATCH and
  DELETE filter on `id` under RLS, and PowerSync identifies source rows by
  all of their key columns.
- **Per-owner ids on the client (rejected).** Put the owner into every
  id. That re-keys every row on every device, breaks the `dive_id` rule
  that Subsurface matching and re-parse depend on, renames R2 storage
  keys, and has to run while old builds are still uploading old ids.
- **Quarantine the collision (rejected).** Treat the 42501 as permanent
  and skip the op. The queue drains, but the second account's copy of the
  computer and its dives never reaches the server. That breaks principle 7
  without anyone noticing.

Scope, my call: all 16 synced tables, not only the ones that repeat
today. `cylinders` needs a key that includes `owner_id` anyway, because
`dive_bailout_carry` gets a composite foreign key to it. The time-based
ids can still repeat. And a uniform rule is one the lint and the dry-run
check can enforce. The cost is that PowerSync copies the small tables
once more (5.5).

### 4.2 What a 42501 on the user's own row does

After this change, a 42501 on a row the signed-in user owns can only come
from a server defect: a missing grant, a missing or wrong RLS policy, or a
synced table still keyed by `id` alone. A server fix (a migration or a
grant) makes the same upload succeed.

- **A, loud block (chosen by Egbert, 2026-11-16).** The connector keeps
  retrying, as today. The Sync tab shows that the upload is blocked
  instead of "Syncing…", and Sentry receives one redacted event naming the
  table, the op type and the SQLSTATE. Nothing gets reordered or lost.
  The queue drains by itself once the server is fixed.
- **B, park and re-drive (not chosen).** Quarantine the op so the rest of
  the queue drains, and re-upload the current local row on each sign-in
  until it succeeds. The queue never blocks, but it needs more code (the
  foreign-key self-heal path has to park children too) and lands changes
  out of order. It stays a candidate for a later change that also gives
  #233's quarantined ops their re-drive.

### 4.3 Queued changes across an account switch

Signing out keeps the upload queue. Today a PATCH or DELETE another
account queued is harmless under the new account, because RLS hides the
row with that id. Once two accounts can own the same id, it would land on
the new account's copy: account A's annotation edit or soft-delete of a
shared dive would change account B's row.

- **1. Fix it in this change, migration after (chosen by Egbert,
  2026-11-16).** The connector sets aside every queued op that belongs to
  another account, not only PUTs (5.4). 0027 is deployed once a build with
  this has shipped. Until then the test account stays blocked.
- **2. Migration first, fix after (not chosen).** Unblocks the test
  account sooner, but leaves a window where switching accounts with
  changes still queued corrupts the other account's rows.

## 5. Design

### 5.1 Migration `0027_per_owner_row_keys.sql`

One file, applied in one transaction by `apply_migrations.sh` like every
other. Idempotent per `supabase/README.md`: a second run changes nothing
and raises nothing.

1. **Guard.** Count the child rows whose parent does not exist for the
   same owner:
   - `dive_samples` whose `(owner_id, id)` has no `dives` row;
   - `dive_bailout_carry` whose `(owner_id, dive_id)` has no `dives` row,
     or whose `(owner_id, cylinder_id)` has no `cylinders` row;
   - `dive_merge_links` whose `(owner_id, id)` has no `dives` row.

   If any exist, `raise exception` with the four counts and a pointer to
   the README pre-flight query, so the whole migration rolls back. The
   query is written so it means the same thing before and after the
   migration (after it, the foreign keys keep the count at zero), which
   keeps the file re-runnable.
2. **Drop the single-column foreign keys** into `dives(id)` and
   `cylinders(id)`: `dive_samples.id`, `dive_bailout_carry.dive_id`,
   `dive_bailout_carry.cylinder_id`, `dive_merge_links.id`. Find them in
   `pg_constraint` by table, referenced table and column, not by a
   hard-coded name. The 0026 review flagged hard-coded constraint names
   as an apply-time risk.
3. **Re-key all 16 tables.** For each table in the list below whose
   primary key is not exactly `(owner_id, id)`: drop the primary-key
   constraint (found by lookup), then `add primary key (owner_id, id)`.
   `owner_id` is already `not null` on all 16. Tables:
   `dive_annotations, cylinders, oxygen_cells, scrubber_sessions,
   pressure_mappings, dive_cylinders, dive_computers, dives, dive_samples,
   dive_attachments, dive_bailout_carry, dive_plans, dive_merge_links,
   gas_analyses, user_acknowledgements, open_blends`.
4. **Add the composite foreign keys**, each only if a constraint with its
   name does not exist yet:
   - `dive_samples (owner_id, id) → dives (owner_id, id) on delete cascade`
     (it is `on delete cascade` today);
   - `dive_bailout_carry (owner_id, dive_id) → dives (owner_id, id)`;
   - `dive_bailout_carry (owner_id, cylinder_id) → cylinders (owner_id, id)`;
   - `dive_merge_links (owner_id, id) → dives (owner_id, id)`.

   The last three stay NO ACTION, as today.
5. **Restate the table grants** for the 16 tables (revoke all, then grant
   select, insert, update, delete to authenticated and service_role),
   the same form 0026 uses. No new table, so this is belt and braces.
6. `NOTIFY pgrst, 'reload schema';`

**The two deleting functions, edited in place in 0022 and 0024** (my
call). `delete_my_account()` and `purge_unconfirmed_users()` delete
bailout and merge rows "whose dive or cylinder id is one of the user's".
Once ids repeat, that also deletes another account's rows for the same
dives. They become `delete from public.dive_bailout_carry where owner_id
= uid` and `delete from public.dive_merge_links where owner_id = uid`
(`= any(doomed)` in the purge). The composite foreign keys guarantee a
child row has its parent's owner, so this covers everything the old form
did. Signatures, settings, grants and the 0024 cron schedule stay as they
are.

They are edited in their own files, not redefined in 0027, because
`apply_migrations.sh` re-runs every file on every deploy. A redefinition
in 0027 would be undone by 0022 and 0024 for part of every later deploy,
and stay undone if a run stopped between them. Each file gets a comment
saying it was amended for 0027. If 0027's guard stops a deploy, the new
bodies run against the old keys. A cross-account child row then makes
that account's deletion fail on a foreign key instead of deleting the
other account's row. That fails loudly, which is the safe direction.

Left as they are: the `owner_id` indexes from 0002 and later (now
redundant with the primary key, harmless), the unique keys that already
include `owner_id`, and the 0026 triggers. `keep_newer_parse` and
`keep_newer_samples` are BEFORE UPDATE row triggers that never mention
the key, and they fire the same way for the conflicting row of an
`ON CONFLICT (owner_id, id) DO UPDATE`.

### 5.2 How installed builds behave after the migration

- **PUT** (`upsert` without `onConflict`): postgrest-dart 2.7.0 sends
  `Prefer: resolution=merge-duplicates` and no `on_conflict`. PostgREST
  then uses the primary key as the conflict target
  (`confCols = fromMaybe pkCols qsOnConflict`, `src/library/PostgREST/Plan.hs`),
  so after the schema reload it generates `ON CONFLICT (owner_id, id)`.
  The payload always carries `owner_id` (the local row has it). An
  ownerless PUT inserts a NULL owner, conflicts with nothing and fails
  RLS with 42501, exactly as today.
- **PATCH and DELETE** (`.eq('id', id)`): RLS adds `owner_id = auth.uid()`,
  so they touch only the caller's row, and the primary-key index serves
  the lookup.
- **Schema-cache window**: between the commit and PostgREST's reload, an
  upsert still targets `ON CONFLICT (id)`, which no longer matches a
  constraint. Postgres answers 42P10. The connector treats 42P10 as
  transient (it is not in `_permanentSqlStates`, and its code doesn't
  parse as an HTTP status), so it retries and nothing is lost.
- **Foreign-key self-heal** (23503 → re-upsert the parent from the local
  DB → retry) works as before. It now also catches a child whose own
  account's parent is missing, a case the global key used to hide.

The connector keeps calling `upsert(data)` with no `onConflict`. Passing
`onConflict: 'owner_id,id'` would break uploads against a server that
hasn't had 0027 yet (42P10 on every PUT) and gains nothing.

### 5.3 Loud block (option A)

Connector (`lib/sync/cloud/ccrlogger_backend_connector.dart`):

- 42501 stays out of `_permanentSqlStates` and is still retried. Rewrite
  the comment: after 0027 a 42501 on the user's own row means a server
  defect that a server fix resolves; the ownerless case (sign-in backfill
  pending) still resolves on the client.
- When an op fails with a 42501, wherever it happens (the op itself, or
  the parent upsert inside the self-heal path), report it once per
  `(table, op type)` per connector instance through an injected reporter.
  The production reporter calls
  `captureRedactedException(error, stack, tags: {...})` with three tags:
  `sync.table` (the table name, checked against the known synced tables,
  else `other`), `sync.op` (`put`, `patch` or `delete`) and
  `sync.sqlstate` (`42501`). No ids, no owner, no message text: a
  `dc_<serial>` id carries a serial number.
- Don't report an ownerless PUT (no `owner_id` in its data). That is the
  signed-out-import case the sign-in backfill claims; it is expected and
  short-lived.
- #233's other-account PUTs never reach the server, so they never get
  here.

Sync tab (`lib/ui/screens/settings/sync_tab.dart`, `_statusLabel`):

- When the last upload failed with a 42501, the status reads
  **"🔴 Upload blocked by the server"**, checked before the "Syncing…"
  case. A helper line under it reads: "The server refused a change. It
  uploads by itself once the server is fixed." (My call: Repair has no
  read-only report to point at, and its actions rewrite the queue, so the
  line sends the user nowhere.) The state clears when PowerSync clears
  `uploadError` after a successful upload.
- The classification is a field on `SyncStatusSnapshot`
  (`uploadBlockedByServer`, a bool), set in `fromPowerSync`, so widget
  tests build it directly.

The 42501 check is shared: one function decides "this error is a 42501"
for the reporter and for the snapshot.

### 5.4 Queued changes across an account switch

This builds on #233 (`fix/backfill-keep-other-account-uploads`, open on
2026-11-16), which already sets aside a queued PUT whose `owner_id` names
another account, with cause `OtherAccountOpException`. This work branches
from #233 and lands after it.

The connector attributes each op to an owner before sending it, and sets
it aside unsent (quarantine, cause `OtherAccountOpException`) when that
owner is a signed-in account other than the current one:

- **PUT**: the `owner_id` in its data (#233, unchanged). No owner means
  a signed-out import, which the sign-in backfill claims.
- **PATCH**: the `owner_id` of its row in the local database. A PATCH
  carries only the changed columns, but its row is still there: PowerSync
  doesn't publish downloaded data while the upload queue holds anything
  ("Don't publish downloaded data until the upload queue is empty",
  `can_apply_sync_changes` in powersync-sqlite-core's
  `crates/core/src/sync/sync_local.rs`, priority 0 excepted; our streams
  don't use priorities). While account A's ops wait, the local row still
  says A, even after B signs in. A row with no owner (a signed-out import)
  is claimable, so its PATCH uploads. A PATCH whose local row no longer
  exists uploads as today (see DELETE).

  Local updates keep an existing owner: every DAO UPDATE that writes
  `owner_id` from the session uses `owner_id = COALESCE(owner_id, ?)`, so
  an owned row is not re-owned and an ownerless row is still claimed. That
  is what keeps the local row naming A through a signed-out edit or an edit
  under B. (The Settings "Re-assign dives to this account" path re-owns on
  purpose and is unchanged.)

  The Settings "Push stuck uploads" drain replays ps_crud directly, so it
  calls the same check (`CcrloggerBackendConnector.isQueuedByAnotherAccount`)
  and leaves such ops in the queue.
- **DELETE**: carries no data, and its local row is gone, so it has no
  owner to read. It uploads as today. The only hard deletes in the app
  are on `dive_plans` (random ids), `oxygen_cells` (`cell_<ms>_<slot>`)
  and `dive_bailout_carry` (`<diveId>:<cylinderId>`, where the cylinder id
  is per account). Their ids don't repeat across accounts in practice, so
  a DELETE can only reach the signed-in account's own row. If a table with
  repeating ids ever gets hard deletes, this rule has to be revisited. A
  comment at the check says so.

The local-row lookup goes through the same `fetchLocalRow` seam the
self-heal path uses. The table name comes from the op, so check it
against the known synced tables before it goes into the SQL.

#233's sign-out warning ("If you sign in with another account first,
they won't upload") then holds for every kind of change, not only new
rows.

Installed builds don't have this. Their backfiller also rewrites another
account's queued PUTs to the new account, and 42501 used to stop such a
PUT for an id the old account already had on the server. After 0027 that
PUT would succeed. Both are why the deploy waits for the new build (5.9).

### 5.5 PowerSync

- Composite source keys are supported. PowerSync's Postgres module takes
  the replica-identity columns from the relation message
  (`getReplicaIdColumns`, `modules/module-postgres/src/replication/PgRelation.ts`)
  and builds the row identity from all of them (`getUuidReplicaIdentityBson`,
  `packages/service-core/src/util/utils.ts`). With `REPLICA IDENTITY
  DEFAULT`, those are the primary-key columns.
- The output `id` only has to be unique per client ("PowerSync does not
  perform any validation that IDs are unique",
  docs.powersync.com/sync/advanced/client-id). Each user syncs only rows
  with their own `owner_id`, and `(owner_id, id)` is now unique, so no
  client ever gets two rows with one id.
- A primary-key change is a replica-identity change: "the entire table is
  re-replicated again", and "all other replication will be blocked"
  until that finishes (docs.powersync.com/maintenance-ops/implementing-schema-changes).
  Expect each table to be copied once when its next change arrives, and
  clients to download those rows again. `dive_samples` is the one large
  table. Deploy at a quiet moment and watch the PowerSync dashboard until
  replication has caught up.
- `infra/powersync-sync-streams.yaml` does not change, so nothing needs
  redeploying there.

### 5.6 Lint rule

`supabase/lint_migrations.sh` gets an eighth rule: a table that a
migration numbered 0027 or later adds to the `powersync` publication must
be created in that same file with `primary key (owner_id, id)`. Tables
created in 0001–0026 are exempt, since 0027 re-keys them. CI already runs
the lint.

### 5.7 Docs

- `supabase/README.md`: a "Before deploying 0027" section with the
  pre-flight query (the guard's four checks, listing rows instead of
  counting them) and "if it lists rows, don't apply, those rows need a
  decision". It also covers the deploy-time PowerSync re-replication.
  The manual account-deletion SQL ("Deleting an account on request")
  switches to `where owner_id = '<uid>'`, for the same reason as the
  functions.
- `CLAUDE.md` principle 7: a new synced table also needs
  `primary key (owner_id, id)`.
- `.claude/skills/sync-recovery/SKILL.md`: a short "Upload blocked by the
  server (42501)" entry: check the Sentry tags for the table, then the
  table's grants, RLS policy and primary key. #233 edits the same file,
  so whichever merges second rebases.

### 5.8 Consequences for the sync-service spec

`docs/superpowers/specs/2026-11-02-subsurface-sync-service-design.md`
(branch `spec/subsurface-sync-service`) needs a short amendment, as a
follow-up outside this PR:

- `subsurface_sync_dives` has `id` = dive id. It must get
  `primary key (owner_id, id)` like every synced table, and the lint
  enforces that.
- The service reads with its own role, bypassing RLS, and filters by user
  id itself. Every read and join on an id must also match `owner_id`:
  `dive_samples` to `dives`, annotations and cylinders to their dive,
  bailout to cylinders.

### 5.9 Deploy order

1. #233 merges, then this PR.
2. A build containing both ships. A hand-built TestFlight or internal
   build is enough; it doesn't have to wait for a release train.
3. Then Egbert deploys 0027 (6.3). The edited 0022 and 0024 go live in
   the same `apply_migrations.sh` run, since it re-runs every file.

Until step 3, nothing on the server changes, and the test account stays
blocked.

## 6. Verification

### 6.1 Local dry run (before the PR)

A throwaway `postgres:17-alpine` container (the image is already local)
with a minimal Supabase stub:

- the roles `anon`, `authenticated` and `service_role`;
- an `auth` schema with `users` (id, email, email_confirmed_at,
  created_at), `audit_log_entries` (payload jsonb) and `auth.uid()`
  reading `request.jwt.claims`;
- a stub `pg_cron` extension (control file and `cron.job`, `schedule`,
  `unschedule`), so 0008, 0017 and 0024 run unmodified.

Run 0001–0027, then a check script that runs as `authenticated` with
claims set for user A or user B:

1. Every table in the `powersync` publication has primary key exactly
   `(owner_id, id)`. The four composite foreign keys exist, and no
   single-column foreign key into `dives` or `cylinders` is left.
2. Collision: A, then B, insert the same ids (`dive_computers`
   `dc_b89641e4`, a dive and its samples, annotation, `dive_cylinders`,
   `pressure_mappings`, merge link, bailout carry and a USB
   `gas_analyses` id). B's rows go through the SQL PostgREST generates
   for an upsert (`INSERT … ON CONFLICT (owner_id, id) DO UPDATE SET …`).
   Both succeed, and each user's `select` returns only their own rows.
3. Updates stay in their account: a repeated upsert by B and a PATCH-style
   `update … where id = …` by B change only B's row.
4. The triggers still hold: an upsert with a lower `parser_version`, and a
   same-version blob change to `dive_samples`, leave B's row as it was.
5. A `dive_samples` row of B for a dive B doesn't have fails with 23503.
6. `delete_my_account()` as A removes all of A's rows and none of B's,
   including B's bailout and merge rows for the shared dive.
   `purge_unconfirmed_users()` with A unconfirmed does the same.
7. The guard: on a fresh 0001–0026 database with one cross-account
   bailout row, applying 0027 raises, and every primary key is still
   `(id)` afterwards.
8. Idempotency: applying 0027 a second time succeeds and changes nothing.
9. After 0027, `INSERT … ON CONFLICT (id)` fails with 42P10 (the
   schema-cache window in 5.2).

Builder's call whether the stub and script go into the repo (my
preference: `supabase/dry_run/`, so the next migration can reuse them)
or stay in the workspace as for 0026.

### 6.2 App tests (test-first)

- `ccrlogger_backend_connector_test`:
  - a 42501 on an owned PUT is rethrown (still retried) and reported once;
  - a second 42501 on the same table and op is not reported again;
  - an ownerless PUT's 42501 is not reported;
  - a 42501 from the self-heal parent upsert is reported under the
    parent's table;
  - other errors are never reported this way;
  - a PATCH whose local row names another account is quarantined
    unsent, and the next op still uploads;
  - a PATCH whose local row is ownerless, owned by the signed-in
    account, or missing is uploaded;
  - a DELETE is uploaded whatever the signed-in account;
  - a PATCH on a table outside the known synced tables never reaches the
    local-row SQL.
- `sync_status_source` / snapshot: a `CrudUploadException` with a 42501
  cause sets `uploadBlockedByServer`; other errors and no error don't.
- `sync_tab` widget test: the blocked label and helper show for a blocked
  snapshot, and "Syncing…" doesn't.
- `flutter analyze` clean, `flutter test` passing. `packages/subsurface_core`
  is not touched.

### 6.3 Acceptance (Egbert, after deploying)

0. The phones in the test run on a build with #233 and this PR (5.9).
1. Run the README pre-flight query in the SQL Editor. It should list no
   rows.
2. `./supabase/apply_migrations.sh`, run it again (no-op), then
   `./supabase/check_migrations.sh`.
3. Watch the PowerSync dashboard until replication has caught up.
4. The test account's blocked `dive_computers` PUT uploads by itself.
   Connect the same Petrel 3 to the test account and import a dive the
   main account already has. Both accounts' Sync tabs end on "🟢 Synced",
   and neither shows "Upload blocked by the server".
5. In the SQL Editor, the shared ids appear once per owner, and each
   account's app shows only its own dives.
6. Account switch: on the main account, edit the shared dive's notes
   with the phone offline, sign out, sign in to the test account and go
   back online. In the SQL Editor, the test account's copy keeps its own
   notes, and the test account's queue drains (its Sync tab ends on
   "🟢 Synced"). The main
   account's edit does not reach the server later either: with no
   re-drive it stays set aside on the phone, as #233's sign-out warning
   says.

Rollback: before any id repeats across accounts, reversing the DDL
restores the old keys. Once one repeats, there is no going back to a
global key, and that is intended: the global key is the bug.

## 7. Left to the builder

- The exact SQL for the lookups and guards in 5.1, as long as the
  idempotency and lookup-not-name rules hold.
- Constraint names for the new foreign keys.
- How the reporter is injected into the connector, and how the 42501
  check reads the error (the exception object, or its text if PowerSync
  hands over a string on some platform). Check which one arrives on
  native before relying on it.
- How the lint rule parses the files, as long as it is a static check
  that runs in CI.
- Whether the dry-run stub is committed (6.1).
- How the branch stacks on #233 (based on its branch, rebased onto
  `main` once #233 merges).
