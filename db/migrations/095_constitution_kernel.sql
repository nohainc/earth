-- EARTH ACTIVE MIGRATION: canonical Constitution & Governance Kernel envelope.

CREATE TABLE constitutional_rule_definitions_v5 (
  rule_code TEXT PRIMARY KEY,
  article_code TEXT NOT NULL,
  value_type TEXT NOT NULL CHECK (value_type IN ('BOOLEAN','INTEGER','CREDIT_UNITS','RATE_BPS','ENUM','GAME_DAYS','RESOURCE_UNITS','PROGRESSIVE_SCHEDULE_REF','POLICY_REFERENCE')),
  authority_model TEXT NOT NULL CHECK (authority_model IN ('EARTH_LOCKED','EARTH_DEFAULT_CORPORATION_OVERRIDE','CORPORATION_LOCAL')),
  policy_group TEXT NOT NULL,
  amendment_class TEXT NOT NULL CHECK (amendment_class IN ('FOUNDATIONAL','POLICY','LOCAL_POLICY','OPERATIONAL')),
  allowed_values JSONB NOT NULL DEFAULT '[]'::JSONB CHECK (jsonb_typeof(allowed_values) = 'array'),
  validation_schema JSONB NOT NULL DEFAULT '{}'::JSONB CHECK (jsonb_typeof(validation_schema) = 'object'),
  active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE constitutional_rule_versions_v5 (
  id TEXT PRIMARY KEY,
  rule_code TEXT NOT NULL REFERENCES constitutional_rule_definitions_v5(rule_code),
  authority_type TEXT NOT NULL CHECK (authority_type IN ('EARTH','CORPORATION')),
  authority_id TEXT NOT NULL,
  version INTEGER NOT NULL CHECK (version > 0),
  value_json JSONB NOT NULL,
  effective_from_game_day BIGINT NOT NULL CHECK (effective_from_game_day >= 1),
  effective_to_game_day BIGINT,
  status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('DRAFT','ACTIVE','RETIRED')),
  proposal_id TEXT REFERENCES v5_governance_proposals(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (rule_code, authority_type, authority_id, version),
  CHECK (effective_to_game_day IS NULL OR effective_to_game_day >= effective_from_game_day),
  CHECK ((authority_type = 'EARTH' AND authority_id = 'EARTH') OR authority_type = 'CORPORATION')
);

CREATE INDEX constitutional_rule_versions_effective_idx
  ON constitutional_rule_versions_v5 (rule_code, authority_type, authority_id, effective_from_game_day DESC, version DESC);
CREATE UNIQUE INDEX constitutional_rule_versions_one_active_idx
  ON constitutional_rule_versions_v5 (rule_code, authority_type, authority_id)
  WHERE status = 'ACTIVE' AND effective_to_game_day IS NULL;

CREATE TABLE constitutional_change_sets_v5 (
  proposal_id TEXT PRIMARY KEY REFERENCES v5_governance_proposals(id),
  authority_type TEXT NOT NULL CHECK (authority_type IN ('EARTH','CORPORATION')),
  authority_id TEXT NOT NULL,
  policy_group TEXT NOT NULL,
  changes JSONB NOT NULL CHECK (jsonb_typeof(changes) = 'array' AND jsonb_array_length(changes) > 0),
  base_version_snapshot JSONB NOT NULL DEFAULT '{}'::JSONB CHECK (jsonb_typeof(base_version_snapshot) = 'object'),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE resolved_constitution_snapshots_v5 (
  id TEXT PRIMARY KEY,
  authority_type TEXT NOT NULL CHECK (authority_type IN ('EARTH','CORPORATION')),
  authority_id TEXT NOT NULL,
  game_day BIGINT NOT NULL CHECK (game_day >= 1),
  rules_json JSONB NOT NULL CHECK (jsonb_typeof(rules_json) = 'object'),
  version_ids JSONB NOT NULL CHECK (jsonb_typeof(version_ids) = 'object'),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (authority_type, authority_id, game_day)
);

INSERT INTO constitutional_rule_definitions_v5 (rule_code, article_code, value_type, authority_model, policy_group, amendment_class, allowed_values)
VALUES
  ('EARTH.CAPACITY.STANDARD', 'TERRITORY_CAPACITY', 'INTEGER', 'EARTH_LOCKED', 'EARTH:CAPACITY_POLICY', 'POLICY', '[]'),
  ('EARTH.CAPACITY.BASE_RATE', 'TERRITORY_CAPACITY', 'CREDIT_UNITS', 'EARTH_LOCKED', 'EARTH:CAPACITY_POLICY', 'POLICY', '[]'),
  ('EARTH.CAPACITY.PROGRESSIVE_SCHEDULE', 'TERRITORY_CAPACITY', 'PROGRESSIVE_SCHEDULE_REF', 'EARTH_LOCKED', 'EARTH:CAPACITY_POLICY', 'POLICY', '[]'),
  ('CORPORATION.HOUSE_CAPACITY.BASE_RATE', 'TERRITORY_CAPACITY', 'CREDIT_UNITS', 'EARTH_DEFAULT_CORPORATION_OVERRIDE', 'HOUSE_CAPACITY_POLICY', 'LOCAL_POLICY', '[]'),
  ('CORPORATION.ADMISSION_POLICY', 'CORPORATION_GOVERNANCE', 'ENUM', 'CORPORATION_LOCAL', 'ADMISSION_POLICY', 'LOCAL_POLICY', '["OPEN","APPROVAL","INVITE_ONLY"]'),
  ('EARTH.HOUSE_INCOME_TAX', 'TAXATION', 'PROGRESSIVE_SCHEDULE_REF', 'EARTH_LOCKED', 'EARTH:HOUSE_INCOME_TAX', 'POLICY', '[]'),
  ('CORPORATION.HOUSE_INCOME_TAX', 'TAXATION', 'PROGRESSIVE_SCHEDULE_REF', 'CORPORATION_LOCAL', 'HOUSE_INCOME_TAX', 'LOCAL_POLICY', '[]')
ON CONFLICT (rule_code) DO NOTHING;

INSERT INTO constitutional_rule_versions_v5 (id, rule_code, authority_type, authority_id, version, value_json, effective_from_game_day, effective_to_game_day, status)
SELECT 'V5-CONST-EARTH-CAPACITY-' || p.version, 'EARTH.CAPACITY.STANDARD', 'EARTH', 'EARTH', p.version,
       jsonb_build_object('value', p.standard_territory_capacity_units::TEXT), p.effective_from_game_day, p.effective_to_game_day, p.status
  FROM v5_capacity_policy_versions p
ON CONFLICT (id) DO NOTHING;

INSERT INTO constitutional_rule_versions_v5 (id, rule_code, authority_type, authority_id, version, value_json, effective_from_game_day, effective_to_game_day, status)
SELECT 'V5-CONST-EARTH-RATE-' || p.version, 'EARTH.CAPACITY.BASE_RATE', 'EARTH', 'EARTH', p.version,
       jsonb_build_object('value', p.earth_base_capacity_rate_units::TEXT), p.effective_from_game_day, p.effective_to_game_day, p.status
  FROM v5_capacity_policy_versions p
ON CONFLICT (id) DO NOTHING;

INSERT INTO constitutional_rule_versions_v5 (id, rule_code, authority_type, authority_id, version, value_json, effective_from_game_day, effective_to_game_day, status)
SELECT 'V5-CONST-EARTH-SCHEDULE-' || p.version, 'EARTH.CAPACITY.PROGRESSIVE_SCHEDULE', 'EARTH', 'EARTH', p.version,
       jsonb_build_object('scheduleId', p.earth_corporation_schedule_id::TEXT), p.effective_from_game_day, p.effective_to_game_day, p.status
  FROM v5_capacity_policy_versions p
ON CONFLICT (id) DO NOTHING;

INSERT INTO constitutional_rule_versions_v5 (id, rule_code, authority_type, authority_id, version, value_json, effective_from_game_day, effective_to_game_day, status)
SELECT 'V5-CONST-CORP-RATE-' || p.corporation_id || '-' || p.version, 'CORPORATION.HOUSE_CAPACITY.BASE_RATE', 'CORPORATION', p.corporation_id, p.version,
       jsonb_build_object('value', p.house_base_capacity_rate_units::TEXT), p.effective_from_game_day, p.effective_to_game_day, p.status
  FROM corporation_capacity_policy_versions p
ON CONFLICT (id) DO NOTHING;

INSERT INTO constitutional_rule_versions_v5 (id, rule_code, authority_type, authority_id, version, value_json, effective_from_game_day, status)
SELECT 'V5-CONST-CORP-ADMISSION-' || c.id || '-1', 'CORPORATION.ADMISSION_POLICY', 'CORPORATION', c.id, 1,
       jsonb_build_object('value', c.admission_policy), 1, 'ACTIVE'
  FROM corporations c
 WHERE c.admission_policy IS NOT NULL
ON CONFLICT (id) DO NOTHING;
