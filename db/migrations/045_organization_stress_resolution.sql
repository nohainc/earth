-- EARTH ACTIVE MIGRATION: organization stress, claims, and resolution cases

CREATE TABLE IF NOT EXISTS organization_financial_states (
  organization_id TEXT PRIMARY KEY REFERENCES organizations(id),
  status TEXT NOT NULL CHECK (status IN ('HEALTHY','WATCH','STRESS','INSOLVENT','RESOLUTION')),
  assets_units BIGINT NOT NULL CHECK (assets_units >= 0),
  liabilities_units BIGINT NOT NULL CHECK (liabilities_units >= 0),
  liquid_units BIGINT NOT NULL CHECK (liquid_units >= 0),
  overdue_units BIGINT NOT NULL CHECK (overdue_units >= 0),
  since_game_day BIGINT NOT NULL,
  evaluated_game_day BIGINT NOT NULL,
  rules_version TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS organization_financial_state_history (
  id TEXT PRIMARY KEY,
  organization_id TEXT NOT NULL REFERENCES organizations(id),
  status TEXT NOT NULL CHECK (status IN ('HEALTHY','WATCH','STRESS','INSOLVENT','RESOLUTION')),
  assets_units BIGINT NOT NULL CHECK (assets_units >= 0),
  liabilities_units BIGINT NOT NULL CHECK (liabilities_units >= 0),
  liquid_units BIGINT NOT NULL CHECK (liquid_units >= 0),
  overdue_units BIGINT NOT NULL CHECK (overdue_units >= 0),
  game_day BIGINT NOT NULL,
  rules_version TEXT NOT NULL,
  correlation_id TEXT NOT NULL UNIQUE
);
CREATE INDEX IF NOT EXISTS organization_financial_state_history_org_day_idx ON organization_financial_state_history (organization_id, game_day DESC);

CREATE TABLE IF NOT EXISTS organization_resolution_cases (
  id TEXT PRIMARY KEY,
  organization_id TEXT NOT NULL REFERENCES organizations(id),
  case_type TEXT NOT NULL CHECK (case_type IN ('RESTRUCTURE','MERGER','SPLIT','DISSOLUTION')),
  status TEXT NOT NULL DEFAULT 'OPEN' CHECK (status IN ('OPEN','APPROVED','EXECUTING','COMPLETED','CANCELLED')),
  opened_game_day BIGINT NOT NULL,
  effective_game_day BIGINT,
  approved_proposal_id TEXT REFERENCES governance_proposals_v4(id),
  correlation_id TEXT NOT NULL UNIQUE,
  details JSONB NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(details) = 'object')
);
CREATE INDEX IF NOT EXISTS organization_resolution_cases_org_status_idx ON organization_resolution_cases (organization_id, status, opened_game_day DESC);

CREATE TABLE IF NOT EXISTS organization_creditor_claims (
  id TEXT PRIMARY KEY,
  organization_id TEXT NOT NULL REFERENCES organizations(id),
  creditor_economic_id TEXT NOT NULL REFERENCES owner_registry(economic_id),
  source_type TEXT NOT NULL,
  source_id TEXT NOT NULL,
  claim_units BIGINT NOT NULL CHECK (claim_units > 0),
  priority_rank INTEGER NOT NULL CHECK (priority_rank > 0),
  status TEXT NOT NULL DEFAULT 'OPEN' CHECK (status IN ('OPEN','PAID','RESTRUCTURED','WRITTEN_OFF')),
  created_game_day BIGINT NOT NULL,
  correlation_id TEXT NOT NULL UNIQUE
);
CREATE INDEX IF NOT EXISTS organization_creditor_claims_resolution_idx ON organization_creditor_claims (organization_id, status, priority_rank, created_game_day);

CREATE TABLE IF NOT EXISTS organization_successor_mappings (
  id TEXT PRIMARY KEY,
  resolution_case_id TEXT NOT NULL REFERENCES organization_resolution_cases(id),
  predecessor_organization_id TEXT NOT NULL REFERENCES organizations(id),
  successor_organization_id TEXT NOT NULL REFERENCES organizations(id),
  transferred_asset_units BIGINT NOT NULL DEFAULT 0 CHECK (transferred_asset_units >= 0),
  effective_game_day BIGINT NOT NULL,
  correlation_id TEXT NOT NULL UNIQUE,
  CHECK (predecessor_organization_id <> successor_organization_id)
);
