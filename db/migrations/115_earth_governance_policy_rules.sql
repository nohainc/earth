-- EARTH ACTIVE MIGRATION: give Earth constitutional governance its own rule
-- namespace. Corporation policy rules remain Earth defaults with local
-- Corporation overrides; Earth-wide amendments must not masquerade as them.

INSERT INTO constitutional_rule_definitions_v5
  (rule_code, article_code, value_type, authority_model, policy_group,
   amendment_class, allowed_values)
VALUES
  ('EARTH.GOVERNANCE.POLICY_QUORUM_BPS', 'EARTH_GOVERNANCE', 'RATE_BPS', 'EARTH_LOCKED', 'EARTH_GOVERNANCE_POLICY', 'POLICY', '[]'),
  ('EARTH.GOVERNANCE.POLICY_APPROVAL_BPS', 'EARTH_GOVERNANCE', 'RATE_BPS', 'EARTH_LOCKED', 'EARTH_GOVERNANCE_POLICY', 'POLICY', '[]'),
  ('EARTH.GOVERNANCE.VOTING_PERIOD_DAYS', 'EARTH_GOVERNANCE', 'GAME_DAYS', 'EARTH_LOCKED', 'EARTH_GOVERNANCE_POLICY', 'POLICY', '[]'),
  ('EARTH.GOVERNANCE.IMPLEMENTATION_DELAY_DAYS', 'EARTH_GOVERNANCE', 'GAME_DAYS', 'EARTH_LOCKED', 'EARTH_GOVERNANCE_POLICY', 'POLICY', '[]')
ON CONFLICT (rule_code) DO NOTHING;

INSERT INTO constitutional_rule_versions_v5
  (id, rule_code, authority_type, authority_id, version, value_json,
   effective_from_game_day, status)
VALUES
  ('V5-CONST-EARTH-GOV-EARTH-QUORUM-V1', 'EARTH.GOVERNANCE.POLICY_QUORUM_BPS', 'EARTH', 'EARTH', 1, '{"value":"2500"}', 1, 'ACTIVE'),
  ('V5-CONST-EARTH-GOV-EARTH-APPROVAL-V1', 'EARTH.GOVERNANCE.POLICY_APPROVAL_BPS', 'EARTH', 'EARTH', 1, '{"value":"5000"}', 1, 'ACTIVE'),
  ('V5-CONST-EARTH-GOV-EARTH-PERIOD-V1', 'EARTH.GOVERNANCE.VOTING_PERIOD_DAYS', 'EARTH', 'EARTH', 1, '{"value":"3"}', 1, 'ACTIVE'),
  ('V5-CONST-EARTH-GOV-EARTH-DELAY-V1', 'EARTH.GOVERNANCE.IMPLEMENTATION_DELAY_DAYS', 'EARTH', 'EARTH', 1, '{"value":"0"}', 1, 'ACTIVE')
ON CONFLICT (id) DO NOTHING;
