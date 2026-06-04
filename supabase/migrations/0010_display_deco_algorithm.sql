ALTER TABLE dive_annotations
ADD COLUMN IF NOT EXISTS display_deco_algorithm TEXT;
COMMENT ON COLUMN dive_annotations.display_deco_algorithm IS
  'User per-dive override of which deco algorithm to display. '
  'Values: ''zhl16c'' or ''vpmb''. NULL = use default (zhl16c).';
