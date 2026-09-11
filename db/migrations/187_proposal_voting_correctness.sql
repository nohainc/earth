-- Proposal Engine V2: governance rule selection and voting invariants.

ALTER TABLE governance_rules
  ADD COLUMN IF NOT EXISTS voting_period_days INTEGER NOT NULL DEFAULT 3;

-- Keep existing databases installable when earlier proposal work left more than
-- one active version in a category. The newest version remains authoritative.
WITH ranked AS (
  SELECT id,
         ROW_NUMBER() OVER (
           PARTITION BY institution_id, category
           ORDER BY version DESC, created_at DESC, id DESC
         ) AS rank
  FROM governance_rules
  WHERE status = 'active'
)
UPDATE governance_rules AS rules
SET status = 'superseded'
FROM ranked
WHERE rules.id = ranked.id
  AND ranked.rank > 1;

CREATE UNIQUE INDEX IF NOT EXISTS governance_rules_one_active_category
  ON governance_rules(institution_id, category)
  WHERE status = 'active';
