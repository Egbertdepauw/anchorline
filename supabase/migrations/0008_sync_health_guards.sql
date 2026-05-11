-- Sync-health guards against the WAL-fill class of failure we hit on
-- 2026-05-08 (stuck PowerSync replication slot pinning WAL until the
-- NANO-tier disk filled and Postgres refused all connections).
--
-- Three layers of defence, applied via the Management API (this file
-- documents them so a fresh project bootstrap reproduces the setup):
--
-- 1. `max_slot_wal_keep_size = 1GB` and `max_wal_size = 1GB` —
--    both set via `PUT /v1/projects/{ref}/config/database/postgres`.
--    The first invalidates a stuck slot once retained WAL hits 1 GB
--    (PowerSync re-bootstraps clients on next reconnect — one-time
--    re-download, no data loss). The second caps Postgres's own WAL
--    working set so a traffic spike can't push us above the disk
--    quota. Supabase enforces a 1 GB MINIMUM on `max_wal_size`, so
--    that floor is also the most aggressive cap we can set; 4 GB is
--    the platform default and it dwarfed our 30 MB of user data.
--
-- 2. `reap_stale_replication_slots()` + pg_cron schedule (every 15
--    min). Defence-in-depth: drops slots that are inactive AND
--    either marked `wal_status='lost'` (already invalidated by layer
--    1) or holding >500 MB of WAL. SECURITY DEFINER so the function
--    can call pg_drop_replication_slot regardless of caller role.
--
-- 3. `public.sync_health_check()` RPC exposed to authenticated users.
--    The app polls this and surfaces a banner if retention crosses
--    a warn threshold long before layers 1/2 kick in.

create extension if not exists pg_cron;

create or replace function public.reap_stale_replication_slots()
returns void
language plpgsql
security definer
as $$
declare
  rec record;
begin
  for rec in
    select
      slot_name,
      wal_status,
      pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn) as retained_bytes
    from pg_replication_slots
    where not active
      and (
        wal_status = 'lost'
        or pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn) > 500 * 1024 * 1024
      )
  loop
    raise notice
      'reap_stale_replication_slots: dropping % (wal_status=%, retained_bytes=%)',
      rec.slot_name, rec.wal_status, rec.retained_bytes;
    perform pg_drop_replication_slot(rec.slot_name);
  end loop;
end;
$$;

revoke all on function public.reap_stale_replication_slots() from public;

-- Idempotent: cron.schedule errors if a job with this name already
-- exists. Drop first so this migration is safe to re-apply.
select cron.unschedule('reap-stale-replication-slots')
where exists (
  select 1 from cron.job where jobname = 'reap-stale-replication-slots'
);
select cron.schedule(
  'reap-stale-replication-slots',
  '*/15 * * * *',
  'select public.reap_stale_replication_slots();'
);

-- ─────────────────────────────────────────────────────────────────
-- Layer 3: app-callable health snapshot.

create or replace function public.sync_health_check()
returns table (
  slot_name text,
  active boolean,
  wal_status text,
  retained_mb bigint
)
language sql
security definer
stable
as $$
  select
    slot_name::text,
    active,
    wal_status::text,
    (pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn) / (1024 * 1024))::bigint
      as retained_mb
  from pg_replication_slots
$$;

revoke all on function public.sync_health_check() from public;
grant execute on function public.sync_health_check() to authenticated;
