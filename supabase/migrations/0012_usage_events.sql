-- Anonymous, opt-out beta-usage telemetry. Records `user did feature X
-- at time T` events so we can prioritise paid-tier features based on
-- actual usage instead of guesses.
--
-- NOT synced via PowerSync (intentionally absent from
-- infra/powersync-sync-rules.yaml). It's a write-only stream from each
-- device into our analytics layer — no value in mirroring it to other
-- devices of the same user. Saves WAL volume on the NANO compute tier.
--
-- Schema:
--   id          uuid     — server-generated, unique per event
--   owner_id    uuid     — auth.users.id, nullable for pre-sign-in events
--                          (those are dropped by RLS; we don't want them
--                          anyway, see notes below)
--   event_name  text     — e.g. 'import_completed', 'dive_opened'
--   properties  jsonb    — free-form, per-event payload (counts, codes)
--   created_at  timestamptz — server clock; index target
--
-- RLS:
--   * `authenticated` role can INSERT rows where owner_id = auth.uid().
--     The UsageTracker client only fires when a session exists, so this
--     policy is the second line of defence.
--   * No SELECT / UPDATE / DELETE policy. Authenticated users cannot
--     read anyone's events (including their own) — this is purely a
--     one-way feed. We query the table via the Supabase SQL Editor /
--     Management API using the service role, which bypasses RLS.

create table if not exists usage_events (
  id         uuid primary key default gen_random_uuid(),
  owner_id   uuid references auth.users (id) on delete cascade,
  event_name text not null,
  properties jsonb,
  created_at timestamptz not null default now()
);

-- (owner_id, created_at desc) for "this user's recent events" queries.
-- (event_name, created_at desc) for "how often does event X fire" queries.
create index if not exists usage_events_owner_created
  on usage_events (owner_id, created_at desc);
create index if not exists usage_events_name_created
  on usage_events (event_name, created_at desc);

alter table usage_events enable row level security;

-- The only thing authenticated users are allowed to do: insert their
-- own rows. No SELECT, no UPDATE, no DELETE — telemetry is write-once
-- from the client side. We read it via the Editor.
drop policy if exists "owner_insert_only" on usage_events;
create policy "owner_insert_only"
  on usage_events
  for insert
  to authenticated
  with check (owner_id = auth.uid());
