-- Stored Function: earth_get_current_game_time
--
-- Calculates one authoritative absolute game-minute value from real elapsed time
-- since genesis_at (1 real second = 1 game minute).
CREATE OR REPLACE FUNCTION earth_get_current_game_time()
RETURNS TABLE (
  total_game_minutes BIGINT,
  genesis_at TIMESTAMPTZ,
  elapsed_real_seconds NUMERIC
)
LANGUAGE plpgsql
AS $$
DECLARE
  v_genesis TIMESTAMPTZ;
  v_offset BIGINT;
  v_elapsed_sec NUMERIC;
  v_total_minute BIGINT;
BEGIN
  SELECT
    COALESCE(w.genesis_at, '2026-01-01T00:00:00Z'::TIMESTAMPTZ),
    COALESCE(w.simulated_day_offset, 0)
  INTO v_genesis, v_offset
  FROM world_state w
  WHERE w.id = 'WORLD';

  IF NOT FOUND THEN
    v_genesis := '2026-01-01T00:00:00Z'::TIMESTAMPTZ;
    v_offset := 0;
  END IF;

  v_elapsed_sec := GREATEST(0, EXTRACT(EPOCH FROM (NOW() - v_genesis)));
  -- 1 real second = 1 game minute; 1,440 real seconds (24 real minutes) = 1 game day
  v_total_minute := FLOOR(v_elapsed_sec)::BIGINT + (v_offset * 1440);

  RETURN QUERY SELECT v_total_minute, v_genesis, v_elapsed_sec;
END;
$$;
