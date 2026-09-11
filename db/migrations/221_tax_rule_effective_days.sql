-- Finance V2 Plan 11: immutable tax rules selected by settlement game day.

CREATE TABLE IF NOT EXISTS tax_rule_versions (
  id TEXT PRIMARY KEY,
  tax_rule_id TEXT NOT NULL REFERENCES tax_rules(id),
  scope TEXT NOT NULL,
  category TEXT NOT NULL,
  version INTEGER NOT NULL CHECK (version > 0),
  effective_from_game_day BIGINT NOT NULL CHECK (effective_from_game_day >= 0),
  effective_to_game_day BIGINT,
  rate_bps INTEGER NOT NULL CHECK (rate_bps BETWEEN 0 AND 10000),
  tax_base_definition TEXT NOT NULL,
  beneficiary_economic_id BIGINT NOT NULL REFERENCES owner_registry(economic_id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (tax_rule_id, version),
  UNIQUE (tax_rule_id, effective_from_game_day),
  CHECK (effective_to_game_day IS NULL OR effective_to_game_day >= effective_from_game_day)
);
CREATE INDEX IF NOT EXISTS tax_rule_versions_effective_idx
  ON tax_rule_versions(tax_rule_id, effective_from_game_day DESC);

INSERT INTO tax_rule_versions (
  id, tax_rule_id, scope, category, version, effective_from_game_day,
  rate_bps, tax_base_definition, beneficiary_economic_id
)
SELECT r.id || '-v' || r.version, r.id, r.scope, r.category, r.version, 0,
       ROUND(r.rate * 10000)::INTEGER,
       CASE r.category
         WHEN 'basic_income' THEN 'fixed_living_cost_levy'
         WHEN 'business' THEN 'incremental_business_revenue'
         WHEN 'market' THEN 'external_market_trade'
         ELSE r.category
       END,
       o.economic_id
FROM tax_rules r
JOIN owner_registry o ON o.id = 'OUC'
ON CONFLICT (id) DO NOTHING;

CREATE OR REPLACE FUNCTION earth_get_tax_rule_version(p_tax_rule_id TEXT, p_game_day BIGINT)
RETURNS tax_rule_versions
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  result tax_rule_versions;
BEGIN
  SELECT * INTO result FROM tax_rule_versions
  WHERE tax_rule_id = p_tax_rule_id
    AND effective_from_game_day <= p_game_day
    AND (effective_to_game_day IS NULL OR effective_to_game_day >= p_game_day)
  ORDER BY effective_from_game_day DESC, version DESC
  LIMIT 1;
  IF NOT FOUND THEN RAISE EXCEPTION 'No tax rule % applies on game day %', p_tax_rule_id, p_game_day; END IF;
  RETURN result;
END;
$$;

CREATE OR REPLACE FUNCTION earth_tax_rule_versions_are_immutable()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  RAISE EXCEPTION 'Historical tax rule versions are immutable';
END;
$$;
DROP TRIGGER IF EXISTS tax_rule_versions_immutable ON tax_rule_versions;
CREATE TRIGGER tax_rule_versions_immutable
BEFORE UPDATE OR DELETE ON tax_rule_versions
FOR EACH ROW EXECUTE FUNCTION earth_tax_rule_versions_are_immutable();
