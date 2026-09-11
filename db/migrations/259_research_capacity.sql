-- Technology & Research V2 Plan 5: research capacity drives project progress.

ALTER TABLE building_catalog
  ADD COLUMN IF NOT EXISTS research_capacity_units_per_day BIGINT NOT NULL DEFAULT 0;
ALTER TABLE building_catalog
  ADD CONSTRAINT building_catalog_research_capacity_ck
  CHECK (research_capacity_units_per_day >= 0);

UPDATE building_catalog
SET research_capacity_units_per_day = GREATEST(0,
  COALESCE((effects ->> 'research_capacity')::BIGINT, 0) * 10)
WHERE research_capacity_units_per_day = 0
  AND effects ? 'research_capacity';

ALTER TABLE building_settlement_plans
  ADD COLUMN IF NOT EXISTS research_capacity_units BIGINT NOT NULL DEFAULT 0;
ALTER TABLE building_settlement_plans
  ADD COLUMN IF NOT EXISTS research_points_generated BIGINT NOT NULL DEFAULT 0;

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
  ), technology_modifiers AS (
    SELECT r.economic_id AS corporation_economic_id,
      LEAST(2500, GREATEST(0, COALESCE(SUM(e.modifier_bps), 0)))::BIGINT AS modifier_bps
    FROM corporation_research_projects p
    JOIN owner_registry r ON r.economic_id = p.corporation_economic_id
    JOIN technology_effects e ON e.technology_id = p.target_id
      AND e.effect_type = 'RESEARCH_CAPACITY'
    JOIN technology_modifier_rules mr ON mr.family_code = e.modifier_family
    WHERE p.target_type = 'TECHNOLOGY'
      AND p.status = 'COMPLETED'
      AND r.owner_type ILIKE 'corporation'
      AND mr.effective_from_game_day <= p_game_day
      AND (mr.effective_to_game_day IS NULL OR mr.effective_to_game_day >= p_game_day)
    GROUP BY r.economic_id
  ), ranked_projects AS (
    SELECT p.id, p.required_research_points, p.progress_research_points,
      LEAST(p.required_research_points - p.progress_research_points,
        GREATEST(0, ROUND(c.base_capacity *
          (10000 + COALESCE(m.modifier_bps, 0)) / 10000.0))::BIGINT) AS points,
      ROW_NUMBER() OVER (
        PARTITION BY p.corporation_economic_id
        ORDER BY p.priority DESC, p.created_at, p.id
      ) AS project_rank
    FROM corporation_research_projects p
    JOIN corporation_capacity c ON c.owner_economic_id = p.corporation_economic_id
    LEFT JOIN technology_modifiers m ON m.corporation_economic_id = p.corporation_economic_id
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

COMMENT ON FUNCTION earth_advance_corporation_research_v2(BIGINT) IS
  'Advances one highest-priority unified research project per corporation using effective daily building capacity.';
