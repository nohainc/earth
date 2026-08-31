-- Migration 089: Seed Baseline Governance Rules for All Institutions
--
-- Ensures every active City, Corporation, and OUC Council has an active
-- baseline governance rule for voting thresholds, quorum, and duration.

INSERT INTO governance_rules (
  id, institution_id, name, category, quorum_threshold, approval_threshold,
  voting_period_days, implementation_delay_days, version, status, created_by
)
SELECT
  'GOV-' || institutions.id || '-BASELINE-v1',
  institutions.id,
  institutions.name || ' Governance Baseline',
  'governance',
  0.25,
  0.50,
  30,
  1,
  1,
  'active',
  human.id
FROM institutions
CROSS JOIN LATERAL (SELECT id FROM humans ORDER BY id LIMIT 1) human
WHERE institutions.kind IN ('CITY', 'CORPORATION', 'OUC')
  AND NOT EXISTS (
    SELECT 1
    FROM governance_rules
    WHERE governance_rules.institution_id = institutions.id
      AND governance_rules.status = 'active'
  )
ON CONFLICT (id) DO NOTHING;
