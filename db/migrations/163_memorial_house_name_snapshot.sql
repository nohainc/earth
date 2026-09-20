-- Preserve the House identity as it existed at the Human's death. Current
-- House names may change later; a memorial biography must not be rewritten.

ALTER TABLE human_memorial_records
  ADD COLUMN IF NOT EXISTS house_name_at_death TEXT;

COMMENT ON COLUMN human_memorial_records.house_name_at_death IS
  'Immutable House name captured when the Human memorial record is created.';
