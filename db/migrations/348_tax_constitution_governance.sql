-- Plan 10: constitutional tax scope, caps, and proposal-authorized changes.

CREATE TABLE IF NOT EXISTS tax_governance_rules (
  scope TEXT NOT NULL CHECK (scope IN ('OUC', 'CITY', 'CORPORATION')),
  category TEXT NOT NULL,
  minimum_rate_bps INTEGER NOT NULL DEFAULT 0 CHECK (minimum_rate_bps >= 0),
  maximum_rate_bps INTEGER NOT NULL CHECK (maximum_rate_bps >= minimum_rate_bps AND maximum_rate_bps <= 10000),
  allowed_tax_base_definitions JSONB NOT NULL CHECK (jsonb_typeof(allowed_tax_base_definitions) = 'array'),
  beneficiary_scope TEXT NOT NULL CHECK (beneficiary_scope IN ('OUC', 'CITY', 'CORPORATION')),
  rules_version TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (scope, category)
);

INSERT INTO tax_governance_rules
  (scope, category, maximum_rate_bps, allowed_tax_base_definitions, beneficiary_scope, rules_version)
VALUES
  ('OUC', 'basic_levy', 2000, '["fixed_daily_obligation"]', 'OUC', 'tax-constitution-v1'),
  ('OUC', 'personal_income', 3000, '["positive_realized_daily_income"]', 'OUC', 'tax-constitution-v1'),
  ('OUC', 'market_transaction', 1000, '["external_market_trade"]', 'OUC', 'tax-constitution-v1'),
  ('CITY', 'personal_income', 3000, '["positive_realized_daily_income"]', 'CITY', 'tax-constitution-v1'),
  ('CITY', 'property', 2500, '["assessed_property_value"]', 'CITY', 'tax-constitution-v1'),
  ('CITY', 'building', 2500, '["assessed_building_value"]', 'CITY', 'tax-constitution-v1'),
  ('CORPORATION', 'corporate_income', 4000, '["positive_realized_daily_taxable_profit"]', 'CORPORATION', 'tax-constitution-v1'),
  ('CORPORATION', 'market_transaction', 1000, '["external_market_trade"]', 'CORPORATION', 'tax-constitution-v1')
ON CONFLICT (scope, category) DO NOTHING;

ALTER TABLE tax_rule_versions
  ADD COLUMN IF NOT EXISTS authorization_proposal_id TEXT REFERENCES proposals(id);

CREATE OR REPLACE FUNCTION earth_validate_tax_rule_governance()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE rule tax_governance_rules%ROWTYPE;
BEGIN
  SELECT * INTO rule FROM tax_governance_rules
  WHERE scope = NEW.scope AND category = NEW.category;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Tax scope/category is not constitutionally permitted: %/%', NEW.scope, NEW.category;
  END IF;
  IF NEW.rate_bps < rule.minimum_rate_bps OR NEW.rate_bps > rule.maximum_rate_bps THEN
    RAISE EXCEPTION 'Tax rate % exceeds constitutional range for %/%', NEW.rate_bps, NEW.scope, NEW.category;
  END IF;
  IF NOT (rule.allowed_tax_base_definitions ? NEW.tax_base_definition) THEN
    RAISE EXCEPTION 'Tax base % is not permitted for %/%', NEW.tax_base_definition, NEW.scope, NEW.category;
  END IF;
  IF NEW.authorization_proposal_id IS NULL THEN
    RAISE EXCEPTION 'New tax rule versions require an approved proposal';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS tax_rule_versions_governance_trigger ON tax_rule_versions;
CREATE TRIGGER tax_rule_versions_governance_trigger
BEFORE INSERT ON tax_rule_versions
FOR EACH ROW EXECUTE FUNCTION earth_validate_tax_rule_governance();

CREATE OR REPLACE FUNCTION earth_create_tax_rule_version(
  p_tax_rule_id TEXT, p_scope TEXT, p_category TEXT, p_rate_bps INTEGER,
  p_tax_base_definition TEXT, p_beneficiary_economic_id BIGINT,
  p_effective_from_game_day BIGINT, p_authorization_proposal_id TEXT
)
RETURNS TEXT LANGUAGE plpgsql AS $$
DECLARE next_version INTEGER; latest_day BIGINT; new_id TEXT;
BEGIN
  IF p_effective_from_game_day < 0 THEN RAISE EXCEPTION 'Tax effective day must be non-negative'; END IF;
  IF NOT EXISTS (SELECT 1 FROM proposals WHERE id = p_authorization_proposal_id AND decision_status = 'passed') THEN
    RAISE EXCEPTION 'Tax change requires a passed proposal';
  END IF;
  SELECT COALESCE(MAX(version), 0) + 1, COALESCE(MAX(effective_from_game_day), -1)
    INTO next_version, latest_day
  FROM tax_rule_versions WHERE tax_rule_id = p_tax_rule_id;
  IF p_effective_from_game_day <= latest_day THEN
    RAISE EXCEPTION 'Tax rule versions cannot be retroactive or overlap: % <= %', p_effective_from_game_day, latest_day;
  END IF;
  new_id := p_tax_rule_id || '-v' || next_version;
  INSERT INTO tax_rule_versions (id, tax_rule_id, scope, category, version,
    effective_from_game_day, rate_bps, tax_base_definition, beneficiary_economic_id, authorization_proposal_id)
  VALUES (new_id, p_tax_rule_id, p_scope, p_category, next_version,
    p_effective_from_game_day,
    p_rate_bps, p_tax_base_definition, p_beneficiary_economic_id, p_authorization_proposal_id);
  RETURN new_id;
END;
$$;
