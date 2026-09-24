-- Explicit Data API grants for every public table (issue #76).
--
-- Supabase stops auto-granting anon/authenticated/service_role on new
-- tables in `public`. That is already the default for projects created
-- since 2026-05-30 and is enforced on existing projects from 2026-10-30.
-- Migrations 0001–0015 relied entirely on those implicit default
-- privileges. Every app write goes through the Data API (PostgREST) as
-- `authenticated`: the PowerSync upload connector, UsageTracker and
-- CloudDataWiper. A fresh-project recreate would therefore leave all
-- tables unreachable, and every CRUD upload would fail with
-- `permission denied`.
--
-- Least-privilege, identical on live and on a fresh recreate:
--   * revoke everything first, then grant back exactly what's used.
--     apply_migrations.sh runs each file in one transaction, so the app
--     never observes the gap. It also drops the TRUNCATE / REFERENCES /
--     TRIGGER that Supabase's old defaults handed out.
--   * anon: nothing. No code path runs signed-out against these tables.
--     RLS would reject it anyway; this closes the door one layer earlier.
--   * authenticated: CRUD on the synced tables (upsert needs select +
--     insert + update; RLS still scopes rows to owner_id). usage_events is
--     insert-only, matching its RLS (UsageTracker inserts with
--     return=minimal, so no select is needed).
--   * service_role: CRUD everywhere, for admin/server tooling. It bypasses
--     RLS; the SQL Editor runs as postgres and is unaffected either way.
--
-- New tables MUST add their own grant (or an explicit revoke) in the
-- migration that creates them. lint_migrations.sh enforces this.

-- PowerSync-synced tables (one line each in infra/powersync-sync-rules.yaml)
revoke all on table public.dive_annotations from anon, authenticated, service_role;
grant select, insert, update, delete on table public.dive_annotations to authenticated, service_role;

revoke all on table public.cylinders from anon, authenticated, service_role;
grant select, insert, update, delete on table public.cylinders to authenticated, service_role;

revoke all on table public.oxygen_cells from anon, authenticated, service_role;
grant select, insert, update, delete on table public.oxygen_cells to authenticated, service_role;

revoke all on table public.scrubber_sessions from anon, authenticated, service_role;
grant select, insert, update, delete on table public.scrubber_sessions to authenticated, service_role;

revoke all on table public.pressure_mappings from anon, authenticated, service_role;
grant select, insert, update, delete on table public.pressure_mappings to authenticated, service_role;

revoke all on table public.dive_cylinders from anon, authenticated, service_role;
grant select, insert, update, delete on table public.dive_cylinders to authenticated, service_role;

revoke all on table public.dive_computers from anon, authenticated, service_role;
grant select, insert, update, delete on table public.dive_computers to authenticated, service_role;

revoke all on table public.dives from anon, authenticated, service_role;
grant select, insert, update, delete on table public.dives to authenticated, service_role;

revoke all on table public.dive_samples from anon, authenticated, service_role;
grant select, insert, update, delete on table public.dive_samples to authenticated, service_role;

revoke all on table public.dive_attachments from anon, authenticated, service_role;
grant select, insert, update, delete on table public.dive_attachments to authenticated, service_role;

revoke all on table public.dive_bailout_carry from anon, authenticated, service_role;
grant select, insert, update, delete on table public.dive_bailout_carry to authenticated, service_role;

revoke all on table public.dive_plans from anon, authenticated, service_role;
grant select, insert, update, delete on table public.dive_plans to authenticated, service_role;

revoke all on table public.dive_merge_links from anon, authenticated, service_role;
grant select, insert, update, delete on table public.dive_merge_links to authenticated, service_role;

-- Write-only telemetry (not synced)
revoke all on table public.usage_events from anon, authenticated, service_role;
grant insert on table public.usage_events to authenticated;
grant select, insert, update, delete on table public.usage_events to service_role;

-- Opt in to the new behaviour now, rather than on 2026-10-30. Tables
-- created by postgres (i.e. these migrations) no longer auto-grant
-- anything, so a migration that forgets its grant fails immediately
-- instead of weeks later. Supabase's recommended opt-in SQL only revokes
-- the CRUD/usage privileges. `all` also drops the TRUNCATE / REFERENCES /
-- TRIGGER defaults, so a new table starts from zero and gets only what
-- its migration grants. Revoking an absent default privilege is a no-op,
-- so this is idempotent.
alter default privileges for role postgres in schema public
  revoke all on tables from anon, authenticated, service_role;
alter default privileges for role postgres in schema public
  revoke all on sequences from anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';
