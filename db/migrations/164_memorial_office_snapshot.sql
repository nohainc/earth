-- Preserve the Human's major offices at death. Current role rows are mutable
-- operational state and must not be used to rewrite a permanent biography.
ALTER TABLE human_memorial_records
  ADD COLUMN IF NOT EXISTS major_offices_snapshot JSONB NOT NULL DEFAULT '[]'::JSONB;

COMMENT ON COLUMN human_memorial_records.major_offices_snapshot IS
  'Immutable major office records captured at death; never reconstructed from current role assignments.';
