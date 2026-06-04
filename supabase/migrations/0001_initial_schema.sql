-- Phase 2.0 cloud schema. Mirrors the sync-eligible Drift tables.
-- Each table is owned by exactly one Supabase auth user (owner_id) and
-- protected by row-level security keyed on auth.uid().
--
-- Composite-PK Drift tables (pressure_mappings, dive_cylinders) get a
-- synthetic id column here; the client composes it at sync time.

-- dive_annotations -----------------------------------------------------------
create table if not exists dive_annotations (
  id text primary key,
  owner_id uuid not null references auth.users(id) on delete cascade,
  dive_id text not null,
  site_name text,
  site_latitude_e5 integer,
  site_longitude_e5 integer,
  notes text,
  buddies_json jsonb,
  tags_json jsonb,
  rating integer,
  conditions text,
  created_at bigint not null,
  updated_at bigint not null,
  deleted_at bigint,
  version integer not null default 1,
  sync_status integer not null default 0
);

alter table dive_annotations enable row level security;
drop policy if exists "owner_full_access" on dive_annotations;
create policy "owner_full_access"
  on dive_annotations for all
  using (auth.uid() = owner_id)
  with check (auth.uid() = owner_id);

-- cylinders ------------------------------------------------------------------
create table if not exists cylinders (
  id text primary key,
  owner_id uuid not null references auth.users(id) on delete cascade,
  label text not null,
  role text not null,
  bailout_order integer,
  volume_liters double precision not null,
  working_pressure_bar integer not null,
  gas_mix text,
  notes text,
  created_at bigint not null,
  updated_at bigint not null,
  deleted_at bigint,
  version integer not null default 1,
  sync_status integer not null default 0
);

alter table cylinders enable row level security;
drop policy if exists "owner_full_access" on cylinders;
create policy "owner_full_access"
  on cylinders for all
  using (auth.uid() = owner_id)
  with check (auth.uid() = owner_id);

-- oxygen_cells ---------------------------------------------------------------
create table if not exists oxygen_cells (
  id text primary key,
  owner_id uuid not null references auth.users(id) on delete cascade,
  slot integer not null,
  label text,
  installed_date bigint,
  retired_date bigint,
  notes text,
  created_at bigint not null,
  updated_at bigint not null,
  deleted_at bigint,
  version integer not null default 1,
  sync_status integer not null default 0
);

alter table oxygen_cells enable row level security;
drop policy if exists "owner_full_access" on oxygen_cells;
create policy "owner_full_access"
  on oxygen_cells for all
  using (auth.uid() = owner_id)
  with check (auth.uid() = owner_id);

-- scrubber_sessions ----------------------------------------------------------
create table if not exists scrubber_sessions (
  id text primary key,
  owner_id uuid not null references auth.users(id) on delete cascade,
  started_date bigint,
  total_minutes integer,
  media_type text,
  notes text,
  created_at bigint not null,
  updated_at bigint not null,
  deleted_at bigint,
  version integer not null default 1,
  sync_status integer not null default 0
);

alter table scrubber_sessions enable row level security;
drop policy if exists "owner_full_access" on scrubber_sessions;
create policy "owner_full_access"
  on scrubber_sessions for all
  using (auth.uid() = owner_id)
  with check (auth.uid() = owner_id);

-- pressure_mappings ----------------------------------------------------------
-- Drift PK is composite (dive_computer_id, channel_index); we synthesize
-- `id` as "<dive_computer_id>:<channel_index>" client-side at sync time.
create table if not exists pressure_mappings (
  id text primary key,
  owner_id uuid not null references auth.users(id) on delete cascade,
  dive_computer_id text not null,
  channel_index integer not null,
  cylinder_id text,
  created_at bigint not null,
  updated_at bigint not null,
  deleted_at bigint,
  version integer not null default 1,
  sync_status integer not null default 0,
  unique (owner_id, dive_computer_id, channel_index)
);

alter table pressure_mappings enable row level security;
drop policy if exists "owner_full_access" on pressure_mappings;
create policy "owner_full_access"
  on pressure_mappings for all
  using (auth.uid() = owner_id)
  with check (auth.uid() = owner_id);

-- dive_cylinders -------------------------------------------------------------
-- Drift PK is composite (dive_id, gas_mix_index); synthesized as
-- "<dive_id>:<gas_mix_index>" at sync time.
create table if not exists dive_cylinders (
  id text primary key,
  owner_id uuid not null references auth.users(id) on delete cascade,
  dive_id text not null,
  gas_mix_index integer not null,
  cylinder_id text,
  created_at bigint not null,
  updated_at bigint not null,
  deleted_at bigint,
  version integer not null default 1,
  sync_status integer not null default 0,
  unique (owner_id, dive_id, gas_mix_index)
);

alter table dive_cylinders enable row level security;
drop policy if exists "owner_full_access" on dive_cylinders;
create policy "owner_full_access"
  on dive_cylinders for all
  using (auth.uid() = owner_id)
  with check (auth.uid() = owner_id);

-- dive_computers -------------------------------------------------------------
create table if not exists dive_computers (
  id text primary key,
  owner_id uuid not null references auth.users(id) on delete cascade,
  serial bigint not null,
  model integer not null,
  firmware_version integer,
  nickname text,
  created_at bigint not null,
  updated_at bigint not null,
  deleted_at bigint,
  version integer not null default 1,
  sync_status integer not null default 0,
  unique (owner_id, serial)
);

alter table dive_computers enable row level security;
drop policy if exists "owner_full_access" on dive_computers;
create policy "owner_full_access"
  on dive_computers for all
  using (auth.uid() = owner_id)
  with check (auth.uid() = owner_id);

-- PowerSync publication ------------------------------------------------------
create publication powersync for table dive_annotations, cylinders,
  oxygen_cells, scrubber_sessions, pressure_mappings, dive_cylinders,
  dive_computers;
