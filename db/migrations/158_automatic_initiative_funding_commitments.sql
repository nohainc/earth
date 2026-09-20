-- Governance-authorized funding is consumed by settlement, never by a Human.

ALTER TABLE initiative_funding_commitments
  ADD COLUMN IF NOT EXISTS commitment_type TEXT NOT NULL DEFAULT 'TREASURY';
ALTER TABLE initiative_funding_commitments DROP CONSTRAINT IF EXISTS initiative_funding_commitments_type_check;
ALTER TABLE initiative_funding_commitments ADD CONSTRAINT initiative_funding_commitments_type_check
  CHECK (commitment_type IN ('TREASURY','MATCHING'));
DROP INDEX IF EXISTS initiative_funding_commitments_scope_uq;
CREATE UNIQUE INDEX IF NOT EXISTS initiative_funding_commitments_scope_type_uq
  ON initiative_funding_commitments(initiative_id, source_type, source_id, commitment_type);

-- Backfill Governance-authorized commitments for initiatives migrated before
-- the automatic funding lifecycle existed.
INSERT INTO initiative_funding_commitments
  (id, initiative_id, source_type, source_id, authorized_units, committed_units,
   commitment_type, status, governance_proposal_id, created_game_day, correlation_id)
SELECT 'INIT-COMMITMENT-' || i.id, i.id, i.scope_type, i.scope_id,
       i.treasury_authorized_units, 0, 'TREASURY', 'AUTHORIZED',
       i.governance_proposal_id, i.created_game_day,
       'initiative-commitment:treasury:' || i.governance_proposal_id
  FROM v5_initiatives i
 WHERE NOT EXISTS (
   SELECT 1 FROM initiative_funding_commitments c
    WHERE c.initiative_id = i.id AND c.commitment_type = 'TREASURY'
 )
ON CONFLICT (correlation_id) DO NOTHING;

INSERT INTO initiative_funding_commitments
  (id, initiative_id, source_type, source_id, authorized_units, committed_units,
   commitment_type, status, governance_proposal_id, created_game_day, correlation_id)
SELECT 'INIT-COMMITMENT-' || i.id || '-MATCHING', i.id, i.scope_type, i.scope_id,
       i.matching_cap_units, 0, 'MATCHING', 'AUTHORIZED',
       i.governance_proposal_id, i.created_game_day,
       'initiative-commitment:matching:' || i.governance_proposal_id
  FROM v5_initiatives i
 WHERE NOT EXISTS (
   SELECT 1 FROM initiative_funding_commitments c
    WHERE c.initiative_id = i.id AND c.commitment_type = 'MATCHING'
 )
ON CONFLICT (correlation_id) DO NOTHING;
