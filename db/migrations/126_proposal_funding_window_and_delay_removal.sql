-- 126_proposal_funding_window_and_delay_removal.sql
-- Remove implementation delay setting and add 7-day funding expiration window for queued proposals.

ALTER TABLE proposals
  ADD COLUMN IF NOT EXISTS expires_game_day INTEGER,
  ADD COLUMN IF NOT EXISTS expires_game_minute INTEGER DEFAULT 0;

ALTER TABLE proposals
  ALTER COLUMN implementation_delay_days SET DEFAULT 0;

ALTER TABLE governance_rules
  ALTER COLUMN implementation_delay_days SET DEFAULT 0;

CREATE INDEX IF NOT EXISTS proposals_queued_expiry_idx
  ON proposals (execution_status, expires_game_day)
  WHERE execution_status = 'queued';
