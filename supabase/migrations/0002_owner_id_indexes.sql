-- Phase 2.2c follow-up: indexes on owner_id for RLS + PowerSync replication.
--
-- Every read of these tables filters by `auth.uid() = owner_id` (RLS) and
-- PowerSync's bucket-per-user sync rules also key on owner_id. Without an
-- index, each row check is a sequential scan; on free-tier compute this
-- starves auth queries and produces "Database error querying schema".
--
-- The composite-PK tables (pressure_mappings, dive_cylinders,
-- dive_computers) already have covering indexes via their
-- `unique (owner_id, ...)` constraints, so they're omitted here.

create index if not exists dive_annotations_owner_id_idx
  on dive_annotations (owner_id);

create index if not exists cylinders_owner_id_idx
  on cylinders (owner_id);

create index if not exists oxygen_cells_owner_id_idx
  on oxygen_cells (owner_id);

create index if not exists scrubber_sessions_owner_id_idx
  on scrubber_sessions (owner_id);
