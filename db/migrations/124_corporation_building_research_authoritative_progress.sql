-- Corporation building-tier research uses the database clock exclusively.
-- The caller supplies no clock values; the stored function calculates and
-- persists progress, completion timestamps, catalog activation, and unlocks.

CREATE OR REPLACE FUNCTION earth_advance_corporation_building_research()
RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_total_game_minutes BIGINT;
  v_game_day BIGINT;
  v_game_minute INTEGER;
  v_completed INTEGER := 0;
BEGIN
  SELECT total_game_minutes
    INTO v_total_game_minutes
    FROM earth_get_current_game_time();

  v_game_day := earth_game_day_from_total_minutes(v_total_game_minutes);
  v_game_minute := earth_minute_of_day_from_total_minutes(v_total_game_minutes);

  WITH due AS (
    SELECT
      p.id,
      p.corporation_id,
      p.catalog_id,
      GREATEST(0, v_total_game_minutes - ((p.started_game_day - 1) * 1440 + p.started_game_minute)) AS elapsed_minutes,
      GREATEST(1, p.duration_minutes) AS duration_minutes
    FROM corporation_building_research_projects p
    WHERE p.status = 'active'
    FOR UPDATE
  ), updated AS (
    UPDATE corporation_building_research_projects p
       SET progress = LEAST(100, ROUND((d.elapsed_minutes::NUMERIC / d.duration_minutes) * 100, 3)),
           status = CASE WHEN d.elapsed_minutes >= d.duration_minutes THEN 'completed' ELSE 'active' END,
           completed_game_day = CASE WHEN d.elapsed_minutes >= d.duration_minutes THEN v_game_day ELSE NULL END,
           completed_game_minute = CASE WHEN d.elapsed_minutes >= d.duration_minutes THEN v_game_minute ELSE NULL END,
           updated_at = CURRENT_TIMESTAMP
      FROM due d
     WHERE p.id = d.id
    RETURNING d.corporation_id, d.catalog_id, p.id AS research_project_id,
              d.elapsed_minutes >= d.duration_minutes AS completed_now
  ), completed AS (
    SELECT * FROM updated WHERE completed_now
  ), activated AS (
    UPDATE building_catalog c
       SET is_active = true, updated_at = CURRENT_TIMESTAMP
      FROM completed done
     WHERE c.id = done.catalog_id
    RETURNING c.id
  )
  INSERT INTO corporation_building_unlocks (
    corporation_id, catalog_id, research_project_id, unlocked_game_day
  )
  SELECT corporation_id, catalog_id, research_project_id, v_game_day
    FROM completed
  ON CONFLICT (corporation_id, catalog_id) DO UPDATE
    SET status = 'unlocked',
        research_project_id = EXCLUDED.research_project_id,
        unlocked_game_day = EXCLUDED.unlocked_game_day;

  GET DIAGNOSTICS v_completed = ROW_COUNT;
  RETURN v_completed;
END;
$$;
