-- EARTH ACTIVE MIGRATION: initiatives are created only by activated V5 governance proposals.

ALTER TABLE v5_governance_proposals DROP CONSTRAINT IF EXISTS v5_governance_proposals_action_type_check;
ALTER TABLE v5_governance_proposals ADD CONSTRAINT v5_governance_proposals_action_type_check
  CHECK (action_type IN (
    'CONSTITUTION_AMENDMENT',
    'CORPORATION_PUBLIC_CONSTRUCTION',
    'CORPORATION_BUILDING_RESEARCH',
    'CORPORATION_SCALE_RESEARCH',
    'EARTH_TECHNOLOGY_FRONTIER',
    'INITIATIVE_CREATE',
    'EARTH_CAPACITY_POLICY',
    'CORPORATION_HOUSE_RATE',
    'PROGRESSIVE_SCHEDULE',
    'CORPORATION_ADMISSION_POLICY'
  ));

CREATE TABLE IF NOT EXISTS v5_initiatives (
  id TEXT PRIMARY KEY,
  scope_type TEXT NOT NULL CHECK (scope_type IN ('EARTH','CORPORATION')),
  scope_id TEXT,
  initiative_type TEXT NOT NULL CHECK (initiative_type IN ('PROGRAM','PUBLIC_PROJECT','EMERGENCY','COMMONS')),
  name TEXT NOT NULL,
  description TEXT NOT NULL,
  program_type TEXT CHECK (program_type IS NULL OR program_type IN ('TECHNOLOGY','COMMONS','EMERGENCY')),
  funding_target_units BIGINT NOT NULL CHECK (funding_target_units > 0),
  treasury_authorized_units BIGINT NOT NULL DEFAULT 0 CHECK (treasury_authorized_units >= 0),
  matching_policy TEXT NOT NULL DEFAULT 'NONE' CHECK (matching_policy IN ('NONE','LINEAR_MATCH','BREADTH_MATCH')),
  matching_cap_units BIGINT NOT NULL DEFAULT 0 CHECK (matching_cap_units >= 0),
  funding_deadline_game_day BIGINT NOT NULL CHECK (funding_deadline_game_day >= 1),
  funding_model TEXT NOT NULL CHECK (funding_model IN ('TREASURY','CROWDFUND','MATCHED','MIXED')),
  execution_model TEXT NOT NULL CHECK (execution_model IN ('FUNDING_ONLY','TIMED_PROGRAM','PUBLIC_WORK')),
  outcome JSONB NOT NULL CHECK (jsonb_typeof(outcome) = 'object'),
  physical_target JSONB CHECK (physical_target IS NULL OR jsonb_typeof(physical_target) = 'object'),
  governance_proposal_id TEXT NOT NULL UNIQUE REFERENCES v5_governance_proposals(id),
  status TEXT NOT NULL DEFAULT 'FUNDING' CHECK (status IN ('FUNDING','FUNDED','EXECUTING','COMPLETED','FAILED','CANCELLED')),
  effective_game_day BIGINT NOT NULL CHECK (effective_game_day >= 1),
  created_game_day BIGINT NOT NULL CHECK (created_game_day >= 1),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CHECK ((scope_type = 'EARTH' AND scope_id IS NULL) OR (scope_type = 'CORPORATION' AND scope_id IS NOT NULL)),
  CHECK (treasury_authorized_units >= funding_target_units OR funding_model IN ('CROWDFUND','MATCHED','MIXED')),
  CHECK (matching_cap_units = 0 OR matching_policy <> 'NONE')
);
CREATE INDEX IF NOT EXISTS v5_initiatives_scope_status_idx ON v5_initiatives(scope_type, scope_id, status, funding_deadline_game_day);

-- Existing tables remain readable during the migration, but all newly materialized
-- records carry canonical V5 provenance. The old V4 references are retained only
-- as historical compatibility columns and are no longer used by player paths.
ALTER TABLE global_programs DROP CONSTRAINT IF EXISTS global_programs_authorization_proposal_id_fkey;
ALTER TABLE public_projects DROP CONSTRAINT IF EXISTS public_projects_proposal_id_fkey;
ALTER TABLE global_programs ADD COLUMN IF NOT EXISTS initiative_id TEXT REFERENCES v5_initiatives(id);
ALTER TABLE global_programs ADD COLUMN IF NOT EXISTS governance_proposal_id TEXT REFERENCES v5_governance_proposals(id);
ALTER TABLE public_projects ADD COLUMN IF NOT EXISTS initiative_id TEXT REFERENCES v5_initiatives(id);
ALTER TABLE public_projects ADD COLUMN IF NOT EXISTS governance_proposal_id TEXT REFERENCES v5_governance_proposals(id);
