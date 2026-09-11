-- Proposal Engine V2: separate decision and execution state machines.

ALTER TABLE proposals
  ADD COLUMN IF NOT EXISTS decision_status TEXT;

UPDATE proposals
SET decision_status = CASE
  WHEN outcome = 'passed' THEN 'passed'
  WHEN outcome = 'rejected' THEN 'rejected'
  WHEN outcome = 'no_quorum' THEN 'no_quorum'
  WHEN status = 'open' THEN 'voting'
  ELSE 'scheduled'
END
WHERE decision_status IS NULL;

ALTER TABLE proposals ALTER COLUMN decision_status SET DEFAULT 'scheduled';
ALTER TABLE proposals ALTER COLUMN decision_status SET NOT NULL;
ALTER TABLE proposals DROP CONSTRAINT IF EXISTS proposals_decision_status_check;
ALTER TABLE proposals ADD CONSTRAINT proposals_decision_status_check CHECK (decision_status IN ('scheduled','voting','passed','rejected','no_quorum','cancelled'));

CREATE INDEX IF NOT EXISTS proposals_decision_execution_idx ON proposals(decision_status, execution_status, voting_due_end_day);
