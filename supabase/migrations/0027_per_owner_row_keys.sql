-- Per-owner row keys (spec: docs/superpowers/specs/
-- 2026-11-16-per-owner-row-keys-design.md).
--
-- Why: every synced table had `id text primary key`, but many ids are
-- computed from hardware or dive data only (dc_<serial>, the dive hash, the
-- ids derived from them). A second account with the same dive computer or
-- the same dive produced the same id, its upsert hit the first account's
-- row, RLS refused the update, and Postgres answered 42501 forever. The
-- upload queue then never drained.
--
-- What: all 16 synced tables are keyed by (owner_id, id). The four child
-- foreign keys (dive_samples.id, dive_bailout_carry.dive_id and
-- .cylinder_id, dive_merge_links.id) become composite and include owner_id,
-- so a child row always has its parent's owner. Delete behaviour is
-- unchanged. Client ids do not change.
--
-- Deploy only after a build with #233 (an account switch must not apply the
-- other account's queued changes) and this PR's app changes has shipped. See
-- supabase/README.md, "Before deploying 0027".
--
-- Guard: a child row whose parent does not exist for the same owner (it can
-- exist today, because a foreign-key check ignores RLS) stops the whole file
-- with an exception, so nothing half-applies and nothing is dropped
-- silently. After this migration the foreign keys keep those counts at zero,
-- so the file stays re-runnable.
--
-- Idempotent: a second run finds the keys and foreign keys in place and
-- changes nothing. Constraints are found in pg_constraint, never by a
-- hard-coded name. Creates no table; the grants are restated below.

-- A busy table makes this fail cleanly instead of queueing app traffic behind
-- the ACCESS EXCLUSIVE locks below; rerun at a quieter moment.
set local lock_timeout = '10s';

-- 1. Guard ---------------------------------------------------------------------
do $$
declare
  samples bigint;
  carry_dive bigint;
  carry_cylinder bigint;
  merge_links bigint;
begin
  select count(*) into samples from public.dive_samples s
    where not exists (select 1 from public.dives d
                      where d.owner_id = s.owner_id and d.id = s.id);
  select count(*) into carry_dive from public.dive_bailout_carry c
    where not exists (select 1 from public.dives d
                      where d.owner_id = c.owner_id and d.id = c.dive_id);
  select count(*) into carry_cylinder from public.dive_bailout_carry c
    where not exists (select 1 from public.cylinders y
                      where y.owner_id = c.owner_id and y.id = c.cylinder_id);
  select count(*) into merge_links from public.dive_merge_links m
    where not exists (select 1 from public.dives d
                      where d.owner_id = m.owner_id and d.id = m.id);

  if samples + carry_dive + carry_cylinder + merge_links > 0 then
    raise exception
      '0027 refused: child rows without a parent of the same owner (dive_samples -> dives: %, dive_bailout_carry -> dives: %, dive_bailout_carry -> cylinders: %, dive_merge_links -> dives: %); see supabase/README.md, Before deploying 0027',
      samples, carry_dive, carry_cylinder, merge_links;
  end if;
end $$;

-- Guard 2: PowerSync replicates these tables by REPLICA IDENTITY. A table set
-- to USING INDEX on its old id-only key would fall back to NOTHING when that
-- index is dropped below, and replication of updates and deletes would break.
do $$
declare bad text;
begin
  select string_agg(c.relname || ' (' || c.relreplident::text || ')', ', ' order by c.relname)
    into bad
  from pg_class c
  where c.relnamespace = 'public'::regnamespace
    and c.relname in (
      'dive_annotations', 'cylinders', 'oxygen_cells', 'scrubber_sessions',
      'pressure_mappings', 'dive_cylinders', 'dive_computers', 'dives',
      'dive_samples', 'dive_attachments', 'dive_bailout_carry', 'dive_plans',
      'dive_merge_links', 'gas_analyses', 'user_acknowledgements', 'open_blends')
    and c.relreplident <> 'd';
  if bad is not null then
    raise exception
      '0027 refused: REPLICA IDENTITY is not DEFAULT on: %; see supabase/README.md, Before deploying 0027',
      bad;
  end if;
end $$;

-- 2. Drop the single-column foreign keys into dives(id) and cylinders(id) -------
do $$
declare
  pair text[];
  con record;
begin
  foreach pair slice 1 in array array[
    array['dive_samples', 'dives'],
    array['dive_bailout_carry', 'dives'],
    array['dive_bailout_carry', 'cylinders'],
    array['dive_merge_links', 'dives']
  ] loop
    for con in
      select conname from pg_constraint
      where contype = 'f'
        and conrelid = format('public.%I', pair[1])::regclass
        and confrelid = format('public.%I', pair[2])::regclass
        and cardinality(conkey) = 1
    loop
      execute format('alter table public.%I drop constraint %I', pair[1], con.conname);
    end loop;
  end loop;
end $$;

-- 3. Re-key all 16 synced tables on (owner_id, id) ------------------------------
do $$
declare
  t text;
  pk_name text;
  pk_cols text[];
begin
  foreach t in array array[
    'dive_annotations', 'cylinders', 'oxygen_cells', 'scrubber_sessions',
    'pressure_mappings', 'dive_cylinders', 'dive_computers', 'dives',
    'dive_samples', 'dive_attachments', 'dive_bailout_carry', 'dive_plans',
    'dive_merge_links', 'gas_analyses', 'user_acknowledgements', 'open_blends'
  ] loop
    select c.conname,
           (select array_agg(a.attname::text order by k.ord)
            from unnest(c.conkey) with ordinality k(attnum, ord)
            join pg_attribute a on a.attrelid = c.conrelid and a.attnum = k.attnum)
      into pk_name, pk_cols
    from pg_constraint c
    where c.conrelid = format('public.%I', t)::regclass and c.contype = 'p';

    if pk_cols is distinct from array['owner_id', 'id'] then
      if pk_name is not null then
        execute format('alter table public.%I drop constraint %I', t, pk_name);
      end if;
      execute format('alter table public.%I add primary key (owner_id, id)', t);
    end if;
  end loop;
end $$;

-- 4. Composite foreign keys -----------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'dive_samples_owner_dive_fkey'
                 and conrelid = 'public.dive_samples'::regclass) then
    alter table public.dive_samples
      add constraint dive_samples_owner_dive_fkey
      foreign key (owner_id, id) references public.dives (owner_id, id) on delete cascade;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'dive_bailout_carry_owner_dive_fkey'
                 and conrelid = 'public.dive_bailout_carry'::regclass) then
    alter table public.dive_bailout_carry
      add constraint dive_bailout_carry_owner_dive_fkey
      foreign key (owner_id, dive_id) references public.dives (owner_id, id);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'dive_bailout_carry_owner_cylinder_fkey'
                 and conrelid = 'public.dive_bailout_carry'::regclass) then
    alter table public.dive_bailout_carry
      add constraint dive_bailout_carry_owner_cylinder_fkey
      foreign key (owner_id, cylinder_id) references public.cylinders (owner_id, id);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'dive_merge_links_owner_dive_fkey'
                 and conrelid = 'public.dive_merge_links'::regclass) then
    alter table public.dive_merge_links
      add constraint dive_merge_links_owner_dive_fkey
      foreign key (owner_id, id) references public.dives (owner_id, id);
  end if;
end $$;

-- 5. Explicit Data API grants (issue #76), restated for all 16 tables -----------
revoke all on table public.dive_annotations from anon, authenticated, service_role;
grant select, insert, update, delete on table public.dive_annotations to authenticated, service_role;
revoke all on table public.cylinders from anon, authenticated, service_role;
grant select, insert, update, delete on table public.cylinders to authenticated, service_role;
revoke all on table public.oxygen_cells from anon, authenticated, service_role;
grant select, insert, update, delete on table public.oxygen_cells to authenticated, service_role;
revoke all on table public.scrubber_sessions from anon, authenticated, service_role;
grant select, insert, update, delete on table public.scrubber_sessions to authenticated, service_role;
revoke all on table public.pressure_mappings from anon, authenticated, service_role;
grant select, insert, update, delete on table public.pressure_mappings to authenticated, service_role;
revoke all on table public.dive_cylinders from anon, authenticated, service_role;
grant select, insert, update, delete on table public.dive_cylinders to authenticated, service_role;
revoke all on table public.dive_computers from anon, authenticated, service_role;
grant select, insert, update, delete on table public.dive_computers to authenticated, service_role;
revoke all on table public.dives from anon, authenticated, service_role;
grant select, insert, update, delete on table public.dives to authenticated, service_role;
revoke all on table public.dive_samples from anon, authenticated, service_role;
grant select, insert, update, delete on table public.dive_samples to authenticated, service_role;
revoke all on table public.dive_attachments from anon, authenticated, service_role;
grant select, insert, update, delete on table public.dive_attachments to authenticated, service_role;
revoke all on table public.dive_bailout_carry from anon, authenticated, service_role;
grant select, insert, update, delete on table public.dive_bailout_carry to authenticated, service_role;
revoke all on table public.dive_plans from anon, authenticated, service_role;
grant select, insert, update, delete on table public.dive_plans to authenticated, service_role;
revoke all on table public.dive_merge_links from anon, authenticated, service_role;
grant select, insert, update, delete on table public.dive_merge_links to authenticated, service_role;
revoke all on table public.gas_analyses from anon, authenticated, service_role;
grant select, insert, update, delete on table public.gas_analyses to authenticated, service_role;
revoke all on table public.user_acknowledgements from anon, authenticated, service_role;
grant select, insert, update, delete on table public.user_acknowledgements to authenticated, service_role;
revoke all on table public.open_blends from anon, authenticated, service_role;
grant select, insert, update, delete on table public.open_blends to authenticated, service_role;

-- 6. PostgREST must pick up the new conflict targets ----------------------------
NOTIFY pgrst, 'reload schema';
