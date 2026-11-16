-- libdivecomputer phase 1, storage groundwork. Adds the columns a refreshed or
-- non-Shearwater dive needs, keys dive_computers by vendor as well as serial,
-- and guards against an older reader overwriting a newer parse.
--
-- dives: brand fields (`dc_vendor`, `dc_product`, `dc_family`,
-- `dc_model_code`) and the Subsurface-copy match candidates. All nullable and
-- not backfilled: a NULL `dc_vendor` means "Shearwater" on a download and
-- "unknown" on a Subsurface copy. Backfilling would replicate every dive to
-- every device for a value the app can derive.
--
-- dive_samples: `cell_ppo2_blob` (per-cell ppO2), `events_blob`, and the
-- `parser_version` / `dc_family` the blobs were written by.
--
-- dive_computers: brand fields, and the unique key moves from
-- (owner_id, serial) to (owner_id, dc_vendor, serial) so two vendors can share
-- a serial number.
--
-- dive_bailout_carry: `dc_family`, a copy of the dive's, so the sync gate can
-- filter carry rows without joining dives.
--
-- keep_newer_parse(): a before-update trigger on dives and dive_samples. An
-- older build (1.1.0+47 and earlier) or a device that has not synced yet must
-- never lower a refreshed row's parser_version or replace its data with an
-- older parse.

-- dives ----------------------------------------------------------------------
ALTER TABLE public.dives ADD COLUMN IF NOT EXISTS dc_vendor text;
ALTER TABLE public.dives ADD COLUMN IF NOT EXISTS dc_product text;
ALTER TABLE public.dives ADD COLUMN IF NOT EXISTS dc_family integer;
ALTER TABLE public.dives ADD COLUMN IF NOT EXISTS dc_model_code integer;
ALTER TABLE public.dives ADD COLUMN IF NOT EXISTS match_candidates_json text;

-- dive_samples ---------------------------------------------------------------
ALTER TABLE public.dive_samples ADD COLUMN IF NOT EXISTS cell_ppo2_blob text;
ALTER TABLE public.dive_samples ADD COLUMN IF NOT EXISTS events_blob text;
ALTER TABLE public.dive_samples ADD COLUMN IF NOT EXISTS parser_version integer;
ALTER TABLE public.dive_samples ADD COLUMN IF NOT EXISTS dc_family integer;

-- dive_bailout_carry ---------------------------------------------------------
ALTER TABLE public.dive_bailout_carry ADD COLUMN IF NOT EXISTS dc_family integer;

-- dive_computers -------------------------------------------------------------
ALTER TABLE public.dive_computers ADD COLUMN IF NOT EXISTS dc_vendor text;
ALTER TABLE public.dive_computers ADD COLUMN IF NOT EXISTS dc_product text;
ALTER TABLE public.dive_computers ADD COLUMN IF NOT EXISTS dc_family integer;
ALTER TABLE public.dive_computers ADD COLUMN IF NOT EXISTS dc_model_code integer;

-- Every existing computer is a Shearwater (the only brand before this).
UPDATE public.dive_computers SET dc_vendor = 'Shearwater' WHERE dc_vendor IS NULL;
ALTER TABLE public.dive_computers ALTER COLUMN dc_vendor SET DEFAULT 'Shearwater';
ALTER TABLE public.dive_computers ALTER COLUMN dc_vendor SET NOT NULL;

ALTER TABLE public.dive_computers DROP CONSTRAINT IF EXISTS dive_computers_owner_id_serial_key;
CREATE UNIQUE INDEX IF NOT EXISTS dive_computers_owner_vendor_serial_key
  ON public.dive_computers (owner_id, dc_vendor, serial);

-- keep_newer_parse -----------------------------------------------------------
-- Created after the columns above: the dive_samples trigger reads the new
-- parser_version.
create or replace function public.keep_newer_parse() returns trigger
language plpgsql set search_path = public as $$
begin
  -- A Subsurface copy (-1) may be replaced by any reader. Otherwise an
  -- update may never lower parser_version: an older reader's upload
  -- (an old build, or a device that hadn't synced yet) keeps the newer
  -- row. Returning OLD makes the update a no-op; the uploading client
  -- gets the server row back through sync.
  if old.parser_version is not null and new.parser_version is not null
     and old.parser_version >= 0
     and new.parser_version < old.parser_version then
    return old;
  end if;

  -- dive_samples only: builds from before this migration upload with an
  -- upsert (INSERT ... ON CONFLICT (id) DO UPDATE SET <payload columns>)
  -- that never names dive_samples.parser_version, so NEW keeps OLD's value
  -- and the rule above cannot fire. Without this, such a build replaces a
  -- refreshed row's blobs with its older parse while dives stays current,
  -- a mixed pair no later refresh repairs. So: at an equal (or omitted)
  -- version, a change to any imported data column is refused. A change
  -- that carries a higher version is a real refresh and goes through.
  -- dives is deliberately not covered: same-version PATCHes of dives
  -- (deleted_at, user fields) must still apply.
  if tg_table_name = 'dive_samples'
     and old.parser_version is not null and old.parser_version >= 0
     and (new.parser_version is null or new.parser_version = old.parser_version)
     and (new.sample_count, new.depth_blob, new.temperature_blob, new.ppo2_blob,
          new.cell_mv0_blob, new.cell_mv1_blob, new.cell_mv2_blob,
          new.setpoint_blob, new.cns_blob, new.deco_depth_blob,
          new.deco_time_blob, new.tts_blob, new.gas_mix_idx_blob,
          new.status_blob, new.tank_pressures_blob, new.cell_ppo2_blob,
          new.events_blob)
         is distinct from
         (old.sample_count, old.depth_blob, old.temperature_blob, old.ppo2_blob,
          old.cell_mv0_blob, old.cell_mv1_blob, old.cell_mv2_blob,
          old.setpoint_blob, old.cns_blob, old.deco_depth_blob,
          old.deco_time_blob, old.tts_blob, old.gas_mix_idx_blob,
          old.status_blob, old.tank_pressures_blob, old.cell_ppo2_blob,
          old.events_blob) then
    return old;
  end if;
  return new;
end $$;

drop trigger if exists dives_keep_newer_parse on public.dives;
create trigger dives_keep_newer_parse
  before update on public.dives
  for each row execute function public.keep_newer_parse();

drop trigger if exists dive_samples_keep_newer_parse on public.dive_samples;
create trigger dive_samples_keep_newer_parse
  before update on public.dive_samples
  for each row execute function public.keep_newer_parse();

-- Explicit Data API grants (issue #76), restated for the tables this touches.
revoke all on table public.dives from anon, authenticated, service_role;
grant select, insert, update, delete on table public.dives to authenticated, service_role;
revoke all on table public.dive_samples from anon, authenticated, service_role;
grant select, insert, update, delete on table public.dive_samples to authenticated, service_role;
revoke all on table public.dive_computers from anon, authenticated, service_role;
grant select, insert, update, delete on table public.dive_computers to authenticated, service_role;
revoke all on table public.dive_bailout_carry from anon, authenticated, service_role;
grant select, insert, update, delete on table public.dive_bailout_carry to authenticated, service_role;

NOTIFY pgrst, 'reload schema';
