-- An explicit, audited cut-over. This is never called automatically.
CREATE OR REPLACE FUNCTION earth_activate_daily_settlement(
  p_baseline_game_day BIGINT,
  p_activated_by TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
  v_current_day BIGINT;
BEGIN
  SELECT earth_game_day_from_total_minutes(total_game_minutes)
    INTO v_current_day FROM earth_get_current_game_time();
  IF p_baseline_game_day < 1 OR p_baseline_game_day >= v_current_day THEN
    RAISE EXCEPTION 'Baseline day must be between 1 and the last fully ended day (%)', v_current_day - 1;
  END IF;
  IF EXISTS (SELECT 1 FROM daily_settlement_runs WHERE status IN ('completed', 'baseline')) THEN
    RAISE EXCEPTION 'Daily settlement is already initialized';
  END IF;
  INSERT INTO daily_settlement_runs (game_day, status, current_phase, completed_at)
  VALUES (p_baseline_game_day, 'baseline', 'baseline', CURRENT_TIMESTAMP);
  UPDATE daily_settlement_control
  SET status = 'active', activated_at = CURRENT_TIMESTAMP, activated_by = p_activated_by,
      updated_at = CURRENT_TIMESTAMP
  WHERE id = 'WORLD';
END;
$$;
