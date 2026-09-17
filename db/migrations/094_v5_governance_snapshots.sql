-- EARTH ACTIVE MIGRATION: V5 governance rule and electorate snapshots.

ALTER TABLE v5_governance_proposals
  ADD COLUMN IF NOT EXISTS quorum_bps INTEGER NOT NULL DEFAULT 2500 CHECK (quorum_bps BETWEEN 0 AND 10000),
  ADD COLUMN IF NOT EXISTS approval_bps INTEGER NOT NULL DEFAULT 5000 CHECK (approval_bps BETWEEN 0 AND 10000),
  ADD COLUMN IF NOT EXISTS electorate_snapshot_game_day BIGINT,
  ADD COLUMN IF NOT EXISTS electorate_size INTEGER NOT NULL DEFAULT 0 CHECK (electorate_size >= 0),
  ADD COLUMN IF NOT EXISTS abstain_votes INTEGER NOT NULL DEFAULT 0 CHECK (abstain_votes >= 0),
  ADD COLUMN IF NOT EXISTS governance_rule_snapshot JSONB NOT NULL DEFAULT '{}'::JSONB CHECK (jsonb_typeof(governance_rule_snapshot) = 'object'),
  ADD COLUMN IF NOT EXISTS base_version_snapshot JSONB NOT NULL DEFAULT '{}'::JSONB CHECK (jsonb_typeof(base_version_snapshot) = 'object'),
  ADD COLUMN IF NOT EXISTS policy_group TEXT;

ALTER TABLE v5_governance_proposals DROP CONSTRAINT IF EXISTS v5_governance_proposals_status_check;
ALTER TABLE v5_governance_proposals ADD CONSTRAINT v5_governance_proposals_status_check
  CHECK (status IN ('VOTING','PASSED','REJECTED','SCHEDULED','ACTIVATED','EXECUTED','STALE','FAILED','CANCELLED'));

UPDATE v5_governance_proposals
SET electorate_snapshot_game_day = voting_start_game_day,
    electorate_size = CASE WHEN subject_type = 'CORPORATION'
      THEN (SELECT COUNT(*) FROM house_affiliations ha WHERE ha.corporation_id = subject_id
            AND ha.status = 'ACTIVE' AND ha.joined_game_day <= voting_start_game_day
            AND (ha.left_game_day IS NULL OR ha.left_game_day >= voting_start_game_day))
      ELSE (SELECT COUNT(*) FROM houses WHERE status = 'ACTIVE') END,
    governance_rule_snapshot = jsonb_build_object('quorumBps', quorum_bps, 'approvalBps', approval_bps, 'votingPeriodDays', 3, 'implementationDelayDays', 0),
    policy_group = CASE action_type
      WHEN 'EARTH_CAPACITY_POLICY' THEN 'EARTH:CAPACITY_POLICY'
      WHEN 'PROGRESSIVE_SCHEDULE' THEN 'EARTH:PROGRESSIVE_SCHEDULE'
      WHEN 'CORPORATION_HOUSE_RATE' THEN 'CORPORATION:' || COALESCE(subject_id, '') || ':HOUSE_CAPACITY_POLICY'
      WHEN 'CORPORATION_ADMISSION_POLICY' THEN 'CORPORATION:' || COALESCE(subject_id, '') || ':ADMISSION_POLICY'
      ELSE action_type END
WHERE electorate_snapshot_game_day IS NULL;

CREATE INDEX v5_governance_proposals_policy_group_idx
  ON v5_governance_proposals (policy_group, status);
