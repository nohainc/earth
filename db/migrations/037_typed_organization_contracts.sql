-- EARTH ACTIVE MIGRATION: typed Organization commerce contracts

CREATE TABLE IF NOT EXISTS contract_templates (
  id TEXT PRIMARY KEY,
  contract_type TEXT NOT NULL CHECK (contract_type IN ('RECURRING_SERVICE','PROJECT_PROCUREMENT','LICENSE','GUARANTEE','COMMITMENT')),
  name TEXT NOT NULL UNIQUE,
  terms_schema JSONB NOT NULL CHECK (jsonb_typeof(terms_schema) = 'object'),
  schema_version INTEGER NOT NULL CHECK (schema_version > 0),
  status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','RETIRED'))
);
CREATE TABLE IF NOT EXISTS organization_contracts (
  id TEXT PRIMARY KEY,
  template_id TEXT NOT NULL REFERENCES contract_templates(id),
  buyer_organization_id TEXT NOT NULL REFERENCES organizations(id),
  seller_organization_id TEXT NOT NULL REFERENCES organizations(id),
  terms JSONB NOT NULL CHECK (jsonb_typeof(terms) = 'object'),
  status TEXT NOT NULL DEFAULT 'PENDING_SIGNATURE' CHECK (status IN ('PENDING_SIGNATURE','ACTIVE','COMPLETED','TERMINATED','CANCELLED')),
  start_game_day BIGINT NOT NULL,
  end_game_day BIGINT NOT NULL CHECK (end_game_day >= start_game_day),
  amount_per_period BIGINT NOT NULL CHECK (amount_per_period > 0),
  period_days INTEGER NOT NULL CHECK (period_days > 0),
  created_by_human_id TEXT NOT NULL REFERENCES humans(id),
  correlation_id TEXT NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS organization_contract_signatures (
  contract_id TEXT NOT NULL REFERENCES organization_contracts(id),
  organization_id TEXT NOT NULL REFERENCES organizations(id),
  signed_by_human_id TEXT NOT NULL REFERENCES humans(id),
  signed_game_day BIGINT NOT NULL,
  correlation_id TEXT NOT NULL UNIQUE,
  PRIMARY KEY (contract_id, organization_id)
);
CREATE TABLE IF NOT EXISTS contract_performance_events (
  id TEXT PRIMARY KEY,
  contract_id TEXT NOT NULL REFERENCES organization_contracts(id),
  period_start_game_day BIGINT NOT NULL,
  period_end_game_day BIGINT NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('DUE','PERFORMED','FAILED','WAIVED')),
  obligation_id TEXT REFERENCES financial_obligations(id),
  correlation_id TEXT NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS organization_contracts_party_status_idx ON organization_contracts (buyer_organization_id, status, end_game_day);
CREATE INDEX IF NOT EXISTS contract_performance_due_idx ON contract_performance_events (status, period_end_game_day);

INSERT INTO contract_templates (id, contract_type, name, terms_schema, schema_version)
VALUES
 ('CONTRACT-RECURRING-SERVICE-V1','RECURRING_SERVICE','Recurring service','{"required":["serviceCode","amountPerPeriod","periodDays"]}'::jsonb,1),
 ('CONTRACT-PROCUREMENT-V1','PROJECT_PROCUREMENT','Project procurement','{"required":["deliverable","amountPerPeriod","periodDays"]}'::jsonb,1),
 ('CONTRACT-LICENSE-V1','LICENSE','Technology license','{"required":["patentId","amountPerPeriod","periodDays"]}'::jsonb,1),
 ('CONTRACT-GUARANTEE-V1','GUARANTEE','Performance guarantee','{"required":["guaranteedAmount","periodDays"]}'::jsonb,1)
ON CONFLICT (id) DO NOTHING;
