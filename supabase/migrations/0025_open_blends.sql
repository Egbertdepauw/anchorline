-- Open blends (issue #112): a blend the diver has logged on the Blend tab
-- and not yet closed with an analysis. The Analyse card closes one by
-- setting closed_by_analysis_id to the analysis that measured it; an open
-- blend is one with no closing analysis (or whose closing analysis was
-- deleted). Dismissing a blend soft-deletes it.
--
-- closed_by_analysis_id is a SOFT reference to gas_analyses.id (no foreign
-- key), like gas_analyses.cylinder_id: upload order can't fail, and the
-- connector's orphan-drop logic never touches it.
--
-- target_* is the mix the diver wanted, residual_* what was left in the
-- cylinder before the fill, topoff_* the mix topped off with (whole percents;
-- pressures in bar, water_capacity_l in litres). gas_role is 'bailout',
-- 'diluent', 'backgas' or 'deco'; the app reads any other value as bailout.
--
-- Synced per account (CLAUDE.md principle 7). Timestamps are millis since
-- epoch (bigint), like every other synced table.
--
-- Also adds gas_analyses.is_residual: 0/1 (integer), NOT NULL DEFAULT 0. 1
-- marks an analysis of what was left in the cylinder before a fill; it closes
-- no blend. Rows from an older build read as 0.
--
-- Deploy this BEFORE shipping a build that writes these: the upload connector
-- sends whole rows, so Supabase rejects uploads from a newer build until the
-- table and column exist.
CREATE TABLE IF NOT EXISTS open_blends (
  id text PRIMARY KEY,
  owner_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  target_o2_percent integer NOT NULL,
  target_he_percent integer NOT NULL,
  target_pressure_bar double precision NOT NULL,
  residual_o2_percent integer NOT NULL,
  residual_he_percent integer NOT NULL,
  residual_pressure_bar double precision NOT NULL,
  topoff_o2_percent integer NOT NULL,
  topoff_he_percent integer NOT NULL,
  water_capacity_l double precision NOT NULL,
  gas_role text NOT NULL,
  blended_by text,
  blended_at bigint NOT NULL,
  closed_by_analysis_id text,
  created_at bigint NOT NULL,
  updated_at bigint NOT NULL,
  deleted_at bigint,
  version integer NOT NULL DEFAULT 1,
  sync_status integer NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_open_blends_owner_deleted
  ON open_blends (owner_id, deleted_at);

ALTER TABLE open_blends ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner can rw" ON open_blends;
CREATE POLICY "owner can rw" ON open_blends
  USING (auth.uid() = owner_id)
  WITH CHECK (auth.uid() = owner_id);

-- Explicit Data API grants (issue #76): Supabase no longer auto-grants new
-- tables. The PowerSync upload connector writes as `authenticated`.
revoke all on table public.open_blends from anon, authenticated, service_role;
grant select, insert, update, delete on table public.open_blends to authenticated, service_role;

-- PowerSync subscribes to logical replication via the `powersync`
-- publication. New tables must be added explicitly so changes start flowing.
do $$
begin
  if not exists (select 1 from pg_publication_tables
                 where pubname = 'powersync' and schemaname = 'public' and tablename = 'open_blends') then
    execute 'alter publication powersync add table public.open_blends';
  end if;
end $$;

ALTER TABLE gas_analyses ADD COLUMN IF NOT EXISTS is_residual integer NOT NULL DEFAULT 0;

NOTIFY pgrst, 'reload schema';
