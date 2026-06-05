ALTER TABLE dive_annotations
ADD COLUMN IF NOT EXISTS user_dive_number INTEGER;
COMMENT ON COLUMN dive_annotations.user_dive_number IS
  'User-assigned dive number (renumbering). NULL = use the app''s automatic '
  'date-order sequence.';
