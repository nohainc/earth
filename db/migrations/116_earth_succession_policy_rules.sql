-- EARTH ACTIVE MIGRATION: succession cost and transition settings are typed
-- Earth Constitution policy values, not a legacy governance JSON blob.

INSERT INTO constitutional_rule_definitions_v5
  (rule_code, article_code, value_type, authority_model, policy_group,
   amendment_class, allowed_values)
VALUES
  ('EARTH.SUCCESSION.COST_UNITS', 'SUCCESSION', 'CREDIT_UNITS', 'EARTH_LOCKED', 'SUCCESSION_POLICY', 'POLICY', '[]'),
  ('EARTH.SUCCESSION.COST_BPS', 'SUCCESSION', 'RATE_BPS', 'EARTH_LOCKED', 'SUCCESSION_POLICY', 'POLICY', '[]'),
  ('EARTH.SUCCESSION.TRANSITION_DAYS', 'SUCCESSION', 'GAME_DAYS', 'EARTH_LOCKED', 'SUCCESSION_POLICY', 'POLICY', '[]')
ON CONFLICT (rule_code) DO NOTHING;

-- Preserve legacy object-form values when they exist. A missing legacy policy
-- remains equivalent to the old optional behavior: no succession charge.
INSERT INTO constitutional_rule_versions_v5
  (id, rule_code, authority_type, authority_id, version, value_json,
   effective_from_game_day, effective_to_game_day, status)
SELECT 'V5-CONST-EARTH-SUCCESSION-COST-UNITS-' || r.id,
       'EARTH.SUCCESSION.COST_UNITS', 'EARTH', 'EARTH', r.version,
       jsonb_build_object('value', COALESCE(r.value_json->>'successionCostUnits', '0')),
       r.effective_from_game_day, r.effective_to_game_day,
       CASE WHEN lower(r.status) = 'active' THEN 'ACTIVE' ELSE 'RETIRED' END
  FROM governance_rules r
 WHERE r.institution_id = 'EARTH'
   AND r.category = 'succession'
   AND jsonb_typeof(r.value_json) = 'object'
ON CONFLICT (id) DO NOTHING;

INSERT INTO constitutional_rule_versions_v5
  (id, rule_code, authority_type, authority_id, version, value_json,
   effective_from_game_day, effective_to_game_day, status)
SELECT 'V5-CONST-EARTH-SUCCESSION-COST-BPS-' || r.id,
       'EARTH.SUCCESSION.COST_BPS', 'EARTH', 'EARTH', r.version,
       jsonb_build_object('value', COALESCE(r.value_json->>'successionCostBps', '0')),
       r.effective_from_game_day, r.effective_to_game_day,
       CASE WHEN lower(r.status) = 'active' THEN 'ACTIVE' ELSE 'RETIRED' END
  FROM governance_rules r
 WHERE r.institution_id = 'EARTH'
   AND r.category = 'succession'
   AND jsonb_typeof(r.value_json) = 'object'
ON CONFLICT (id) DO NOTHING;

INSERT INTO constitutional_rule_versions_v5
  (id, rule_code, authority_type, authority_id, version, value_json,
   effective_from_game_day, effective_to_game_day, status)
SELECT 'V5-CONST-EARTH-SUCCESSION-TRANSITION-' || r.id,
       'EARTH.SUCCESSION.TRANSITION_DAYS', 'EARTH', 'EARTH', r.version,
       jsonb_build_object('value', COALESCE(r.value_json->>'successionTransitionDays', '1')),
       r.effective_from_game_day, r.effective_to_game_day,
       CASE WHEN lower(r.status) = 'active' THEN 'ACTIVE' ELSE 'RETIRED' END
  FROM governance_rules r
 WHERE r.institution_id = 'EARTH'
   AND r.category = 'succession'
   AND jsonb_typeof(r.value_json) = 'object'
ON CONFLICT (id) DO NOTHING;
