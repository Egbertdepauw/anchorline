-- State for the 0027 guard test: B has a dive_bailout_carry row pointing at
-- A's dive d1, while B has no dive d1 of their own. A foreign-key check
-- ignores RLS, so this exists in real data. Run as postgres, before 0027.
insert into auth.users (id, email, email_confirmed_at) values
  ('00000000-0000-0000-0000-00000000000a', 'a@example.test', now()),
  ('00000000-0000-0000-0000-00000000000b', 'b@example.test', now());

insert into public.dives (
  id, owner_id, dc_serial, dc_dive_number, start_time, end_time,
  duration_seconds, max_depth_mm, dive_mode, deco_model,
  atmospheric_pressure_mbar, water_density, log_version, dc_model,
  sample_interval_ms, gas_mixes_json, parser_version, imported_at
) values (
  'd1', '00000000-0000-0000-0000-00000000000a', 1, 1, 1000, 2000, 1000,
  10000, 0, 0, 1013, 1000, 1, 0, 10000, '[]', 2, 1000
);

insert into public.cylinders (id, owner_id, label, role, volume_liters, working_pressure_bar, created_at, updated_at) values
  ('cyl_a', '00000000-0000-0000-0000-00000000000a', 'c', 'bailout', 3, 200, 1, 1),
  ('cyl_b', '00000000-0000-0000-0000-00000000000b', 'c', 'bailout', 3, 200, 1, 1);

insert into public.dive_bailout_carry (id, owner_id, dive_id, cylinder_id, gas_mix, bailout_order, created_at, updated_at)
values ('d1:cyl_b', '00000000-0000-0000-0000-00000000000b', 'd1', 'cyl_b', '21/0', 0, 1, 1);
