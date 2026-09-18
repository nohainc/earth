-- EARTH ACTIVE MIGRATION: settlement finalization barrier
-- Settlement completion is only authoritative after all required phases,
-- shadow reconciliation, and final invariant checks have succeeded.

CREATE OR REPLACE FUNCTION earth_finalize_settlement_day(p_game_day BIGINT)
RETURNS BOOLEAN LANGUAGE plpgsql AS $$
DECLARE
  v_status TEXT;
  v_shadow_status TEXT;
BEGIN
  SELECT status INTO v_status
    FROM daily_settlement_runs
   WHERE game_day = p_game_day
   FOR UPDATE;

  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Settlement day % does not exist', p_game_day;
  END IF;
  IF v_status = 'completed' THEN
    RETURN TRUE;
  END IF;
  IF v_status <> 'running' THEN
    RAISE EXCEPTION 'Settlement day % has status % and cannot be finalized', p_game_day, v_status;
  END IF;

  IF EXISTS (
    SELECT 1 FROM daily_settlement_phase_runs
     WHERE game_day = p_game_day AND status <> 'completed'
  ) THEN
    RAISE EXCEPTION 'Settlement day % has incomplete required work', p_game_day;
  END IF;

  SELECT status INTO v_shadow_status
    FROM economy_shadow_runs
   WHERE game_day = p_game_day;
  IF v_shadow_status IS NULL OR v_shadow_status NOT IN ('reconciled', 'skipped') THEN
    RAISE EXCEPTION 'Settlement day % shadow reconciliation is not complete: %', p_game_day, COALESCE(v_shadow_status, 'missing');
  END IF;

  -- This is the final authoritative transaction. The cursor advance is the
  -- last state transition and is rolled back if any invariant fails.
  UPDATE daily_settlement_runs
     SET status = 'completed', completed_at = CURRENT_TIMESTAMP,
         current_phase = NULL, lease_owner = NULL,
         lease_heartbeat_at = NULL, updated_at = CURRENT_TIMESTAMP
   WHERE game_day = p_game_day AND status = 'running';

  PERFORM earth_advance_settlement_cursor(p_game_day);
  RETURN TRUE;
END;
$$;

-- Preserve the legacy entry point while making it safe: callers cannot bypass
-- final reconciliation by invoking the old completion function.
CREATE OR REPLACE FUNCTION earth_complete_settlement_day(p_game_day BIGINT)
RETURNS BOOLEAN LANGUAGE plpgsql AS $$
BEGIN
  RETURN earth_finalize_settlement_day(p_game_day);
END;
$$;
