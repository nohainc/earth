-- EARTH ACTIVE MIGRATION: Corporation tax rates in the Constitution rule envelope.

INSERT INTO constitutional_rule_definitions_v5 (rule_code, article_code, value_type, authority_model, policy_group, amendment_class, allowed_values)
VALUES
  ('CORPORATION.TAX.INCOME_RATE', 'TAXATION', 'RATE_BPS', 'CORPORATION_LOCAL', 'CORPORATION:TAXATION', 'LOCAL_POLICY', '[]'),
  ('CORPORATION.TAX.SALES_RATE', 'TAXATION', 'RATE_BPS', 'CORPORATION_LOCAL', 'CORPORATION:TAXATION', 'LOCAL_POLICY', '[]'),
  ('CORPORATION.TAX.CORPORATE_RATE', 'TAXATION', 'RATE_BPS', 'CORPORATION_LOCAL', 'CORPORATION:TAXATION', 'LOCAL_POLICY', '[]'),
  ('CORPORATION.TAX.PROPERTY_RATE', 'TAXATION', 'RATE_BPS', 'CORPORATION_LOCAL', 'CORPORATION:TAXATION', 'LOCAL_POLICY', '[]')
ON CONFLICT (rule_code) DO NOTHING;

INSERT INTO constitutional_rule_versions_v5 (id, rule_code, authority_type, authority_id, version, value_json, effective_from_game_day, status)
SELECT 'V5-CONST-TAX-' || c.id || '-' || field.rule_code, field.rule_code, 'CORPORATION', c.id, 1,
       jsonb_build_object('value', COALESCE(c.tax_charter->>field.json_key, '0')), 1, 'ACTIVE'
  FROM corporations c
 CROSS JOIN (VALUES
   ('CORPORATION.TAX.INCOME_RATE', 'incomeTaxBps'),
   ('CORPORATION.TAX.SALES_RATE', 'salesTaxBps'),
   ('CORPORATION.TAX.CORPORATE_RATE', 'corporateTaxBps'),
   ('CORPORATION.TAX.PROPERTY_RATE', 'propertyTaxBps')
 ) AS field(rule_code, json_key)
ON CONFLICT (id) DO NOTHING;
