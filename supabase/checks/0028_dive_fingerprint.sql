-- Manual check for migration 0028 (dives.dc_fingerprint). Self-asserting:
-- every check is a DO block that raises an exception naming the check, the
-- value it got and the value it expected. If the whole script finishes
-- without an error, every check passed. Everything runs in one transaction
-- that is rolled back.
--
-- How to run: paste the whole script into the Supabase SQL editor after
-- applying 0028, with your own auth.users uuid (Authentication -> Users) in
-- the set_config line below (same pattern as 0026_keep_newer_parse.sql). Or
-- run it with psql through the Session pooler (see supabase/README.md) with
-- the same edit:
--   psql -v ON_ERROR_STOP=1 -f supabase/checks/0028_dive_fingerprint.sql "<pooler url>"
-- Run all of it together.
begin;
select set_config('request.jwt.claims', '{"sub":"<your auth.users uuid>","role":"authenticated"}', true);

do $$ begin
  if current_setting('request.jwt.claims', true) like '%<your auth.users%' then
    raise exception 'replace <your auth.users uuid> in the set_config line with your uuid';
  end if;
  if auth.uid() is null then
    raise exception 'auth.uid() is null: put your auth.users uuid in the set_config line';
  end if;
end $$;

-- 1. The column exists, as text.
do $$ declare t text; begin
  select data_type into t from information_schema.columns
   where table_schema = 'public' and table_name = 'dives' and column_name = 'dc_fingerprint';
  if t is distinct from 'text' then
    raise exception 'check 1 (dc_fingerprint column type): got %, expected text', t;
  end if;
end $$;

-- 2. A row inserted with a fingerprint reads it back; a row without stays NULL.
insert into public.dives (
  id, owner_id, dc_serial, dc_dive_number, start_time, end_time,
  duration_seconds, max_depth_mm, dive_mode, deco_model, atmospheric_pressure_mbar,
  water_density, log_version, dc_model, sample_interval_ms, gas_mixes_json,
  parser_version, imported_at, dc_vendor, dc_family, dc_fingerprint
) values (
  'check0028-a', auth.uid(), 1, 0, 1000, 2000,
  1000, 10000, 0, 0, 1013,
  1000, 1, 13, 10000, '[]',
  1, 1000, 'Suunto', 5, 'aa11bb22'
);
insert into public.dives (
  id, owner_id, dc_serial, dc_dive_number, start_time, end_time,
  duration_seconds, max_depth_mm, dive_mode, deco_model, atmospheric_pressure_mbar,
  water_density, log_version, dc_model, sample_interval_ms, gas_mixes_json,
  parser_version, imported_at
) values (
  'check0028-b', auth.uid(), 1, 0, 1030, 2030,
  1000, 10000, 0, 0, 1013,
  1000, 1, 0, 10000, '[]',
  1, 1000
);
do $$ declare a text; b text; begin
  select dc_fingerprint into a from public.dives where id = 'check0028-a';
  select dc_fingerprint into b from public.dives where id = 'check0028-b';
  if a is distinct from 'aa11bb22' then
    raise exception 'check 2 (fingerprint read back): got %, expected aa11bb22', a;
  end if;
  if b is not null then
    raise exception 'check 2 (no fingerprint stays NULL): got %, expected NULL', b;
  end if;
end $$;

-- 3. A same-version update of the fingerprint goes through (the keep_newer_parse
--    guard only blocks an older parse).
update public.dives set dc_fingerprint = 'cc33dd44' where id = 'check0028-b';
do $$ declare b text; begin
  select dc_fingerprint into b from public.dives where id = 'check0028-b';
  if b is distinct from 'cc33dd44' then
    raise exception 'check 3 (fingerprint update): got %, expected cc33dd44', b;
  end if;
end $$;

rollback;
