-- Proposals are executed only by the end-of-day game engine.  A passed
-- proposal either executes immediately or receives seven complete upcoming
-- game days in which its treasury/capacity requirements can become available.

ALTER TABLE proposals
  ADD COLUMN IF NOT EXISTS funding_start_day BIGINT,
  ADD COLUMN IF NOT EXISTS funding_due_end_day BIGINT,
  ADD COLUMN IF NOT EXISTS funding_last_checked_day BIGINT,
  ADD COLUMN IF NOT EXISTS funding_block_reason TEXT,
  ADD COLUMN IF NOT EXISTS funding_requirements JSONB NOT NULL DEFAULT '{}'::jsonb;

-- Retire the legacy queued/challenge lifecycle without changing historical
-- outcomes. Any outstanding legacy item becomes a normal automatic retry.
UPDATE proposals
SET execution_status = 'awaiting_funding',
    funding_start_day = COALESCE(funding_start_day, expires_game_day),
    funding_due_end_day = COALESCE(funding_due_end_day, expires_game_day),
    funding_block_reason = COALESCE(funding_block_reason, 'Awaiting the required city resources or capacity')
WHERE execution_status IN ('queued', 'challenged', 'voided', 'expired');

ALTER TABLE proposals DROP CONSTRAINT IF EXISTS proposals_execution_status_check;
ALTER TABLE proposals
  ADD CONSTRAINT proposals_execution_status_check CHECK (execution_status IN (
    'not_ready', 'ready', 'awaiting_funding', 'executed', 'skipped',
    'expired_unfunded', 'blocked'
  ));

CREATE INDEX IF NOT EXISTS proposals_funding_window_idx
  ON proposals (execution_status, funding_due_end_day)
  WHERE execution_status = 'awaiting_funding';

-- One durable action per passed proposal. The 137 migration is safe for
-- already-resolved proposals while all new actions are created at resolution.
INSERT INTO scheduled_actions (
  owner_id, action_type, due_game_day, due_game_minute, due_end_game_day,
  priority, payload, status, correlation_id
)
SELECT p.institution_id, 'proposal_execution',
       COALESCE(p.implementation_due_end_day, p.resolved_game_day, p.voting_due_end_day),
       0, COALESCE(p.implementation_due_end_day, p.resolved_game_day, p.voting_due_end_day),
       80, jsonb_build_object('proposalId', p.id), 'pending', 'proposal-execution:' || p.id
FROM proposals p
WHERE p.outcome = 'passed'
  AND p.executed_at IS NULL
  AND p.execution_status IN ('ready', 'awaiting_funding')
ON CONFLICT (correlation_id) DO NOTHING;
