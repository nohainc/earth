-- EARTH ACTIVE MIGRATION: move the global basic levy rate into the typed
-- Constitution envelope while retaining the legacy tax row for history.

INSERT INTO constitutional_rule_definitions_v5
  (rule_code, article_code, value_type, authority_model, policy_group, amendment_class, allowed_values)
VALUES
  ('EARTH.TAX.BASIC_LEVY_RATE', 'TAXATION', 'RATE_BPS', 'EARTH_LOCKED', 'EARTH_BASIC_LEVY', 'POLICY', '[]')
ON CONFLICT (rule_code) DO NOTHING;

INSERT INTO constitutional_rule_versions_v5
  (id, rule_code, authority_type, authority_id, version, value_json,
   effective_from_game_day, effective_to_game_day, status)
SELECT 'V5-CONST-EARTH-BASIC-LEVY-' || t.id,
       'EARTH.TAX.BASIC_LEVY_RATE', 'EARTH', 'EARTH', t.version,
       jsonb_build_object('value', t.rate_bps::TEXT),
       t.effective_from_game_day, t.effective_to_game_day,
       CASE WHEN t.effective_to_game_day IS NULL THEN 'ACTIVE' ELSE 'RETIRED' END
  FROM tax_rule_versions t
 WHERE t.scope = 'EARTH'
   AND t.tax_rule_id = 'TAX-BASIC-LEVY'
ON CONFLICT (id) DO NOTHING;
