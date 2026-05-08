-- Subsurface "Information" tab parity. Eight new columns on
-- dive_annotations capturing the structured per-dive conditions data
-- Subsurface stores natively but CCRLog had been silently dropping on
-- import:
--   - five 1..5 environmental star ratings (visibility, wavesize,
--     current, surge, chill); 0/null = unrated, mirroring the existing
--     `rating` column convention.
--   - measured air + water temperatures in °C as real values, nullable
--     because Subsurface's `watertemp` line is optional.
--   - weights_json: a JSON array of `{"weight_kg", "description"}`
--     objects, one per `weightsystem` line in the source dive folder.
--     JSON because divers wear N weights with bespoke labels and a
--     dedicated table would mean an extra join for nothing.
--
-- salinity / atmospheric pressure are deliberately NOT added here —
-- both already live on the immutable `dives` row (`water_density`,
-- `atmospheric_pressure_mbar`) and would duplicate state if mirrored.

alter table dive_annotations
  add column visibility integer,
  add column wavesize integer,
  add column "current" integer,
  add column surge integer,
  add column chill integer,
  add column air_temp_c real,
  add column water_temp_c real,
  add column weights_json jsonb;
