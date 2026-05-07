-- Operational diagnostics for the cloud sync Postgres.
-- Paste any of these into the Supabase SQL Editor when something feels off.
--
-- The disk-overflow incident on 2026-05-07 was caused by an inactive
-- PowerSync logical replication slot holding back WAL. None of these are
-- automated — they're a checklist for the operator (you).

-- 1. Disk usage of the database, by relation. WAL doesn't appear here;
--    if total table+index size is small but the project is full, suspect
--    WAL bloat from a stuck replication slot (query 2).
select
  schemaname,
  relname,
  pg_size_pretty(pg_total_relation_size(relid)) as total_size,
  pg_size_pretty(pg_relation_size(relid))       as table_size,
  pg_size_pretty(pg_indexes_size(relid))        as indexes_size
from pg_catalog.pg_statio_user_tables
order by pg_total_relation_size(relid) desc;

-- 2. Replication slots. PowerSync owns one. If `active = false` and
--    `lag` is more than a few MB, WAL is piling up — drop the slot
--    (query 3) and re-add the source connection in PowerSync.
select
  slot_name,
  slot_type,
  active,
  restart_lsn,
  pg_size_pretty(
    pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)
  ) as lag
from pg_replication_slots;

-- 3. Drop a stuck replication slot. Only run if the slot is not active
--    and you're sure PowerSync is disconnected. After dropping, re-add
--    the source DB connection in the PowerSync dashboard.
-- select pg_drop_replication_slot('REPLACE_WITH_SLOT_NAME_FROM_QUERY_2');

-- 4. Reclaim freed space after dropping a slot. Postgres usually does
--    this on the next checkpoint; this just forces it.
-- checkpoint;

-- 5. Auth users — how many people have signed up. Useful for sanity
--    when something seems off after a fresh project bring-up.
select id, email, created_at, last_sign_in_at
from auth.users
order by created_at desc;

-- 6. Row counts per sync-eligible table. Should match what your app
--    shows; large discrepancies suggest a sync rules / replication issue.
select 'dive_annotations'   as table_name, count(*) from dive_annotations  union all
select 'cylinders',                         count(*) from cylinders         union all
select 'oxygen_cells',                      count(*) from oxygen_cells      union all
select 'scrubber_sessions',                 count(*) from scrubber_sessions union all
select 'pressure_mappings',                 count(*) from pressure_mappings union all
select 'dive_cylinders',                    count(*) from dive_cylinders    union all
select 'dive_computers',                    count(*) from dive_computers;
