ALTER TABLE proposals ADD COLUMN correlation_id TEXT;
CREATE UNIQUE INDEX IF NOT EXISTS idx_proposals_institution_correlation
  ON proposals (institution_id, correlation_id)
  WHERE correlation_id IS NOT NULL;
