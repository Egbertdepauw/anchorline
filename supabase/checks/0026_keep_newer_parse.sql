-- Manual check for migration 0026 (keep_newer_parse guard, vendor-keyed
-- dive_computers). Self-asserting: every check is a DO block that raises an
-- exception naming the check, the value it got and the value it expected. If
-- the whole script finishes without an error, every check passed (the SQL
-- editor shows no NOTICEs and only the last result set, so there is nothing
-- else to read). Everything runs in one transaction that is rolled back.
--
-- How to run: paste the whole script into the Supabase SQL editor after
-- applying 0026, with your own auth.users uuid (Authentication -> Users) in
-- the set_config line below (same pattern as the delete_my_account dry run
-- in supabase/README.md). Or run it with psql through the Session pooler
-- (see supabase/README.md) with the same edit. Run all of it together.
begin;
select set_config('request.jwt.claims', '{"sub":"<your auth.users uuid>","role":"authenticated"}', true);

do $$ begin
  if auth.uid() is null then
    raise exception 'auth.uid() is null: put your auth.users uuid in the set_config line';
  end if;
end $$;

-- Fixture: dive A at parser_version 2 with samples (depth_blob 'orig').
insert into public.dives (
  id, owner_id, dc_serial, dc_dive_number, start_time, end_time,
  duration_seconds, max_depth_mm, dive_mode, deco_model, atmospheric_pressure_mbar,
  water_density, log_version, dc_model, sample_interval_ms, gas_mixes_json,
  parser_version, imported_at
) values (
  'check0026-a', auth.uid(), 1, 1, 1000, 2000,
  1000, 10000, 0, 0, 1013,
  1000, 1, 0, 10000, '[]',
  2, 1000
);
insert into public.dive_samples (
  id, owner_id, sample_count, depth_blob, temperature_blob, ppo2_blob,
  cell_mv0_blob, cell_mv1_blob, cell_mv2_blob, setpoint_blob, cns_blob,
  deco_depth_blob, deco_time_blob, tts_blob, gas_mix_idx_blob, status_blob,
  created_at, updated_at, parser_version
) values (
  'check0026-a', auth.uid(), 0, 'orig', '', '',
  '', '', '', '', '',
  '', '', '', '', '',
  1000, 1000, 2
);

-- 1. Lowering 2 -> 1 is a no-op on both tables.
update public.dives set parser_version = 1 where id = 'check0026-a';
update public.dive_samples set parser_version = 1 where id = 'check0026-a';
do $$ declare d int; s int; begin
  select parser_version into d from public.dives where id = 'check0026-a';
  select parser_version into s from public.dive_samples where id = 'check0026-a';
  if d is distinct from 2 then raise exception 'check 1 (dives lower ignored): got %, expected 2', d; end if;
  if s is distinct from 2 then raise exception 'check 1 (dive_samples lower ignored): got %, expected 2', s; end if;
end $$;

-- 2. An old build's upsert: omits parser_version, changes a blob. Must stay.
insert into public.dive_samples (
  id, owner_id, sample_count, depth_blob, temperature_blob, ppo2_blob,
  cell_mv0_blob, cell_mv1_blob, cell_mv2_blob, setpoint_blob, cns_blob,
  deco_depth_blob, deco_time_blob, tts_blob, gas_mix_idx_blob, status_blob,
  created_at, updated_at
) values (
  'check0026-a', auth.uid(), 0, 'older-parse', '', '',
  '', '', '', '', '',
  '', '', '', '', '',
  1000, 1000
) on conflict (id) do update set depth_blob = excluded.depth_blob;
do $$ declare b text; begin
  select depth_blob into b from public.dive_samples where id = 'check0026-a';
  if b is distinct from 'orig' then
    raise exception 'check 2 (old-build upsert keeps blob): got %, expected orig', b;
  end if;
end $$;

-- 3. A plain update lowering dives.parser_version together with a changed
--    data column: both must stay.
update public.dives set parser_version = 1, max_depth_mm = 99999 where id = 'check0026-a';
do $$ declare v int; m int; begin
  select parser_version, max_depth_mm into v, m from public.dives where id = 'check0026-a';
  if v is distinct from 2 then raise exception 'check 3 (version kept): got %, expected 2', v; end if;
  if m is distinct from 10000 then raise exception 'check 3 (max_depth_mm kept): got %, expected 10000', m; end if;
end $$;

-- 4. Raising 2 -> 3 goes through, on both tables (a real refresh, new blob).
update public.dives set parser_version = 3 where id = 'check0026-a';
update public.dive_samples set parser_version = 3, depth_blob = 'refreshed' where id = 'check0026-a';
do $$ declare d int; s int; b text; begin
  select parser_version into d from public.dives where id = 'check0026-a';
  select parser_version, depth_blob into s, b from public.dive_samples where id = 'check0026-a';
  if d is distinct from 3 then raise exception 'check 4 (dives raise applied): got %, expected 3', d; end if;
  if s is distinct from 3 then raise exception 'check 4 (dive_samples raise applied): got %, expected 3', s; end if;
  if b is distinct from 'refreshed' then raise exception 'check 4 (refreshed blob applied): got %, expected refreshed', b; end if;
end $$;

-- 5. A -1 (Subsurface) write over the download at 3 must stay 3.
update public.dives set parser_version = -1 where id = 'check0026-a';
update public.dive_samples set parser_version = -1, depth_blob = 'subsurface' where id = 'check0026-a';
do $$ declare d int; s int; b text; begin
  select parser_version into d from public.dives where id = 'check0026-a';
  select parser_version, depth_blob into s, b from public.dive_samples where id = 'check0026-a';
  if d is distinct from 3 then raise exception 'check 5 (dives -1 refused): got %, expected 3', d; end if;
  if s is distinct from 3 then raise exception 'check 5 (dive_samples -1 refused): got %, expected 3', s; end if;
  if b is distinct from 'refreshed' then raise exception 'check 5 (blob kept): got %, expected refreshed', b; end if;
end $$;

-- 6. A same-version PATCH of dives.deleted_at goes through.
update public.dives set deleted_at = 5000 where id = 'check0026-a';
do $$ declare t bigint; begin
  select deleted_at into t from public.dives where id = 'check0026-a';
  if t is distinct from 5000 then raise exception 'check 6 (same-version PATCH applied): got %, expected 5000', t; end if;
end $$;

-- 7. A Subsurface copy (-1) can be replaced by any reader.
insert into public.dives (
  id, owner_id, dc_serial, dc_dive_number, start_time, end_time,
  duration_seconds, max_depth_mm, dive_mode, deco_model, atmospheric_pressure_mbar,
  water_density, log_version, dc_model, sample_interval_ms, gas_mixes_json,
  parser_version, imported_at
) values (
  'check0026-b', auth.uid(), 2, 2, 3000, 4000,
  1000, 10000, 0, 0, 1013,
  1000, 1, 0, 10000, '[]',
  -1, 1000
);
insert into public.dive_samples (
  id, owner_id, sample_count, depth_blob, temperature_blob, ppo2_blob,
  cell_mv0_blob, cell_mv1_blob, cell_mv2_blob, setpoint_blob, cns_blob,
  deco_depth_blob, deco_time_blob, tts_blob, gas_mix_idx_blob, status_blob,
  created_at, updated_at, parser_version
) values (
  'check0026-b', auth.uid(), 0, 'sub', '', '',
  '', '', '', '', '',
  '', '', '', '', '',
  1000, 1000, -1
);
update public.dives set parser_version = 1 where id = 'check0026-b';
update public.dive_samples set parser_version = 1, depth_blob = 'parsed' where id = 'check0026-b';
do $$ declare d int; s int; b text; begin
  select parser_version into d from public.dives where id = 'check0026-b';
  select parser_version, depth_blob into s, b from public.dive_samples where id = 'check0026-b';
  if d is distinct from 1 then raise exception 'check 7 (dives subsurface copy replaced): got %, expected 1', d; end if;
  if s is distinct from 1 then raise exception 'check 7 (dive_samples subsurface copy replaced): got %, expected 1', s; end if;
  if b is distinct from 'parsed' then raise exception 'check 7 (blob replaced): got %, expected parsed', b; end if;
end $$;

-- 8. dive_computers: same serial with two vendors is allowed; a duplicate
--    Shearwater/1 is a unique violation.
insert into public.dive_computers (id, owner_id, serial, model, created_at, updated_at, dc_vendor)
values ('check0026-c1', auth.uid(), 1, 0, 1000, 1000, 'Shearwater');
insert into public.dive_computers (id, owner_id, serial, model, created_at, updated_at, dc_vendor)
values ('check0026-c2', auth.uid(), 1, 0, 1000, 1000, 'Divesoft');
do $$ begin
  begin
    insert into public.dive_computers (id, owner_id, serial, model, created_at, updated_at, dc_vendor)
    values ('check0026-c3', auth.uid(), 1, 0, 1000, 1000, 'Shearwater');
    raise exception 'check 8 (duplicate vendor+serial): got accepted, expected unique_violation';
  exception when unique_violation then
    null;
  end;
end $$;

rollback;
