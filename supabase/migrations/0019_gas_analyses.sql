-- Cylinder analysis log (issue #111). One row per gas-analyzer reading the
-- diver saved: what was in which cylinder, measured when, by whom.
--
-- Stored: the measured numbers at the analyzer's full precision (O2/He %,
-- temperature, ambient pressure), the fill pressure the diver typed, the
-- `stable` flag (0/1, the analyzer's stability state at save time), and the
-- ppO2 set the MODs were shown for (`mod_ppo2s`, JSON array of bar values,
-- e.g. "[1.1,1.4,1.6]"; it's a per-user setting that can change later).
-- Derived, NOT stored: the mix label and the MOD depths. Both are pure
-- functions of o2_percent (+ he_percent), so storing them could only drift.
--
-- cylinder_id is a SOFT reference to cylinders.id (nullable, no FK). An
-- analysis is a safety record and must never be lost: with an enforced FK, a
-- cylinder row that never reached the cloud would make the upload connector
-- drop or wedge the analysis. Cylinders are soft-deleted, so the label stays
-- resolvable by a join; a dangling id just shows as "unknown cylinder".
--
-- Timestamps are millis since epoch (bigint), like every other synced table.
CREATE TABLE IF NOT EXISTS gas_analyses (
  id text PRIMARY KEY,
  owner_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  cylinder_id text,
  analysed_by text,
  analysed_at bigint NOT NULL,
  o2_percent double precision NOT NULL,
  he_percent double precision NOT NULL DEFAULT 0,
  fill_pressure_bar double precision,
  temp_c double precision,
  baro_hpa double precision,
  mod_ppo2s text,
  stable integer NOT NULL DEFAULT 0,
  notes text,
  created_at bigint NOT NULL,
  updated_at bigint NOT NULL,
  deleted_at bigint,
  version integer NOT NULL DEFAULT 1,
  sync_status integer NOT NULL DEFAULT 0
);

-- Log query: newest first for one user, optionally per cylinder.
CREATE INDEX IF NOT EXISTS idx_gas_analyses_owner_analysed
  ON gas_analyses (owner_id, deleted_at, analysed_at DESC);
CREATE INDEX IF NOT EXISTS idx_gas_analyses_owner_cylinder
  ON gas_analyses (owner_id, cylinder_id);

ALTER TABLE gas_analyses ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner can rw" ON gas_analyses;
CREATE POLICY "owner can rw" ON gas_analyses
  USING (auth.uid() = owner_id)
  WITH CHECK (auth.uid() = owner_id);

-- Explicit Data API grants (issue #76): Supabase no longer auto-grants new
-- tables. The PowerSync upload connector writes as `authenticated`.
revoke all on table public.gas_analyses from anon, authenticated, service_role;
grant select, insert, update, delete on table public.gas_analyses to authenticated, service_role;

-- PowerSync subscribes to logical replication via the `powersync`
-- publication. New tables must be added explicitly so changes start flowing.
do $$
begin
  if not exists (select 1 from pg_publication_tables
                 where pubname = 'powersync' and schemaname = 'public' and tablename = 'gas_analyses') then
    execute 'alter publication powersync add table public.gas_analyses';
  end if;
end $$;

NOTIFY pgrst, 'reload schema';
