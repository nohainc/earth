-- Stored Function: earth_absolute_game_minute
--
-- Calculates contiguous absolute game minutes from 1-indexed game day and minute (0-1439).
CREATE OR REPLACE FUNCTION earth_absolute_game_minute(p_game_day BIGINT, p_game_minute INTEGER)
RETURNS BIGINT LANGUAGE SQL IMMUTABLE STRICT AS $$
  SELECT (GREATEST(1, p_game_day) - 1) * 1440 + GREATEST(0, LEAST(1439, p_game_minute));
$$;
