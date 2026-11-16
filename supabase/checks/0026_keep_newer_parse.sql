-- Manual check for migration 0026 (keep_newer_parse guard, vendor-keyed
-- dive_computers). Run in the Supabase SQL editor AFTER applying 0026, as a
-- signed-in user so auth.uid() is set (the editor's role must be able to
-- impersonate one; otherwise set owner below to a real auth.users id).
-- Everything runs in one transaction that rolls back, so nothing is kept.
-- Each select shows its expected value in the column name.
begin;

do $$ begin
  if auth.uid() is null then
    raise exception 'auth.uid() is null: run as an authenticated user';
  end if;
end $$;

-- Throwaway dive at parser_version 2, with its samples row.
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
  'check0026-a', auth.uid(), 0, '', '', '',
  '', '', '', '', '',
  '', '', '', '', '',
  1000, 1000, 2
);

-- Lowering 2 -> 1 is a no-op on both tables.
update public.dives set parser_version = 1 where id = 'check0026-a';
update public.dive_samples set parser_version = 1 where id = 'check0026-a';
select 'dives lower ignored (expect 2)' as check,
       (select parser_version from public.dives where id = 'check0026-a') as got;
select 'dive_samples lower ignored (expect 2)' as check,
       (select parser_version from public.dive_samples where id = 'check0026-a') as got;

-- Raising 2 -> 3 goes through.
update public.dives set parser_version = 3 where id = 'check0026-a';
select 'dives raise applied (expect 3)' as check,
       (select parser_version from public.dives where id = 'check0026-a') as got;

-- A Subsurface copy (-1) can be replaced by any reader.
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
update public.dives set parser_version = 1 where id = 'check0026-b';
select 'subsurface copy replaced (expect 1)' as check,
       (select parser_version from public.dives where id = 'check0026-b') as got;

-- dive_computers: same serial, different vendor, is allowed.
insert into public.dive_computers (id, owner_id, serial, model, created_at, updated_at, dc_vendor)
values ('check0026-c1', auth.uid(), 1, 0, 1000, 1000, 'Shearwater');
insert into public.dive_computers (id, owner_id, serial, model, created_at, updated_at, dc_vendor)
values ('check0026-c2', auth.uid(), 1, 0, 1000, 1000, 'Divesoft');
select 'two vendors, same serial (expect 2)' as check,
       (select count(*) from public.dive_computers
         where id in ('check0026-c1', 'check0026-c2')) as got;

-- A second Shearwater/1 must fail with a unique violation.
do $$ begin
  begin
    insert into public.dive_computers (id, owner_id, serial, model, created_at, updated_at, dc_vendor)
    values ('check0026-c3', auth.uid(), 1, 0, 1000, 1000, 'Shearwater');
    raise exception 'FAIL: duplicate Shearwater/1 was accepted';
  exception when unique_violation then
    raise notice 'ok: duplicate Shearwater/1 rejected (unique_violation)';
  end;
end $$;

rollback;
