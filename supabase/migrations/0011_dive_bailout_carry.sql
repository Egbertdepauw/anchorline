-- Cylinders are physical vessels — what gas they hold is recorded per dive.
ALTER TABLE cylinders DROP COLUMN IF EXISTS gas_mix;

-- One row per (dive_id, cylinder_id) the diver carried as OC bailout on this
-- dive. id is "{dive_id}:{cylinder_id}" (PowerSync-friendly synthetic PK).
-- fill_pressure_bar nullable: NULL means "assume cylinder.working_pressure_bar
-- (full)".
CREATE TABLE dive_bailout_carry (
  id text PRIMARY KEY,
  owner_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  dive_id text NOT NULL REFERENCES dives(id),
  cylinder_id text NOT NULL REFERENCES cylinders(id),
  gas_mix text NOT NULL,
  fill_pressure_bar integer,
  bailout_order integer NOT NULL,
  created_at bigint NOT NULL,
  updated_at bigint NOT NULL,
  deleted_at bigint,
  version integer NOT NULL DEFAULT 1,
  sync_status integer NOT NULL DEFAULT 0
);

CREATE INDEX idx_dive_bailout_carry_owner_dive
  ON dive_bailout_carry (owner_id, dive_id);

ALTER TABLE dive_bailout_carry ENABLE ROW LEVEL SECURITY;
CREATE POLICY "owner can rw" ON dive_bailout_carry
  USING (auth.uid() = owner_id)
  WITH CHECK (auth.uid() = owner_id);

-- PowerSync subscribes to logical replication via the `powersync` publication.
-- New tables must be added explicitly so changes start flowing.
ALTER PUBLICATION powersync ADD TABLE "public"."dive_bailout_carry";

NOTIFY pgrst, 'reload schema';
