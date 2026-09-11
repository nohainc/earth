-- Technology & Research V2 Plan 8: Economy V2-only research funding.

ALTER TABLE corporation_research_projects
  ADD COLUMN IF NOT EXISTS funding_transaction_id BIGINT REFERENCES economic_transactions(id);

UPDATE corporation_research_projects p
SET funding_transaction_id = t.id
FROM economic_transactions t
WHERE p.funding_transaction_id IS NULL
  AND t.source_id = p.id
  AND t.transaction_kind IN ('interactive', 'settlement_batch');

-- Unverifiable legacy rows cannot remain active under the V2 funding rule.
UPDATE corporation_research_projects
SET status = 'CANCELLED', updated_at = CURRENT_TIMESTAMP
WHERE status = 'ACTIVE' AND funding_transaction_id IS NULL;

ALTER TABLE corporation_research_projects
  ADD CONSTRAINT corporation_research_active_funded_ck
  CHECK (status <> 'ACTIVE' OR funding_transaction_id IS NOT NULL);

CREATE INDEX IF NOT EXISTS corporation_research_funding_idx
  ON corporation_research_projects (funding_transaction_id)
  WHERE funding_transaction_id IS NOT NULL;

-- Explicit recipient for research services. It is a normal account, so the
-- funding transfer remains conserved rather than silently becoming a sink.
INSERT INTO economic_accounts (owner_economic_id, asset_id, account_type, is_default_settlement)
SELECT o.economic_id, 1, 4, FALSE
FROM owner_registry o
WHERE o.id = 'SYSTEM'
  AND NOT EXISTS (
    SELECT 1 FROM economic_accounts a
    WHERE a.owner_economic_id = o.economic_id AND a.asset_id = 1 AND a.account_type = 4
  );

COMMENT ON COLUMN corporation_research_projects.funding_transaction_id IS
  'Economy V2 transaction that funded the project; active projects must have one.';
