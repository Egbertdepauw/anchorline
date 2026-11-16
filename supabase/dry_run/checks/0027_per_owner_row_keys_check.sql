-- Self-asserting check for migration 0027 (per-owner row keys), run by
-- supabase/dry_run/run.sh after every migration has been applied twice. Every
-- assertion is a DO block that raises an exception naming what failed, so a
-- clean finish means every one passed. Everything runs in one transaction that
-- is rolled back, so nothing is left behind. This file owns its transaction:
-- run it WITHOUT --single-transaction.
begin;

-- Fixture: two accounts. A and B hold exactly the same ids.
insert into auth.users (id, email, email_confirmed_at, created_at) values
  ('00000000-0000-0000-0000-00000000000a', 'a@example.test', now(), now()),
  ('00000000-0000-0000-0000-00000000000b', 'b@example.test', now(), now());

-- Seeds one row per synced table for the calling user, with the ids two
-- accounts really share. Every statement is the upsert PostgREST generates
-- for a PUT with no on_conflict, so each one hits (owner_id, id).
create function public.zz_seed() returns void language plpgsql as $$
declare
  me uuid := auth.uid();
  sfx text := case when me = '00000000-0000-0000-0000-00000000000a' then 'a'
                   else 'b' end;
begin
  insert into public.dive_computers (id, owner_id, serial, model, created_at, updated_at)
  values ('dc_b89641e4', me, 1, 1, 1, 1)
  on conflict (owner_id, id) do update set updated_at = excluded.updated_at;

  insert into public.dives (
    id, owner_id, dc_serial, dc_dive_number, start_time, end_time,
    duration_seconds, max_depth_mm, dive_mode, deco_model,
    atmospheric_pressure_mbar, water_density, log_version, dc_model,
    sample_interval_ms, gas_mixes_json, parser_version, imported_at
  ) values (
    'd1', me, 1, 1, 1000, 2000, 1000, 10000, 0, 0, 1013, 1000, 1, 0,
    10000, '[]', 2, 1000
  ) on conflict (owner_id, id) do update set max_depth_mm = excluded.max_depth_mm;

  insert into public.dive_samples (
    id, owner_id, sample_count, depth_blob, temperature_blob, ppo2_blob,
    cell_mv0_blob, cell_mv1_blob, cell_mv2_blob, setpoint_blob, cns_blob,
    deco_depth_blob, deco_time_blob, tts_blob, gas_mix_idx_blob, status_blob,
    created_at, updated_at, parser_version
  ) values (
    'd1', me, 0, 'orig-' || sfx, '', '', '', '', '', '', '', '', '', '', '', '',
    1000, 1000, 2
  ) on conflict (owner_id, id) do update set updated_at = excluded.updated_at;

  insert into public.dive_annotations (id, owner_id, dive_id, created_at, updated_at)
  values ('d1', me, 'd1', 1, 1)
  on conflict (owner_id, id) do update set updated_at = excluded.updated_at;

  insert into public.dive_cylinders (id, owner_id, dive_id, gas_mix_index, created_at, updated_at)
  values ('d1:0', me, 'd1', 0, 1, 1)
  on conflict (owner_id, id) do update set updated_at = excluded.updated_at;

  insert into public.pressure_mappings (id, owner_id, dive_computer_id, channel_index, created_at, updated_at)
  values ('dc_b89641e4:0', me, 'dc_b89641e4', 0, 1, 1)
  on conflict (owner_id, id) do update set updated_at = excluded.updated_at;

  insert into public.dive_merge_links (id, owner_id, group_id, created_at, updated_at)
  values ('d1', me, 'g1', 1, 1)
  on conflict (owner_id, id) do update set updated_at = excluded.updated_at;

  -- Cylinders and the carry rows that point at them carry the owner in
  -- their ids, as they do in practice.
  insert into public.cylinders (id, owner_id, label, role, volume_liters, working_pressure_bar, created_at, updated_at)
  values ('cyl_' || sfx, me, 'c', 'bailout', 3, 200, 1, 1)
  on conflict (owner_id, id) do update set updated_at = excluded.updated_at;

  insert into public.dive_bailout_carry (id, owner_id, dive_id, cylinder_id, gas_mix, bailout_order, created_at, updated_at)
  values ('d1:cyl_' || sfx, me, 'd1', 'cyl_' || sfx, '21/0', 0, 1, 1)
  on conflict (owner_id, id) do update set updated_at = excluded.updated_at;

  insert into public.gas_analyses (id, owner_id, analysed_at, o2_percent, created_at, updated_at)
  values ('ga_shared', me, 1, 21, 1, 1)
  on conflict (owner_id, id) do update set updated_at = excluded.updated_at;

  -- The remaining tables use ids that rarely repeat; seed them anyway so the
  -- account deletion below is checked against all 16 tables.
  insert into public.oxygen_cells (id, owner_id, slot, created_at, updated_at)
  values ('cell_1', me, 1, 1, 1)
  on conflict (owner_id, id) do update set updated_at = excluded.updated_at;

  insert into public.scrubber_sessions (id, owner_id, created_at, updated_at)
  values ('scrub_1', me, 1, 1)
  on conflict (owner_id, id) do update set updated_at = excluded.updated_at;

  insert into public.dive_attachments (id, owner_id, parent_id, kind, url, created_at, updated_at)
  values ('att_1', me, 'd1', 'link', 'https://example.test', 1, 1)
  on conflict (owner_id, id) do update set updated_at = excluded.updated_at;

  insert into public.dive_plans (id, owner_id, mode, gases_json, segments_json, bailout_json, created_at, updated_at)
  values ('plan_1', me, 'ccr', '[]', '[]', '[]', 1, 1)
  on conflict (owner_id, id) do update set updated_at = excluded.updated_at;

  insert into public.open_blends (
    id, owner_id, target_o2_percent, target_he_percent, target_pressure_bar,
    residual_o2_percent, residual_he_percent, residual_pressure_bar,
    topoff_o2_percent, topoff_he_percent, water_capacity_l, gas_role,
    blended_at, created_at, updated_at
  ) values ('blend_1', me, 21, 0, 200, 21, 0, 0, 21, 0, 10, 'bottom', 1, 1, 1)
  on conflict (owner_id, id) do update set updated_at = excluded.updated_at;

  insert into public.user_acknowledgements (id, owner_id, subject, text_version, accepted_at, created_at, updated_at)
  values ('ack_1', me, 'terms', 1, 1, 1, 1)
  on conflict (owner_id, id) do update set updated_at = excluded.updated_at;
end $$;

-- Counts rows of every synced table visible to the current user, and the
-- subset they own. RLS must make the two equal.
create function public.zz_counts(out total bigint, out own bigint)
language plpgsql as $$
declare t text;
begin
  total := 0; own := 0;
  for t in select tablename from pg_publication_tables
           where pubname = 'powersync' order by 1 loop
    total := total + (select (xpath('/row/c/text()',
      query_to_xml(format('select count(*) c from public.%I', t), false, true, '')))[1]::text::bigint);
    own := own + (select (xpath('/row/c/text()',
      query_to_xml(format('select count(*) c from public.%I where owner_id = auth.uid()', t),
                   false, true, '')))[1]::text::bigint);
  end loop;
end $$;

-- 1. Keys ---------------------------------------------------------------------
do $$
declare bad text;
begin
  select string_agg(t.tablename || ' pk=' || coalesce(pk.cols::text, 'none'), ', ')
    into bad
  from pg_publication_tables t
  left join lateral (
    select array_agg(a.attname::text order by k.ord) cols
    from pg_index i
    cross join lateral unnest(i.indkey) with ordinality k(attnum, ord)
    join pg_attribute a on a.attrelid = i.indrelid and a.attnum = k.attnum
    where i.indrelid = format('public.%I', t.tablename)::regclass and i.indisprimary
  ) pk on true
  where t.pubname = 'powersync' and pk.cols is distinct from array['owner_id','id'];
  if bad is not null then
    raise exception 'check 1: primary key is not (owner_id, id) on: %', bad;
  end if;
  if (select count(*) from pg_publication_tables where pubname = 'powersync') <> 16 then
    raise exception 'check 1: expected 16 tables in the powersync publication';
  end if;
end $$;

do $$
declare n text;
begin
  foreach n in array array['dive_samples_owner_dive_fkey',
      'dive_bailout_carry_owner_dive_fkey', 'dive_bailout_carry_owner_cylinder_fkey',
      'dive_merge_links_owner_dive_fkey'] loop
    if not exists (select 1 from pg_constraint where conname = n and contype = 'f') then
      raise exception 'check 1: foreign key % is missing', n;
    end if;
  end loop;
  if (select confdeltype from pg_constraint where conname = 'dive_samples_owner_dive_fkey') <> 'c' then
    raise exception 'check 1: dive_samples_owner_dive_fkey must be on delete cascade';
  end if;
  if exists (
    select 1 from pg_constraint
    where contype = 'f' and cardinality(conkey) = 1
      and confrelid in ('public.dives'::regclass, 'public.cylinders'::regclass)
  ) then
    raise exception 'check 1: a single-column foreign key into dives or cylinders is left';
  end if;
end $$;

-- 2. Two accounts, the same ids -------------------------------------------------
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000000a","role":"authenticated"}', true);
select public.zz_seed();
reset role;

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000000b","role":"authenticated"}', true);
select public.zz_seed();
reset role;

do $$
declare u uuid; c record; n int;
begin
  foreach u in array array['00000000-0000-0000-0000-00000000000a'::uuid,
                           '00000000-0000-0000-0000-00000000000b'::uuid] loop
    perform set_config('request.jwt.claims',
      json_build_object('sub', u, 'role', 'authenticated')::text, true);
    set local role authenticated;
    select * into c from public.zz_counts();
    reset role;
    if c.total <> c.own then
      raise exception 'check 2: user % sees % rows, owns %', u, c.total, c.own;
    end if;
    if c.own < 16 then
      raise exception 'check 2: user % has only % rows after seeding', u, c.own;
    end if;
  end loop;
  select count(*) into n from public.dives where id = 'd1';
  if n <> 2 then raise exception 'check 2: expected two d1 dives, got %', n; end if;
end $$;

-- An account A dive that B does not have, for check 5.
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000000a","role":"authenticated"}', true);
insert into public.dives (
  id, owner_id, dc_serial, dc_dive_number, start_time, end_time,
  duration_seconds, max_depth_mm, dive_mode, deco_model,
  atmospheric_pressure_mbar, water_density, log_version, dc_model,
  sample_interval_ms, gas_mixes_json, parser_version, imported_at
) values (
  'd2', auth.uid(), 1, 2, 3000, 4000, 1000, 10000, 0, 0, 1013, 1000, 1, 0,
  10000, '[]', 2, 1000
);
reset role;

-- 3. B's writes do not touch A's row ---------------------------------------------
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000000b","role":"authenticated"}', true);
insert into public.dives (
  id, owner_id, dc_serial, dc_dive_number, start_time, end_time,
  duration_seconds, max_depth_mm, dive_mode, deco_model,
  atmospheric_pressure_mbar, water_density, log_version, dc_model,
  sample_interval_ms, gas_mixes_json, parser_version, imported_at
) values (
  'd1', auth.uid(), 1, 1, 1000, 2000, 1000, 55555, 0, 0, 1013, 1000, 1, 0,
  10000, '[]', 2, 1000
) on conflict (owner_id, id) do update set max_depth_mm = excluded.max_depth_mm;
update public.dives set deleted_at = 1 where id = 'd1';
reset role;

do $$
declare a record; b record;
begin
  select * into a from public.dives
    where id = 'd1' and owner_id = '00000000-0000-0000-0000-00000000000a';
  select * into b from public.dives
    where id = 'd1' and owner_id = '00000000-0000-0000-0000-00000000000b';
  if a.max_depth_mm <> 10000 or a.deleted_at is not null then
    raise exception 'check 3: A''s dive changed (max_depth_mm=%, deleted_at=%)',
      a.max_depth_mm, a.deleted_at;
  end if;
  if b.max_depth_mm <> 55555 or b.deleted_at is distinct from 1 then
    raise exception 'check 3: B''s own writes did not apply (max_depth_mm=%, deleted_at=%)',
      b.max_depth_mm, b.deleted_at;
  end if;
end $$;

-- 4. The 0026 triggers still guard the row ---------------------------------------
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000000b","role":"authenticated"}', true);
insert into public.dives (
  id, owner_id, dc_serial, dc_dive_number, start_time, end_time,
  duration_seconds, max_depth_mm, dive_mode, deco_model,
  atmospheric_pressure_mbar, water_density, log_version, dc_model,
  sample_interval_ms, gas_mixes_json, parser_version, imported_at
) values (
  'd1', auth.uid(), 1, 1, 1000, 2000, 1000, 77777, 0, 0, 1013, 1000, 1, 0,
  10000, '[]', 1, 1000
) on conflict (owner_id, id) do update
  set max_depth_mm = excluded.max_depth_mm, parser_version = excluded.parser_version;
update public.dive_samples set depth_blob = 'changed' where id = 'd1';
reset role;

do $$
declare d record; s record;
begin
  select * into d from public.dives
    where id = 'd1' and owner_id = '00000000-0000-0000-0000-00000000000b';
  select * into s from public.dive_samples
    where id = 'd1' and owner_id = '00000000-0000-0000-0000-00000000000b';
  if d.parser_version <> 2 or d.max_depth_mm <> 55555 then
    raise exception 'check 4: keep_newer_parse let an older parse through (parser_version=%, max_depth_mm=%)',
      d.parser_version, d.max_depth_mm;
  end if;
  if s.depth_blob <> 'orig-b' then
    raise exception 'check 4: keep_newer_samples let a same-version change through (depth_blob=%)',
      s.depth_blob;
  end if;
end $$;

-- 5. A child row needs a parent of the same owner --------------------------------
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000000b","role":"authenticated"}', true);
do $$
begin
  begin
    insert into public.dive_samples (
      id, owner_id, sample_count, depth_blob, temperature_blob, ppo2_blob,
      cell_mv0_blob, cell_mv1_blob, cell_mv2_blob, setpoint_blob, cns_blob,
      deco_depth_blob, deco_time_blob, tts_blob, gas_mix_idx_blob, status_blob,
      created_at, updated_at, parser_version
    ) values (
      'd2', auth.uid(), 0, '', '', '', '', '', '', '', '', '', '', '', '', '',
      1, 1, 2
    );
    raise exception 'check 5: B inserted samples for A''s dive d2';
  exception when foreign_key_violation then
    null;
  end;
end $$;
reset role;

-- 6. Deleting one account leaves the other ---------------------------------------
-- A third account C with the same ids, to survive the purge below.
insert into auth.users (id, email, email_confirmed_at, created_at) values
  ('00000000-0000-0000-0000-00000000000c', 'c@example.test', now(), now());
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000000c","role":"authenticated"}', true);
select public.zz_seed();
reset role;

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000000a","role":"authenticated"}', true);
select public.delete_my_account();
reset role;

do $$
declare t text; n bigint; bad text := '';
begin
  for t in select tablename from pg_publication_tables where pubname = 'powersync' loop
    execute format('select count(*) from public.%I where owner_id = %L', t,
                   '00000000-0000-0000-0000-00000000000a') into n;
    if n <> 0 then bad := bad || format('%s has %s rows of A; ', t, n); end if;
    execute format('select count(*) from public.%I where owner_id = %L', t,
                   '00000000-0000-0000-0000-00000000000b') into n;
    if n = 0 then bad := bad || format('%s lost B''s rows; ', t); end if;
  end loop;
  if bad <> '' then raise exception 'check 6 (delete_my_account): %', bad; end if;
  if exists (select 1 from auth.users where id = '00000000-0000-0000-0000-00000000000a') then
    raise exception 'check 6: user A is still in auth.users';
  end if;
  if (select count(*) from public.dive_bailout_carry
      where owner_id = '00000000-0000-0000-0000-00000000000b' and dive_id = 'd1') <> 1
     or (select count(*) from public.dive_merge_links
         where owner_id = '00000000-0000-0000-0000-00000000000b' and id = 'd1') <> 1 then
    raise exception 'check 6: B''s bailout or merge row for d1 was removed';
  end if;
end $$;

-- B becomes an unconfirmed sign-up older than 7 days; the purge removes B only.
update auth.users set email_confirmed_at = null, created_at = now() - interval '8 days'
where id = '00000000-0000-0000-0000-00000000000b';

do $$
declare t text; n bigint; bad text := ''; purged int;
begin
  purged := public.purge_unconfirmed_users();
  if purged <> 1 then
    raise exception 'check 6 (purge): expected 1 user purged, got %', purged;
  end if;
  if exists (select 1 from auth.users where id = '00000000-0000-0000-0000-00000000000b') then
    raise exception 'check 6 (purge): user B is still in auth.users';
  end if;
  for t in select tablename from pg_publication_tables where pubname = 'powersync' loop
    execute format('select count(*) from public.%I where owner_id = %L', t,
                   '00000000-0000-0000-0000-00000000000b') into n;
    if n <> 0 then bad := bad || format('%s has %s rows of B; ', t, n); end if;
    execute format('select count(*) from public.%I where owner_id = %L', t,
                   '00000000-0000-0000-0000-00000000000c') into n;
    if n = 0 then bad := bad || format('%s lost C''s rows; ', t); end if;
  end loop;
  if bad <> '' then raise exception 'check 6 (purge): %', bad; end if;
end $$;

-- 7. A conflict target on id alone is gone ---------------------------------------
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000000c","role":"authenticated"}', true);
do $$
begin
  begin
    insert into public.dives (
      id, owner_id, dc_serial, dc_dive_number, start_time, end_time,
      duration_seconds, max_depth_mm, dive_mode, deco_model,
      atmospheric_pressure_mbar, water_density, log_version, dc_model,
      sample_interval_ms, gas_mixes_json, parser_version, imported_at
    ) values (
      'd1', auth.uid(), 1, 1, 1000, 2000, 1000, 10000, 0, 0, 1013, 1000, 1, 0,
      10000, '[]', 2, 1000
    ) on conflict (id) do update set max_depth_mm = excluded.max_depth_mm;
    raise exception 'check 7: ON CONFLICT (id) was accepted';
  exception when sqlstate '42P10' then
    null;
  end;
end $$;
reset role;

rollback;
