-- Stored Function: earth_get_current_game_time
--
-- Calculates one authoritative absolute game-minute value from real elapsed time
-- since genesis_at (1 real second = 1 game minute).
CREATE OR REPLACE FUNCTION earth_get_current_game_time()
RETURNS TABLE (
  game_day BIGINT,
  game_minute INTEGER,
  total_game_minutes BIGINT,
  genesis_at TIMESTAMPTZ,
  server_now TIMESTAMPTZ,
  elapsed_real_seconds NUMERIC,
  real_seconds_per_game_minute INTEGER
)
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_genesis TIMESTAMPTZ;
  v_now TIMESTAMPTZ := CURRENT_TIMESTAMP;
  v_elapsed_sec NUMERIC;
  v_total_min BIGINT;
  v_game_day BIGINT;
  v_game_minute INTEGER;
BEGIN
  SELECT w.genesis_at INTO v_genesis
  FROM world_state w
  WHERE w.id = 'WORLD';

  IF v_genesis IS NULL THEN
    RAISE EXCEPTION 'world_state.genesis_at is not configured';
  END IF;

  v_elapsed_sec := GREATEST(0, EXTRACT(EPOCH FROM (v_now - v_genesis)));
  v_total_min := FLOOR(v_elapsed_sec)::BIGINT;
  v_game_day := FLOOR(v_total_min / 1440)::BIGINT + 1;
  v_game_minute := (v_total_min % 1440)::INTEGER;

  RETURN QUERY SELECT
    v_game_day,
    v_game_minute,
    v_total_min,
    v_genesis,
    v_now,
    v_elapsed_sec,
    1::INTEGER;
END;
$$;
