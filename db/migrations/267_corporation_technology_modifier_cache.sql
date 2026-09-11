-- Technology & Research V2 Plan 13: one bulk modifier source for economic
-- consumers. Cache rows are projections and can be rebuilt for any day.

CREATE TABLE IF NOT EXISTS corporation_technology_modifier_cache (
  corporation_economic_id BIGINT NOT NULL REFERENCES owner_registry(economic_id),
  game_day BIGINT NOT NULL CHECK (game_day >= 0),
  production_output_bps INTEGER NOT NULL DEFAULT 0,
  material_input_bps INTEGER NOT NULL DEFAULT 0,
  energy_input_bps INTEGER NOT NULL DEFAULT 0,
  construction_time_bps INTEGER NOT NULL DEFAULT 0,
  construction_cost_bps INTEGER NOT NULL DEFAULT 0,
  wear_bps INTEGER NOT NULL DEFAULT 0,
  repair_efficiency_bps INTEGER NOT NULL DEFAULT 0,
  research_capacity_bps INTEGER NOT NULL DEFAULT 0,
  service_capacity_bps INTEGER NOT NULL DEFAULT 0,
  scoped_modifiers JSONB NOT NULL DEFAULT '{}'::JSONB,
  source_count INTEGER NOT NULL DEFAULT 0 CHECK (source_count >= 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (corporation_economic_id, game_day)
);

CREATE INDEX IF NOT EXISTS corporation_technology_modifier_cache_day_idx
  ON corporation_technology_modifier_cache (game_day, corporation_economic_id);

CREATE OR REPLACE FUNCTION earth_rebuild_corporation_technology_modifier_cache(
  p_game_day BIGINT
)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE v_count BIGINT;
BEGIN
  IF p_game_day < 0 THEN
    RAISE EXCEPTION 'Technology modifier cache game day must be non-negative';
  END IF;

  WITH resolved AS (
    SELECT access.corporation_economic_id,
      e.effect_type, e.target_type, e.target_key,
      LEAST(rule.maximum_bps, GREATEST(rule.minimum_bps, SUM(e.modifier_bps)))::INTEGER AS modifier_bps,
      COUNT(DISTINCT e.technology_id)::INTEGER AS source_count
    FROM corporation_technology_access access
    JOIN technology_effects e ON e.technology_id = access.technology_id
    JOIN technology_catalog technology ON technology.id = e.technology_id
    JOIN technology_modifier_rules rule ON rule.family_code = e.modifier_family
    WHERE access.status = 'ACTIVE'
      AND access.effective_from_game_day <= p_game_day
      AND (access.effective_to_game_day IS NULL OR access.effective_to_game_day >= p_game_day)
      AND technology.status = 'ACTIVE'
      AND technology.effective_from_game_day <= p_game_day
      AND (technology.effective_to_game_day IS NULL OR technology.effective_to_game_day >= p_game_day)
      AND rule.effective_from_game_day <= p_game_day
      AND (rule.effective_to_game_day IS NULL OR rule.effective_to_game_day >= p_game_day)
    GROUP BY access.corporation_economic_id, e.effect_type, e.target_type, e.target_key,
      rule.minimum_bps, rule.maximum_bps
  ), grouped AS (
    SELECT corporation_economic_id,
      COALESCE(SUM(modifier_bps) FILTER (WHERE effect_type = 'PRODUCTION_OUTPUT' AND target_type = 'ALL_BUILDINGS' AND target_key = 'ALL'), 0)::INTEGER AS production_output_bps,
      COALESCE(SUM(modifier_bps) FILTER (WHERE effect_type IN ('RESOURCE_INPUT') AND target_key IN ('ALL', 'MATERIAL')), 0)::INTEGER AS material_input_bps,
      COALESCE(SUM(modifier_bps) FILTER (WHERE effect_type IN ('RESOURCE_INPUT') AND target_key IN ('ALL', 'ENERGY')), 0)::INTEGER AS energy_input_bps,
      COALESCE(SUM(modifier_bps) FILTER (WHERE effect_type = 'CONSTRUCTION_TIME'), 0)::INTEGER AS construction_time_bps,
      COALESCE(SUM(modifier_bps) FILTER (WHERE effect_type = 'CONSTRUCTION_RESOURCE_COST'), 0)::INTEGER AS construction_cost_bps,
      COALESCE(SUM(modifier_bps) FILTER (WHERE effect_type = 'BUILDING_WEAR'), 0)::INTEGER AS wear_bps,
      COALESCE(SUM(modifier_bps) FILTER (WHERE effect_type = 'REPAIR_EFFICIENCY'), 0)::INTEGER AS repair_efficiency_bps,
      COALESCE(SUM(modifier_bps) FILTER (WHERE effect_type = 'RESEARCH_CAPACITY'), 0)::INTEGER AS research_capacity_bps,
      COALESCE(SUM(modifier_bps) FILTER (WHERE effect_type = 'SERVICE_CAPACITY'), 0)::INTEGER AS service_capacity_bps,
      jsonb_object_agg(effect_type || ':' || target_type || ':' || target_key, modifier_bps) AS scoped_modifiers,
      SUM(source_count)::INTEGER AS source_count
    FROM resolved
    GROUP BY corporation_economic_id
  )
  INSERT INTO corporation_technology_modifier_cache (
    corporation_economic_id, game_day, production_output_bps, material_input_bps,
    energy_input_bps, construction_time_bps, construction_cost_bps, wear_bps,
    repair_efficiency_bps, research_capacity_bps, service_capacity_bps,
    scoped_modifiers, source_count
  )
  SELECT corporation_economic_id, p_game_day, production_output_bps, material_input_bps,
    energy_input_bps, construction_time_bps, construction_cost_bps, wear_bps,
    repair_efficiency_bps, research_capacity_bps, service_capacity_bps,
    scoped_modifiers, source_count
  FROM grouped
  ON CONFLICT (corporation_economic_id, game_day) DO UPDATE SET
    production_output_bps = EXCLUDED.production_output_bps,
    material_input_bps = EXCLUDED.material_input_bps,
    energy_input_bps = EXCLUDED.energy_input_bps,
    construction_time_bps = EXCLUDED.construction_time_bps,
    construction_cost_bps = EXCLUDED.construction_cost_bps,
    wear_bps = EXCLUDED.wear_bps,
    repair_efficiency_bps = EXCLUDED.repair_efficiency_bps,
    research_capacity_bps = EXCLUDED.research_capacity_bps,
    service_capacity_bps = EXCLUDED.service_capacity_bps,
    scoped_modifiers = EXCLUDED.scoped_modifiers,
    source_count = EXCLUDED.source_count,
    updated_at = CURRENT_TIMESTAMP;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

COMMENT ON TABLE corporation_technology_modifier_cache IS
  'Bulk, game-day-effective corporation technology modifiers consumed by buildings, construction, and research.';

