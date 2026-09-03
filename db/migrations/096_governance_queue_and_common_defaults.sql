-- Migration 096: allow passed civic proposals to wait for city capacity/resources.

ALTER TABLE proposals DROP CONSTRAINT IF EXISTS proposals_execution_status_check;
ALTER TABLE proposals
  ADD CONSTRAINT proposals_execution_status_check
  CHECK (execution_status IN ('not_ready', 'ready', 'queued', 'executed', 'skipped', 'challenged', 'voided'));

-- Convert only the old seeded baseline (not custom rule versions) to the
-- common Earth default of a three-day voting period.
UPDATE governance_rules
SET voting_period_days = 3
WHERE id LIKE 'GOV-%-BASELINE-v1'
  AND voting_period_days = 30;
