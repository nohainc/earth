-- Technology & Research V2 Plan 6: research capacity is institutional, not inventory.

CREATE TABLE IF NOT EXISTS corporation_research_capacity_daily (
  corporation_economic_id BIGINT NOT NULL REFERENCES owner_registry(economic_id),
  game_day BIGINT NOT NULL CHECK (game_day >= 0),
  base_capacity_units BIGINT NOT NULL DEFAULT 0 CHECK (base_capacity_units >= 0),
  technology_modifier_bps INTEGER NOT NULL DEFAULT 0,
  effective_capacity_units BIGINT NOT NULL DEFAULT 0 CHECK (effective_capacity_units >= 0),
  source_building_count INTEGER NOT NULL DEFAULT 0 CHECK (source_building_count >= 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (corporation_economic_id, game_day)
);

CREATE INDEX IF NOT EXISTS corporation_research_capacity_day_idx
  ON corporation_research_capacity_daily (game_day, corporation_economic_id);

CREATE OR REPLACE FUNCTION earth_record_corporation_research_capacity(
  p_game_day BIGINT
)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE v_count BIGINT;
BEGIN
  IF p_game_day < 0 THEN
    RAISE EXCEPTION 'Research capacity game day must be non-negative';
  END IF;

  WITH base AS (
    SELECT p.owner_economic_id,
      SUM(ROUND(COALESCE(c.research_capacity_units_per_day, 0)
        * COALESCE(p.utilization, 1)
        * COALESCE(p.condition_efficiency, 1)))::BIGINT AS capacity_units,
      COUNT(*)::INTEGER AS building_count
    FROM building_settlement_plans p
    JOIN buildings b ON b.id = p.building_id
    JOIN building_catalog c ON c.id = COALESCE(b.catalog_id, b.building_type || '-t' || COALESCE(b.tier, 1))
    JOIN owner_registry owner ON owner.economic_id = p.owner_economic_id
      AND owner.owner_type ILIKE 'corporation'
    WHERE p.game_day = p_game_day
      AND COALESCE(c.research_capacity_units_per_day, 0) > 0
    GROUP BY p.owner_economic_id
  ), modifiers AS (
    SELECT p.corporation_economic_id,
      LEAST(2500, GREATEST(0, COALESCE(SUM(e.modifier_bps), 0)))::INTEGER AS modifier_bps
    FROM corporation_research_projects p
    JOIN technology_effects e ON e.technology_id = p.target_id
      AND e.effect_type = 'RESEARCH_CAPACITY'
    WHERE p.target_type = 'TECHNOLOGY' AND p.status = 'COMPLETED'
    GROUP BY p.corporation_economic_id
  )
  INSERT INTO corporation_research_capacity_daily (
    corporation_economic_id, game_day, base_capacity_units,
    technology_modifier_bps, effective_capacity_units, source_building_count
  )
  SELECT b.owner_economic_id, p_game_day, b.capacity_units,
    COALESCE(m.modifier_bps, 0),
    GREATEST(0, ROUND(b.capacity_units * (10000 + COALESCE(m.modifier_bps, 0)) / 10000.0))::BIGINT,
    b.building_count
  FROM base b
  LEFT JOIN modifiers m ON m.corporation_economic_id = b.owner_economic_id
  ON CONFLICT (corporation_economic_id, game_day) DO UPDATE SET
    base_capacity_units = EXCLUDED.base_capacity_units,
    technology_modifier_bps = EXCLUDED.technology_modifier_bps,
    effective_capacity_units = EXCLUDED.effective_capacity_units,
    source_building_count = EXCLUDED.source_building_count,
    created_at = CURRENT_TIMESTAMP;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

COMMENT ON TABLE corporation_research_capacity_daily IS
  'Derived institutional research capability. Research points are not an economic asset or tradable inventory.';
