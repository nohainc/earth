ALTER TABLE proposals ADD COLUMN quorum NUMERIC NOT NULL DEFAULT 0.25;
ALTER TABLE proposals ADD COLUMN approval_threshold NUMERIC NOT NULL DEFAULT 0.5;
ALTER TABLE proposals ADD COLUMN implementation_delay_days INTEGER NOT NULL DEFAULT 1;
ALTER TABLE proposals ADD COLUMN outcome TEXT NOT NULL DEFAULT 'pending' CHECK (outcome IN ('pending','passed','rejected','no_quorum'));
ALTER TABLE proposals ADD COLUMN implementation_at TEXT;
ALTER TABLE proposals ADD COLUMN resolved_at TEXT;

UPDATE proposals
SET implementation_at = datetime(closes_at, '+1 day')
WHERE implementation_at IS NULL;
