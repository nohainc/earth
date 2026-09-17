-- EARTH ACTIVE MIGRATION: expose the Earth House capacity schedule in the canonical rule registry.

INSERT INTO constitutional_rule_definitions_v5 (rule_code, article_code, value_type, authority_model, policy_group, amendment_class, allowed_values)
VALUES ('EARTH.CAPACITY.HOUSE_PROGRESSIVE_SCHEDULE', 'TERRITORY_CAPACITY', 'PROGRESSIVE_SCHEDULE_REF', 'EARTH_LOCKED', 'EARTH:CAPACITY_POLICY', 'POLICY', '[]')
ON CONFLICT (rule_code) DO NOTHING;

INSERT INTO constitutional_rule_versions_v5 (id, rule_code, authority_type, authority_id, version, value_json, effective_from_game_day, effective_to_game_day, status)
SELECT 'V5-CONST-EARTH-HOUSE-SCHEDULE-' || p.version, 'EARTH.CAPACITY.HOUSE_PROGRESSIVE_SCHEDULE', 'EARTH', 'EARTH', p.version,
       jsonb_build_object('scheduleId', p.earth_house_schedule_id::TEXT), p.effective_from_game_day, p.effective_to_game_day, p.status
  FROM v5_capacity_policy_versions p
ON CONFLICT (id) DO NOTHING;
