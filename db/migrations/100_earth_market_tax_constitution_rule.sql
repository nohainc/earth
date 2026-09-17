-- EARTH ACTIVE MIGRATION: move the global market transaction rate into the
-- typed Constitution envelope while retaining the legacy tax row as history
-- and metadata during the wider tax cutover.

INSERT INTO constitutional_rule_definitions_v5
  (rule_code, article_code, value_type, authority_model, policy_group, amendment_class, allowed_values)
VALUES
  ('EARTH.MARKET.TRANSACTION_TAX_RATE', 'TAXATION', 'RATE_BPS', 'EARTH_LOCKED', 'EARTH_MARKET_TAX', 'POLICY', '[]')
ON CONFLICT (rule_code) DO NOTHING;

INSERT INTO constitutional_rule_versions_v5
  (id, rule_code, authority_type, authority_id, version, value_json,
   effective_from_game_day, effective_to_game_day, status)
SELECT 'V5-CONST-EARTH-MARKET-TAX-' || t.id,
       'EARTH.MARKET.TRANSACTION_TAX_RATE', 'EARTH', 'EARTH', t.version,
       jsonb_build_object('value', t.rate_bps::TEXT),
       t.effective_from_game_day, t.effective_to_game_day,
       CASE WHEN t.effective_to_game_day IS NULL THEN 'ACTIVE' ELSE 'RETIRED' END
  FROM tax_rule_versions t
 WHERE t.scope = 'EARTH'
   AND t.tax_rule_id IN ('TAX-MARKET-TRANSACTION', 'TAX-OUC-MARKET')
ON CONFLICT (id) DO NOTHING;
