-- Proposal lifecycle: keep passed votes open until their action starts.

ALTER TABLE proposals
  ADD COLUMN IF NOT EXISTS challenge_status TEXT NOT NULL DEFAULT 'none',
  ADD COLUMN IF NOT EXISTS started_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS started_game_day BIGINT,
  ADD COLUMN IF NOT EXISTS started_action_id TEXT;

ALTER TABLE proposals DROP CONSTRAINT IF EXISTS proposals_challenge_status_check;
ALTER TABLE proposals
  ADD CONSTRAINT proposals_challenge_status_check
  CHECK (challenge_status IN ('none', 'pending', 'upheld', 'voided'));

ALTER TABLE proposals DROP CONSTRAINT IF EXISTS proposals_execution_status_check;
ALTER TABLE proposals
  ADD CONSTRAINT proposals_execution_status_check CHECK (execution_status IN (
    'not_ready', 'ready', 'awaiting_funding', 'started', 'executed',
    'skipped', 'expired_unfunded', 'blocked'
  ));

UPDATE proposals
SET status = 'approved'
WHERE outcome = 'passed'
  AND executed_at IS NULL
  AND execution_status IN ('ready', 'awaiting_funding')
  AND status <> 'approved';

UPDATE proposals
SET challenge_status = 'none'
WHERE challenge_status IS NULL;
