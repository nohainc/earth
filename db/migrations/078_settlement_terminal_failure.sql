-- EARTH ACTIVE MIGRATION: propagate terminal phase failures to the daily run

CREATE OR REPLACE FUNCTION earth_fail_settlement_day(
  p_work_id BIGINT, p_worker_id TEXT, p_error_message TEXT
) RETURNS BOOLEAN LANGUAGE plpgsql AS $$
DECLARE
  v_game_day BIGINT;
  v_status TEXT;
  v_updated BOOLEAN := FALSE;
BEGIN
  UPDATE daily_settlement_phase_runs
     SET status = CASE WHEN attempt_count >= 5 THEN 'failed' ELSE 'pending' END,
         lease_owner = NULL, lease_expires_at = NULL,
         error_message = LEFT(p_error_message, 1000), updated_at = CURRENT_TIMESTAMP
   WHERE id = p_work_id AND status = 'running' AND lease_owner = p_worker_id
   RETURNING game_day, status INTO v_game_day, v_status;

  IF FOUND THEN
    v_updated := TRUE;
    IF v_status = 'failed' THEN
      UPDATE daily_settlement_runs
         SET status = 'failed',
             current_phase = (SELECT phase_id FROM daily_settlement_phase_runs WHERE id = p_work_id),
             error_message = LEFT(p_error_message, 1000),
             updated_at = CURRENT_TIMESTAMP
       WHERE game_day = v_game_day AND status = 'running';
    END IF;
  END IF;

  RETURN v_updated;
END;
$$;
