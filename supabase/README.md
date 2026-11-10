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
publication), so they can't be run on a vanilla local Postgres. Verify against
the live (or a Supabase branch) DB:

1. `./supabase/apply_migrations.sh` — applies anything missing (e.g. 0009/0010).
2. Run it **again** — must complete with zero errors (all no-ops). This proves
   idempotency/convergence.
3. `./supabase/check_migrations.sh` — must print `✓ in sync`.

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
   delete from public.dive_bailout_carry
   where dive_id in (select id from public.dives where owner_id = '<uid>')
      or cylinder_id in (select id from public.cylinders where owner_id = '<uid>');
   delete from public.dive_merge_links
   where id in (select id from public.dives where owner_id = '<uid>');
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
