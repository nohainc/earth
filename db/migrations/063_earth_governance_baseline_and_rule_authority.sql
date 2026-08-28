ALTER TABLE constitutional_rules
  ADD COLUMN IF NOT EXISTS authority text NOT NULL DEFAULT 'Earth';

UPDATE constitutional_rules
SET authority = CASE WHEN rule_number = '3.1' THEN 'Corporation' ELSE 'Earth' END;

-- The baseline is a real active Earth governance record. It is inserted only
-- when the world has no active OUC governance rule, and may later be replaced
-- through the normal governance process.
INSERT INTO governance_rules (
  id, institution_id, name, category, quorum_threshold, approval_threshold,
  voting_period_days, implementation_delay_days, version, status, created_by
)
SELECT
  'GOV-OUC-BASELINE-v1', institutions.id, 'Earth governance baseline',
  'governance', 0.25, 0.50, 30, 1, 1, 'active', human.id
FROM institutions
CROSS JOIN LATERAL (SELECT id FROM humans ORDER BY id LIMIT 1) human
WHERE institutions.kind = 'OUC'
  AND NOT EXISTS (
    SELECT 1
    FROM governance_rules
    WHERE governance_rules.institution_id = institutions.id
      AND governance_rules.status = 'active'
  )
ON CONFLICT (id) DO NOTHING;
