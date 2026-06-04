-- Phase 3 / Subsurface-sync follow-up. Per-cell calibration factors
-- come out of the Shearwater header (parser at 375-385) and feed the
-- mV → ppo2_bar conversion that Subsurface and our profile chart both
-- need. Until now the value was dropped at import time. Stored as a
-- JSON-text array of three doubles (length 0 on OC; length 3 on CCR).
-- Mirrors the gas_mixes_json column shape.
alter table dives
  add column if not exists sensor_calibration_json text;
