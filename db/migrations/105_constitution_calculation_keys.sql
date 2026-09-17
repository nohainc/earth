-- EARTH ACTIVE MIGRATION: make registry-to-calculation dispatch explicit.

ALTER TABLE constitutional_rule_definitions_v5
  ADD COLUMN IF NOT EXISTS calculation_key TEXT;

UPDATE constitutional_rule_definitions_v5
   SET calculation_key = CASE rule_code
     WHEN 'EARTH.CAPACITY.STANDARD' THEN 'earth.capacity.standard'
     WHEN 'EARTH.CAPACITY.BASE_RATE' THEN 'earth.capacity.base_rate'
     WHEN 'EARTH.CAPACITY.PROGRESSIVE_SCHEDULE' THEN 'earth.capacity.progressive_schedule'
     WHEN 'EARTH.CAPACITY.HOUSE_PROGRESSIVE_SCHEDULE' THEN 'earth.capacity.house_progressive_schedule'
     WHEN 'CORPORATION.HOUSE_CAPACITY.BASE_RATE' THEN 'corporation.house_capacity.base_rate'
     WHEN 'CORPORATION.ADMISSION_POLICY' THEN 'corporation.admission_policy'
     WHEN 'CORPORATION.GOVERNANCE.POLICY_QUORUM_BPS' THEN 'corporation.governance.policy_quorum_bps'
     WHEN 'CORPORATION.GOVERNANCE.POLICY_APPROVAL_BPS' THEN 'corporation.governance.policy_approval_bps'
     WHEN 'CORPORATION.GOVERNANCE.VOTING_PERIOD_DAYS' THEN 'corporation.governance.voting_period_days'
     WHEN 'CORPORATION.GOVERNANCE.IMPLEMENTATION_DELAY_DAYS' THEN 'corporation.governance.implementation_delay_days'
     WHEN 'EARTH.HOUSE_INCOME_TAX' THEN 'earth.house_income_tax'
     WHEN 'EARTH.TAX.BASIC_LEVY_RATE' THEN 'earth.tax.basic_levy_rate'
     WHEN 'EARTH.MARKET.TRANSACTION_TAX_RATE' THEN 'earth.market.transaction_tax_rate'
     WHEN 'CORPORATION.HOUSE_INCOME_TAX' THEN 'corporation.house_income_tax'
     WHEN 'CORPORATION.TAX.INCOME_RATE' THEN 'corporation.tax.income_rate'
     WHEN 'CORPORATION.TAX.SALES_RATE' THEN 'corporation.tax.sales_rate'
     WHEN 'CORPORATION.TAX.CORPORATE_RATE' THEN 'corporation.tax.corporate_rate'
     WHEN 'CORPORATION.TAX.PROPERTY_RATE' THEN 'corporation.tax.property_rate'
     ELSE 'constitution.' || lower(replace(rule_code, '.', '_'))
   END
 WHERE calculation_key IS NULL;

ALTER TABLE constitutional_rule_definitions_v5
  ALTER COLUMN calculation_key SET NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS constitutional_rule_definitions_calculation_key_idx
  ON constitutional_rule_definitions_v5 (calculation_key);
