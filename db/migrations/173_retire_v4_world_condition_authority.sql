-- V5 cutover: WORLD_CONDITION is no longer a V4 governance action.
-- Persistent economic rules belong to the V5 Constitution. World Conditions may
-- be emitted only by typed Initiative outcomes or trusted system/scenario code.
ALTER TABLE governance_proposals_v4
  DROP CONSTRAINT IF EXISTS governance_proposals_v4_action_type_check;

ALTER TABLE governance_proposals_v4
  ADD CONSTRAINT governance_proposals_v4_action_type_check
  CHECK (action_type IN (
    'ORGANIZATION_BUDGET_SPEND',
    'TAX_RULE',
    'PUBLIC_PROJECT',
    'RESEARCH_FUNDING',
    'CHARTER_CHANGE',
    'ORGANIZATION_TECHNOLOGY_ADOPTION'
  ));
