-- EARTH ACTIVE MIGRATION: Organization technology adoption governance lifecycle

ALTER TABLE governance_proposals_v4 DROP CONSTRAINT IF EXISTS governance_proposals_v4_action_type_check;
ALTER TABLE governance_proposals_v4 ADD CONSTRAINT governance_proposals_v4_action_type_check CHECK (action_type IN ('ORGANIZATION_BUDGET_SPEND','TAX_RULE','PUBLIC_PROJECT','RESEARCH_FUNDING','CHARTER_CHANGE','WORLD_CONDITION','ORGANIZATION_TECHNOLOGY_ADOPTION'));
