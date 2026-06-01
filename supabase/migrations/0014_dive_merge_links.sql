-- Reversible "merge dives" grouping. Dives sharing a group_id display as one
-- merged dive (gap between them shown as a surface interval). A dive belongs to
-- at most one group, so the PK is the dive id itself — PowerSync's implicit
-- `id` column doubles as the dive id (same trick as dive_samples), so there is
-- NO separate dive_id column. group_id is a deterministic hash of the sorted
-- member dive ids (see generateMergeGroupId), not a pointer to a dive.
-- Unmerge is a soft delete (deleted_at), so it syncs and is undoable.
CREATE TABLE dive_merge_links (
  id text PRIMARY KEY REFERENCES dives(id),
  owner_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  group_id text NOT NULL,
  created_at bigint NOT NULL,
  updated_at bigint NOT NULL,
  deleted_at bigint,
  version integer NOT NULL DEFAULT 1,
  sync_status integer NOT NULL DEFAULT 0
);

CREATE INDEX idx_dive_merge_links_owner_group
  ON dive_merge_links (owner_id, group_id);

ALTER TABLE dive_merge_links ENABLE ROW LEVEL SECURITY;
CREATE POLICY "owner can rw" ON dive_merge_links
  USING (auth.uid() = owner_id)
  WITH CHECK (auth.uid() = owner_id);

-- PowerSync subscribes to logical replication via the `powersync` publication.
-- New tables must be added explicitly so changes start flowing.
ALTER PUBLICATION powersync ADD TABLE "public"."dive_merge_links";

NOTIFY pgrst, 'reload schema';
