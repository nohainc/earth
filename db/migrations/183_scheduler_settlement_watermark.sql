-- Plan 3: expose the highest contiguous settled day as the scheduler watermark.

CREATE OR REPLACE FUNCTION earth_settlement_watermark(p_current_game_day BIGINT)
RETURNS BIGINT
LANGUAGE sql
STABLE
AS $$
  WITH expected AS (
    SELECT day
    FROM generate_series(1, GREATEST(0, p_current_game_day - 1)) AS day
  ), missing AS (
    SELECT expected.day
    FROM expected
    WHERE NOT EXISTS (
      SELECT 1
      FROM daily_settlement_runs r
      WHERE r.game_day = expected.day
        AND r.status IN ('completed', 'baseline')
    )
  )
  SELECT COALESCE((SELECT MIN(day) - 1 FROM missing), GREATEST(0, p_current_game_day - 1))::BIGINT;
$$;
