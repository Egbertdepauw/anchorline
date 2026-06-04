-- Multilevel dive plans. Single table; one "draft" row per user
-- (name IS NULL), unbounded named saved plans. Body is JSON-encoded
-- (gases / segments / bailout bottles / settings overrides) because
-- those subdocs are always loaded as a unit.
CREATE TABLE IF NOT EXISTS dive_plans (
  id text PRIMARY KEY,
  owner_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name text,                       -- NULL = draft, non-NULL = saved plan
  mode text NOT NULL,              -- 'cc' or 'oc' (v1 ships 'cc' only)
  gases_json text NOT NULL,
  segments_json text NOT NULL,
  bailout_json text NOT NULL,
  settings_json text,              -- per-plan overrides; NULL = use globals
  notes text,
  created_at bigint NOT NULL,
  updated_at bigint NOT NULL,
  deleted_at bigint,
  version integer NOT NULL DEFAULT 1,
  sync_status integer NOT NULL DEFAULT 0
);

-- One draft per user — enforced server-side as well as locally.
CREATE UNIQUE INDEX IF NOT EXISTS idx_dive_plans_owner_draft
  ON dive_plans (owner_id)
  WHERE name IS NULL AND deleted_at IS NULL;

-- Saved-plans browser query: ORDER BY updated_at DESC for one user.
CREATE INDEX IF NOT EXISTS idx_dive_plans_owner_updated
  ON dive_plans (owner_id, deleted_at, updated_at DESC);

ALTER TABLE dive_plans ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner can rw" ON dive_plans;
CREATE POLICY "owner can rw" ON dive_plans
  USING (auth.uid() = owner_id)
  WITH CHECK (auth.uid() = owner_id);

-- PowerSync subscribes to logical replication via the `powersync`
-- publication. New tables must be added explicitly so changes start
-- flowing.
do $$
begin
  if not exists (select 1 from pg_publication_tables
                 where pubname = 'powersync' and schemaname = 'public' and tablename = 'dive_plans') then
    execute 'alter publication powersync add table public.dive_plans';
  end if;
end $$;

NOTIFY pgrst, 'reload schema';
