-- EARTH ACTIVE MIGRATION: explicit public tax authority and traceable assessment basis

CREATE TABLE IF NOT EXISTS tax_authorities (
  id TEXT PRIMARY KEY,
  authority_type TEXT NOT NULL CHECK (authority_type IN ('EARTH','TERRITORY_GOVERNANCE')),
  territory_id TEXT REFERENCES territories(id),
  beneficiary_economic_id TEXT NOT NULL REFERENCES owner_registry(economic_id),
  status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','SUSPENDED','RETIRED')),
  effective_from_game_day BIGINT NOT NULL CHECK (effective_from_game_day >= 1),
  effective_to_game_day BIGINT,
  rules_version TEXT NOT NULL DEFAULT 'tax-authority-v1',
  correlation_id TEXT NOT NULL UNIQUE,
  CHECK ((authority_type = 'EARTH' AND territory_id IS NULL) OR (authority_type = 'TERRITORY_GOVERNANCE' AND territory_id IS NOT NULL)),
  CHECK (effective_to_game_day IS NULL OR effective_to_game_day >= effective_from_game_day)
);
CREATE UNIQUE INDEX IF NOT EXISTS tax_authorities_current_idx
  ON tax_authorities (authority_type, COALESCE(territory_id, 'EARTH'))
  WHERE status = 'ACTIVE' AND effective_to_game_day IS NULL;

INSERT INTO tax_authorities (id, authority_type, beneficiary_economic_id, effective_from_game_day, correlation_id)
VALUES ('TAX-AUTH-EARTH', 'EARTH', 'ECON-EARTH-001', 1, 'tax-authority-backfill:earth')
ON CONFLICT (id) DO NOTHING;

ALTER TABLE tax_rule_versions ADD COLUMN IF NOT EXISTS authority_type TEXT NOT NULL DEFAULT 'EARTH'
  CHECK (authority_type IN ('EARTH','TERRITORY_GOVERNANCE','LEGACY_CORPORATION'));
ALTER TABLE tax_rule_versions ADD COLUMN IF NOT EXISTS authority_id TEXT;
ALTER TABLE tax_rule_versions ADD COLUMN IF NOT EXISTS base_reference TEXT NOT NULL DEFAULT 'rule-defined';
ALTER TABLE tax_rule_versions ADD COLUMN IF NOT EXISTS base_amount_units BIGINT NOT NULL DEFAULT 0 CHECK (base_amount_units >= 0);
UPDATE tax_rule_versions SET authority_type = CASE WHEN scope = 'CORPORATION' THEN 'LEGACY_CORPORATION' ELSE 'EARTH' END,
  authority_id = CASE WHEN scope = 'CORPORATION' THEN beneficiary_economic_id ELSE 'EARTH' END
WHERE authority_id IS NULL;

ALTER TABLE tax_obligations ADD COLUMN IF NOT EXISTS nexus_type TEXT NOT NULL DEFAULT 'RESIDENCE'
  CHECK (nexus_type IN ('RESIDENCE','ASSET_LOCATION','MEMBERSHIP','TRANSACTION','EARTH'));
ALTER TABLE tax_obligations ADD COLUMN IF NOT EXISTS authority_type TEXT NOT NULL DEFAULT 'EARTH'
  CHECK (authority_type IN ('EARTH','TERRITORY_GOVERNANCE','LEGACY_CORPORATION'));
ALTER TABLE tax_obligations ADD COLUMN IF NOT EXISTS authority_id TEXT;
ALTER TABLE tax_obligations ADD COLUMN IF NOT EXISTS base_reference TEXT NOT NULL DEFAULT 'rule-defined';
ALTER TABLE tax_obligations ADD COLUMN IF NOT EXISTS due_game_day BIGINT;
ALTER TABLE tax_obligations ADD COLUMN IF NOT EXISTS correlation_id TEXT;
CREATE UNIQUE INDEX IF NOT EXISTS tax_obligations_correlation_idx ON tax_obligations (correlation_id) WHERE correlation_id IS NOT NULL;
ALTER TABLE financial_obligations ADD COLUMN IF NOT EXISTS authority_type TEXT NOT NULL DEFAULT 'EARTH'
  CHECK (authority_type IN ('EARTH','TERRITORY_GOVERNANCE','LEGACY_CORPORATION'));
ALTER TABLE financial_obligations ADD COLUMN IF NOT EXISTS authority_id TEXT;
ALTER TABLE financial_obligations ADD COLUMN IF NOT EXISTS base_reference TEXT NOT NULL DEFAULT 'rule-defined';
