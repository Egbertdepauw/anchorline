-- Phase 3 polish. Five new freeform-text columns on dive_annotations
-- to track non-cylinder equipment used per dive: suit, undersuit, weight
-- system, DPV, camera. All optional; the UI surfaces them as
-- "buddies-style" autocompletes (free text + suggestion pool from prior
-- entries the same user made).
--
-- Why on dive_annotations and not new tables: each is a single string
-- per dive, identity-less, non-relational. A dedicated table would mean
-- five extra joins for nothing. If/when these grow into structured
-- entities (e.g. a "DPV serial + battery cycles" record), revisit then.

alter table dive_annotations
  add column suit text,
  add column undersuit text,
  add column weight_system text,
  add column dpv text,
  add column camera text;
