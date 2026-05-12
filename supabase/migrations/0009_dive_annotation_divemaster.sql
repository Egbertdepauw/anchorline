-- Adds the divemaster annotation column. CCRLog and Subsurface both
-- model divemaster as a free-text string per dive. Previously the
-- Subsurface-side write was emitted as an empty placeholder; with this
-- column the field round-trips properly through bootstrap import and
-- the CCRLog → Subsurface push.

ALTER TABLE dive_annotations
  ADD COLUMN IF NOT EXISTS divemaster TEXT;
