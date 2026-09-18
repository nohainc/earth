-- Stored Function: earth_advance_settlement_cursor
--
-- Contiguous settlement cursor advancement on daily_settlement_control.
CREATE OR REPLACE FUNCTION earth_advance_settlement_cursor(p_completed_game_day BIGINT)
RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE
  v_current_cursor BIGINT;
  v_day_status TEXT;
BEGIN
  SELECT settled_through_game_day INTO v_current_cursor
  FROM daily_settlement_control
  WHERE id = 'WORLD'
  FOR UPDATE;

  IF v_current_cursor IS NULL THEN
    RAISE EXCEPTION 'daily_settlement_control record not found';
  END IF;

  IF p_completed_game_day <= v_current_cursor THEN
    RETURN v_current_cursor;
  END IF;

  IF p_completed_game_day <> v_current_cursor + 1 THEN
    RAISE EXCEPTION 'Cannot advance settlement cursor from % to %: non-contiguous settlement', v_current_cursor, p_completed_game_day;
  END IF;

  SELECT status INTO v_day_status
  FROM daily_settlement_runs
  WHERE game_day = p_completed_game_day;

  IF v_day_status <> 'completed' THEN
    RAISE EXCEPTION 'Cannot advance settlement cursor: game day % status is % (must be completed)', p_completed_game_day, COALESCE(v_day_status, 'missing');
  END IF;

  UPDATE daily_settlement_control
  SET settled_through_game_day = p_completed_game_day,
      updated_at = CURRENT_TIMESTAMP
  WHERE id = 'WORLD';

  RETURN p_completed_game_day;
END;
$$;
