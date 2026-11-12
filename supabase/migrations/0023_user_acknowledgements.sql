-- Things the diver has read and accepted (issue #184). One row per
-- acceptance: which text (`subject`, e.g. 'planner_warning') at which
-- version (`text_version`), and when. The app treats a subject as accepted
-- when a live row exists at the version it currently ships; bumping the
-- version in the app asks again.
--
-- Synced per account (CLAUDE.md principle 7): accept the planner warning on
-- the iPhone and the Mac doesn't ask. Rows are only ever added; two devices
-- accepting the same text leave two rows, which is harmless.
--
-- Timestamps are millis since epoch (bigint), like every other synced table.
CREATE TABLE IF NOT EXISTS user_acknowledgements (
  id text PRIMARY KEY,
  owner_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  subject text NOT NULL,
  text_version integer NOT NULL,
  accepted_at bigint NOT NULL,
  created_at bigint NOT NULL,
  updated_at bigint NOT NULL,
  deleted_at bigint,
  version integer NOT NULL DEFAULT 1,
  sync_status integer NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_user_acknowledgements_owner_subject
  ON user_acknowledgements (owner_id, subject, text_version);

ALTER TABLE user_acknowledgements ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner can rw" ON user_acknowledgements;
CREATE POLICY "owner can rw" ON user_acknowledgements
  USING (auth.uid() = owner_id)
  WITH CHECK (auth.uid() = owner_id);

-- Explicit Data API grants (issue #76): Supabase no longer auto-grants new
-- tables. The PowerSync upload connector writes as `authenticated`.
revoke all on table public.user_acknowledgements from anon, authenticated, service_role;
grant select, insert, update, delete on table public.user_acknowledgements to authenticated, service_role;

-- PowerSync subscribes to logical replication via the `powersync`
-- publication. New tables must be added explicitly so changes start flowing.
do $$
begin
  if not exists (select 1 from pg_publication_tables
                 where pubname = 'powersync' and schemaname = 'public' and tablename = 'user_acknowledgements') then
    execute 'alter publication powersync add table public.user_acknowledgements';
  end if;
end $$;

NOTIFY pgrst, 'reload schema';
