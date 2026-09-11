-- Technology & Research V2 Plan 16: research capacity uses the shared,
-- game-day-effective modifier cache. A technology completed on Day N is
-- synchronized into access after Day N's research run and therefore affects
-- capacity beginning on Day N + 1.

CREATE OR REPLACE FUNCTION earth_advance_corporation_research_v2(
  p_game_day BIGINT
)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE v_completed BIGINT;
BEGIN
  IF p_game_day < 0 THEN
    RAISE EXCEPTION 'Research game day must be non-negative';
  END IF;

  UPDATE building_settlement_plans p
  SET research_capacity_units = ROUND(COALESCE(c.research_capacity_units_per_day, 0)
      * COALESCE(p.utilization, 1) * COALESCE(p.condition_efficiency, 1))::BIGINT,
      research_points_generated = ROUND(COALESCE(c.research_capacity_units_per_day, 0)
      * COALESCE(p.utilization, 1) * COALESCE(p.condition_efficiency, 1))::BIGINT
  FROM buildings b
  JOIN building_catalog c ON c.id = COALESCE(b.catalog_id, b.building_type || '-t' || COALESCE(b.tier, 1))
  WHERE p.building_id = b.id AND p.game_day = p_game_day;

  WITH corporation_capacity AS (
    SELECT p.owner_economic_id,
      SUM(ROUND(COALESCE(c.research_capacity_units_per_day, 0)
        * COALESCE(p.utilization, 1)
        * COALESCE(p.condition_efficiency, 1)))::BIGINT AS base_capacity
    FROM building_settlement_plans p
    JOIN buildings b ON b.id = p.building_id
    JOIN building_catalog c ON c.id = COALESCE(b.catalog_id, b.building_type || '-t' || COALESCE(b.tier, 1))
    WHERE p.game_day = p_game_day
      AND COALESCE(c.research_capacity_units_per_day, 0) > 0
    GROUP BY p.owner_economic_id
  ), ranked_projects AS (
    SELECT p.id, p.required_research_points, p.progress_research_points,
      LEAST(p.required_research_points - p.progress_research_points,
        GREATEST(0, ROUND(c.base_capacity
          * (10000 + COALESCE(m.research_capacity_bps, 0)) / 10000.0))::BIGINT) AS points,
      ROW_NUMBER() OVER (
        PARTITION BY p.corporation_economic_id
        ORDER BY p.priority DESC, p.created_at, p.id
      ) AS project_rank
    FROM corporation_research_projects p
    JOIN corporation_capacity c ON c.owner_economic_id = p.corporation_economic_id
    LEFT JOIN corporation_technology_modifier_cache m
      ON m.corporation_economic_id = p.corporation_economic_id
     AND m.game_day = p_game_day
    WHERE p.status IN ('QUEUED', 'ACTIVE')
      AND p.progress_research_points < p.required_research_points
  ), updated AS (
    UPDATE corporation_research_projects p
    SET progress_research_points = p.progress_research_points + r.points,
        status = CASE WHEN p.progress_research_points + r.points >= p.required_research_points THEN 'COMPLETED' ELSE 'ACTIVE' END,
        started_game_day = COALESCE(p.started_game_day, p_game_day),
        completed_game_day = CASE WHEN p.progress_research_points + r.points >= p.required_research_points THEN p_game_day ELSE p.completed_game_day END,
        updated_at = CURRENT_TIMESTAMP
    FROM ranked_projects r
    WHERE p.id = r.id AND r.project_rank = 1 AND r.points > 0
    RETURNING p.status
  )
  SELECT COUNT(*) FILTER (WHERE status = 'COMPLETED') INTO v_completed FROM updated;

  RETURN COALESCE(v_completed, 0);
END;
$$;

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
  )
  INSERT INTO corporation_research_capacity_daily (
    corporation_economic_id, game_day, base_capacity_units,
    technology_modifier_bps, effective_capacity_units, source_building_count
  )
  SELECT b.owner_economic_id, p_game_day, b.capacity_units,
    COALESCE(m.research_capacity_bps, 0),
    GREATEST(0, ROUND(b.capacity_units * (10000 + COALESCE(m.research_capacity_bps, 0)) / 10000.0))::BIGINT,
    b.building_count
  FROM base b
  LEFT JOIN corporation_technology_modifier_cache m
    ON m.corporation_economic_id = b.owner_economic_id
   AND m.game_day = p_game_day
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

COMMENT ON FUNCTION earth_advance_corporation_research_v2(BIGINT) IS
  'Advances one highest-priority research project using the day-effective corporation technology modifier cache.';
