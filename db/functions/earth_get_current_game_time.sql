-- Stored Function: earth_get_current_game_time
--
-- Calculates the authoritative game day and minute based on real elapsed time
-- since genesis_at (24 real minutes = 1,440 real seconds = 1 game day/month cycle).
CREATE OR REPLACE FUNCTION earth_get_current_game_time()
RETURNS TABLE (
  game_day BIGINT,
  game_minute INTEGER,
  genesis_at TIMESTAMPTZ,
  elapsed_real_seconds NUMERIC
)
LANGUAGE plpgsql
AS $$
DECLARE
  v_genesis TIMESTAMPTZ;
  v_offset BIGINT;
  v_elapsed_sec NUMERIC;
  v_day BIGINT;
  v_minute INTEGER;
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
  v_day := 1 + FLOOR(v_elapsed_sec / 1440.0)::BIGINT + v_offset;
  v_minute := MOD(FLOOR(v_elapsed_sec)::BIGINT, 1440)::INTEGER;

  RETURN QUERY SELECT v_day, v_minute, v_genesis, v_elapsed_sec;
END;
$$;
