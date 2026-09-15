-- EARTH ACTIVE MIGRATION: generic Organization offices and temporary authority grants

CREATE TABLE IF NOT EXISTS organization_offices (
  id TEXT PRIMARY KEY,
  organization_id TEXT NOT NULL REFERENCES organizations(id),
  office_code TEXT NOT NULL CHECK (office_code IN ('EXECUTIVE','TREASURER','GOVERNOR','OPERATOR','RESEARCHER')),
  name TEXT NOT NULL,
  authority_rules JSONB NOT NULL CHECK (jsonb_typeof(authority_rules) = 'object'),
  status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','RETIRED')),
  UNIQUE (organization_id, office_code)
);
CREATE TABLE IF NOT EXISTS organization_office_grants (
  id TEXT PRIMARY KEY,
  office_id TEXT NOT NULL REFERENCES organization_offices(id),
  principal_type TEXT NOT NULL CHECK (principal_type IN ('HUMAN','HOUSE')),
  principal_id TEXT NOT NULL,
  effective_from_game_day BIGINT NOT NULL,
  effective_to_game_day BIGINT,
  status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','REVOKED','EXPIRED')),
  appointed_by_human_id TEXT NOT NULL REFERENCES humans(id),
  correlation_id TEXT NOT NULL UNIQUE,
  CHECK (effective_to_game_day IS NULL OR effective_to_game_day >= effective_from_game_day)
);
CREATE UNIQUE INDEX IF NOT EXISTS organization_offices_one_human_holder_idx
  ON organization_office_grants (office_id) WHERE principal_type = 'HUMAN' AND status = 'ACTIVE' AND effective_to_game_day IS NULL;
CREATE INDEX IF NOT EXISTS organization_office_grants_principal_idx
  ON organization_office_grants (principal_type, principal_id, status, effective_from_game_day);

INSERT INTO organization_offices (id, organization_id, office_code, name, authority_rules)
SELECT 'OFFICE-' || o.id || '-' || x.code, o.id, x.code, x.name, x.rules::jsonb
FROM organizations o
CROSS JOIN (VALUES
  ('EXECUTIVE','Executive','{"actions":["ORGANIZATION_OPERATE"]}'),
  ('TREASURER','Treasurer','{"actions":["ECONOMIC_OWNER","ORGANIZATION_BUDGET_SPEND"]}'),
  ('GOVERNOR','Governor','{"actions":["GOVERNANCE","CHARTER_AMEND"]}'),
  ('OPERATOR','Operator','{"actions":["ORGANIZATION_OPERATE"]}'),
  ('RESEARCHER','Researcher','{"actions":["RESEARCH"]}')
) AS x(code, name, rules) ON CONFLICT (organization_id, office_code) DO NOTHING;
INSERT INTO organization_office_grants (id, office_id, principal_type, principal_id, effective_from_game_day, appointed_by_human_id, correlation_id)
SELECT 'GRANT-' || o.id || '-FOUNDER-' || x.code, 'OFFICE-' || o.id || '-' || x.code, 'HUMAN', h.id, o.created_game_day, h.id, 'office-backfill:' || o.id || ':' || x.code
FROM organizations o
JOIN humans h ON h.house_id = o.founder_house_id AND h.status = 'ACTIVE'
CROSS JOIN (VALUES ('EXECUTIVE'), ('TREASURER'), ('GOVERNOR')) AS x(code)
ON CONFLICT (correlation_id) DO NOTHING;
