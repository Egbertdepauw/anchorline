-- Self-asserting check for migration 0028 (dives.dc_fingerprint), run by
-- supabase/dry_run/run.sh after every migration has been applied twice. The
-- same assertions as supabase/checks/0028_dive_fingerprint.sql, with a stub
-- user. This file owns its transaction: run it WITHOUT --single-transaction.
begin;
insert into auth.users (id, email, email_confirmed_at, created_at) values
  ('00000000-0000-0000-0000-00000000000a', 'a@example.test', now(), now());
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000000a","role":"authenticated"}', true);

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
