-- Phase 2.5 cloud schema. Imported dive metadata + parsed samples now
-- sync via PowerSync so a dive imported on one device shows up on every
-- other signed-in device of the same user. Raw binary blobs stay
-- device-local (only useful for re-parsing after a parser bug fix; not
-- worth the bandwidth/storage to sync), so this schema deliberately
-- omits raw_blob.
--
-- Sample blobs are gzipped Float32 columnar binary in Drift; PowerSync's
-- column types only cover text/integer/real, so we store them as
-- base64-encoded text and decode at the seam (mirrors how dive_annotations
-- handles jsonb in 0001_initial_schema.sql).

-- dives ----------------------------------------------------------------------
create table dives (
  id text primary key,
  owner_id uuid not null references auth.users(id) on delete cascade,

  dc_serial bigint not null,
  dc_dive_number integer not null,
  start_time bigint not null,
  end_time bigint not null,
  utc_offset_minutes integer,
  duration_seconds integer not null,
  max_depth_mm integer not null,
  dive_mode integer not null,
  deco_model integer not null,
  gf_low integer,
  gf_high integer,
  atmospheric_pressure_mbar integer not null,
  water_density integer not null,
  log_version integer not null,
  dc_model integer not null,
  dc_firmware integer,
  sample_interval_ms integer not null,
  gas_mixes_json text not null,
  tanks_json text,
  configured_stack_seconds integer,
  stack_remaining_at_start_seconds integer,
  stack_remaining_at_end_seconds integer,
  parser_version integer not null,
  imported_at bigint not null,
  subsurface_uploaded_at bigint,
  deleted_at bigint,
  version integer not null default 1,
  sync_status integer not null default 0
);

alter table dives enable row level security;
create policy "owner_full_access"
  on dives for all
  using (auth.uid() = owner_id)
  with check (auth.uid() = owner_id);

create index dives_owner_id_idx on dives (owner_id);

-- dive_samples ---------------------------------------------------------------
-- 1:1 with dives. Blobs are base64-encoded gzipped Float32 channels.
-- tank_pressures_blob is null for OC dives + pre-v6 imports.
create table dive_samples (
  dive_id text primary key references dives(id) on delete cascade,
  owner_id uuid not null references auth.users(id) on delete cascade,
  sample_count integer not null,
  depth_blob text not null,
  temperature_blob text not null,
  ppo2_blob text not null,
  cell_mv0_blob text not null,
  cell_mv1_blob text not null,
  cell_mv2_blob text not null,
  setpoint_blob text not null,
  cns_blob text not null,
  deco_depth_blob text not null,
  deco_time_blob text not null,
  tts_blob text not null,
  gas_mix_idx_blob text not null,
  status_blob text not null,
  tank_pressures_blob text,
  created_at bigint not null,
  updated_at bigint not null,
  version integer not null default 1,
  sync_status integer not null default 0
);

alter table dive_samples enable row level security;
create policy "owner_full_access"
  on dive_samples for all
  using (auth.uid() = owner_id)
  with check (auth.uid() = owner_id);

create index dive_samples_owner_id_idx on dive_samples (owner_id);

-- PowerSync publication ------------------------------------------------------
-- Add the two new tables to the existing publication so logical
-- replication picks them up. (`alter publication ... add table` is the
-- idempotent-ish way; safer than recreating the publication.)
alter publication powersync add table dives, dive_samples;
