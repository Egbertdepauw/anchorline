# Supabase migrations

Plain numbered SQL migrations applied to the live Supabase project by a small
`psql` script. No Supabase CLI. Every migration is **idempotent**, so the whole
set re-runs to converge — this is also the fresh-project-recreate path.

## The idempotency rule (enforced by `lint_migrations.sh`)

Every statement must be safe to run twice:
- `create table/index` → `... if not exists`
- `alter table ... add column` → `... add column if not exists`
- `alter table ... drop column` → `... drop column if exists`
- `create policy "P" on T ...` → precede with `drop policy if exists "P" on T;`
- `create/alter publication ... ` → wrap in a `do $$ ... if not exists
  (select 1 from pg_publication[_tables] ...) then execute '...'; end if; end $$;`

`./supabase/lint_migrations.sh` (no DB) fails the build if any migration breaks
this. It also runs in CI.

## The Data API grant rule (also enforced by `lint_migrations.sh`)

Supabase no longer auto-grants new `public` tables to `anon` / `authenticated`
/ `service_role`. New projects haven't since 2026-05-30, existing projects
stop on 2026-10-30, and 0016 opts this project in early. Every app write goes
through PostgREST as `authenticated` (PowerSync upload connector,
UsageTracker, CloudDataWiper). A table with no grant is unreachable, and
uploads to it fail with `permission denied`. So the migration that creates a
table must also grant access, one statement per line:

```sql
grant select, insert, update, delete on table public.<t> to authenticated, service_role;
```

Grant only what the client uses (e.g. `usage_events` is insert-only), and
never grant `anon`, since no code path runs signed-out. For a table that must
stay off the Data API, write the explicit opt-out
(`revoke all on table public.<t> from anon, authenticated;`). The lint accepts
either form, but a table with neither fails CI (issue #76).

## DATABASE_URL

Use the **direct/session** connection string (NOT the pooler) — DDL +
`alter publication` need a direct session. Supabase → Project Settings →
Database → Connection string → URI (Session mode).

```bash
export DATABASE_URL='postgresql://postgres:<pwd>@db.<ref>.supabase.co:5432/postgres'
```

## Deploy

```bash
./supabase/apply_migrations.sh   # applies all migrations, records versions
./supabase/check_migrations.sh   # ✓ in sync, or lists drift
```

## Acceptance test (the real verification)

These migrations reference Supabase-only objects (`auth.users`, the `powersync`
publication, `pg_cron`). `supabase/dry_run/run.sh` stubs them on a throwaway
Postgres in Docker (see "Dry run" below), which proves the SQL and idempotency
but not the live project. Verify against the live (or a Supabase branch) DB:

1. `./supabase/apply_migrations.sh` — applies anything missing (e.g. 0009/0010).
2. Run it **again** — must complete with zero errors (all no-ops). This proves
   idempotency/convergence.
3. `./supabase/check_migrations.sh` — must print `✓ in sync`.

## Before deploying 0027

`0027_per_owner_row_keys.sql` keys all 16 synced tables by `(owner_id, id)`
and makes the four child foreign keys composite, so two accounts can hold the
same ids (same dive computer, same dive). Spec:
`docs/superpowers/specs/2026-11-16-per-owner-row-keys-design.md`.

**Deploy order.**

1. Hand-build the TestFlight or internal build from the PR branch's head (it
   contains #233's commit) and ship it.
2. Merge #233, then this PR.
3. Right after merging, run the pre-flight queries below, then deploy 0027 in
   the SQL Editor (see "Deploying 0027 in the SQL Editor").

Until step 3 the blocked test account stays blocked.

Every whole-set deploy (`apply_migrations.sh`, or pasting every migration into
the SQL Editor) includes 0027 once this PR is merged, even one made for an
unrelated later migration. Don't make one before step 3. If another migration
has to go out first, leave `0027_per_owner_row_keys.sql` out of it. That run
still deploys the edited 0022 and 0024, which is safe on its own.

**Pre-flight query.** 0027 refuses to run (and rolls back completely) if a
child row has no parent of the same owner. Check first, in the SQL Editor:

```sql
select 'dive_samples -> dives' as problem, s.owner_id, s.id
from public.dive_samples s
where not exists (select 1 from public.dives d where d.owner_id = s.owner_id and d.id = s.id)
union all
select 'dive_bailout_carry -> dives', c.owner_id, c.id
from public.dive_bailout_carry c
where not exists (select 1 from public.dives d where d.owner_id = c.owner_id and d.id = c.dive_id)
union all
select 'dive_bailout_carry -> cylinders', c.owner_id, c.id
from public.dive_bailout_carry c
where not exists (select 1 from public.cylinders y where y.owner_id = c.owner_id and y.id = c.cylinder_id)
union all
select 'dive_merge_links -> dives', m.owner_id, m.id
from public.dive_merge_links m
where not exists (select 1 from public.dives d where d.owner_id = m.owner_id and d.id = m.id);
```

If it lists rows, do not apply: those rows need a decision from Egbert.

Also list every unique index on the 16 synced tables whose only column is `id`:

```sql
select c.relname as "table", i.relname as "index"
from pg_index x
join pg_class c on c.oid = x.indrelid
join pg_class i on i.oid = x.indexrelid
where x.indisunique and x.indnatts = 1
  and c.relnamespace = 'public'::regnamespace
  and c.relname in ('dive_annotations', 'cylinders', 'oxygen_cells', 'scrubber_sessions',
    'pressure_mappings', 'dive_cylinders', 'dive_computers', 'dives', 'dive_samples',
    'dive_attachments', 'dive_bailout_carry', 'dive_plans', 'dive_merge_links',
    'gas_analyses', 'user_acknowledgements', 'open_blends')
  and (select a.attname from pg_attribute a
       where a.attrelid = c.oid and a.attnum = x.indkey[0]) = 'id'
order by 1, 2;
```

Before deploying, only the 16 `<table>_pkey` primary keys should appear; any
other row is an index made outside the migrations, would survive 0027 and keep
collisions alive as 23505, and needs a decision. After 0027 the result must be
empty.

0027 also refuses to run if any of the 16 tables has a REPLICA IDENTITY other
than DEFAULT (for example `USING INDEX` on the old id-only key, which would fall
to NOTHING once that index is dropped and break PowerSync). Check first:

```sql
select c.relname, c.relreplident
from pg_class c
where c.relnamespace = 'public'::regnamespace
  and c.relname in ('dive_annotations', 'cylinders', 'oxygen_cells', 'scrubber_sessions',
    'pressure_mappings', 'dive_cylinders', 'dive_computers', 'dives', 'dive_samples',
    'dive_attachments', 'dive_bailout_carry', 'dive_plans', 'dive_merge_links',
    'gas_analyses', 'user_acknowledgements', 'open_blends')
  and c.relreplident <> 'd';
```

It must list no rows. If it does, stop and go back to Egbert.

**What to expect.** Changing a primary key makes PowerSync re-replicate each
table once, and clients download those rows again. Deploy at a quiet moment
and watch the PowerSync dashboard until replication catches up.

**Deploying 0027 in the SQL Editor.** The database password isn't available
(it is masked everywhere), so deploy from the dashboard's SQL Editor, which runs
as the dashboard session. 0026 and everything before it are already live, so
only the three changed files go in, in this order, with the version record
`apply_migrations.sh` would write. Copy them from the repo root:

```bash
{ cat supabase/migrations/0022_delete_my_account.sql supabase/migrations/0024_purge_unconfirmed_users.sql supabase/migrations/0027_per_owner_row_keys.sql; echo "insert into public._ccrl_migrations(version) values ('0027') on conflict (version) do nothing;"; } | pbcopy
```

Paste into a new SQL Editor query and press Run. The editor sends the paste as
one query, which Postgres runs as one transaction, so if 0027's guard refuses,
nothing in the paste is applied. In that case the error names the reason; stop
and go back to Egbert. Then press Run a second time: it must finish with no
errors (everything is idempotent). Both behaviours were checked against the
dry-run database with the paste sent as one query.

With `DATABASE_URL` set (Session pooler), `./supabase/apply_migrations.sh` twice
does the same.

**Checks after deploying.** The id-only index query above must return no rows,
and this must return the 16 tables, each with `owner_id,id`:

```sql
select c.relname as "table", string_agg(a.attname, ',' order by k.ord) as pk
from pg_index x
join pg_class c on c.oid = x.indrelid
cross join unnest(x.indkey) with ordinality as k(attnum, ord)
join pg_attribute a on a.attrelid = c.oid and a.attnum = k.attnum
where x.indisprimary
  and c.relnamespace = 'public'::regnamespace
  and c.relname in ('dive_annotations', 'cylinders', 'oxygen_cells', 'scrubber_sessions',
    'pressure_mappings', 'dive_cylinders', 'dive_computers', 'dives', 'dive_samples',
    'dive_attachments', 'dive_bailout_carry', 'dive_plans', 'dive_merge_links',
    'gas_analyses', 'user_acknowledgements', 'open_blends')
group by c.relname
order by 1;
```

## Dry run

`supabase/dry_run/run.sh` (Docker and `psql` required, no arguments, exit 0 =
pass) starts a throwaway `postgres:17-alpine` on port 55433 with the
Supabase-only objects stubbed, applies every migration twice, and then runs
every `supabase/dry_run/checks/*_check.sql`. It also runs the 0027 guard
scenarios in further databases: the cross-owner refusal, 0027 applied to
populated data that passes the guard (row counts must not change), and the
REPLICA IDENTITY refusal. It never touches a real Supabase project. A
new migration that needs a behavioural check adds a `checks/NNNN_*_check.sql`
that owns its own `begin; ... rollback;`.

## Before deploying 0022

`0022_delete_my_account.sql` adds `delete_my_account()` for in-app account
deletion. Nothing calls it until the app ships, so deploying it early is
safe. Before applying it, check in the SQL Editor:

1. `select has_table_privilege('postgres', 'auth.users', 'DELETE');` must
   return `true`. If it returns `false`, stop and go back to Egbert: the
   fallback is a request queue or the Dart service, and that decision is his.
2. Apply the migration (`./supabase/apply_migrations.sh`), then check it
   end to end: create a throwaway account in the app, add a dive and an
   attachment, add a bailout-carry entry to a dive, and merge two dives.
   Then delete the account from the app, and confirm the user is gone from
   Authentication → Users and its rows are gone from `dives`.
3. Post-check, with the throwaway account's user id:

   ```sql
   select count(*) from auth.audit_log_entries where payload->>'actor_id' = '<uid>';
   ```

   It must return 0. If it does not, the function's guarded audit-log
   delete lacked the privilege, and those entries (which hold the email and
   IP address) are still there. Tell Egbert: he decides whether to delete
   them by hand or disclose them in the privacy policy.

Optional rollback dry run against a real user id (for example your own,
which has bailout carry and merged dives). It runs the whole function as
that user inside a transaction and rolls it back, so it raises any foreign
key error the real deletion would hit without deleting anything. Run all
four statements together; without the `rollback` the account is deleted
for real.

```sql
begin;
select set_config('request.jwt.claims', '{"sub":"<uid>","role":"authenticated"}', true);
select public.delete_my_account();
rollback;
```

## Deleting an account on request (email)

For people who no longer have the app and email `support@anchorline.eu`
(confirm within 5 working days, complete within 30 days):

1. Verify the email comes from the address the account was created with.
2. Note the user id (Authentication → Users).
3. Delete the `attachments/<uid>/` prefix in the Cloudflare R2 dashboard.
4. The dashboard delete does not run `delete_my_account()`, so first do
   its extra deletes in the SQL Editor (the rows the cascade misses, and
   the audit-log entries that hold the email and IP address):

   ```sql
   delete from public.dive_bailout_carry where owner_id = '<uid>';
   delete from public.dive_merge_links where owner_id = '<uid>';
   delete from auth.audit_log_entries where payload->>'actor_id' = '<uid>';
   ```

5. Delete the user under Authentication → Users. Their rows cascade.
6. The dashboard delete itself logs a `user_deleted` audit entry whose
   traits name the user's id, email and phone. Delete it too:

   ```sql
   delete from auth.audit_log_entries where payload->'traits'->>'user_id' = '<uid>';
   ```

   If either audit-log delete fails with `permission denied`, tell Egbert,
   as in the post-check above.
7. Reply to confirm the deletion.

## Purging unconfirmed sign-ups (0024)

`0024_purge_unconfirmed_users.sql` schedules `purge-unconfirmed-users`, a
nightly pg_cron job (03:43 UTC) that deletes email sign-ups still
unconfirmed 7 days after they were created, together with their audit-log
entries. The confirmation code expires after 1 hour, so these accounts can
never be confirmed. The function `public.purge_unconfirmed_users()` is not
callable through the Data API.

Before applying it, preview what the first run will delete:

```sql
select id, email, created_at from auth.users
where email_confirmed_at is null and email is not null
  and created_at < now() - interval '7 days';
```

Accounts created before 2026-11-10 (when Confirm email was switched on)
should not appear: sign-ups were auto-confirmed then. If any do, stop and
tell Egbert before applying.

To check that the job runs:

```sql
select start_time, status, return_message from cron.job_run_details
where jobid = (select jobid from cron.job where jobname = 'purge-unconfirmed-users')
order by start_time desc limit 5;
```
