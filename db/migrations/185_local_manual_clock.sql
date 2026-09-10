-- Plan 5: deterministic local/manual clock. Production remains realtime.

ALTER TABLE world_state
  ADD COLUMN IF NOT EXISTS clock_mode TEXT NOT NULL DEFAULT 'realtime'
    CHECK (clock_mode IN ('realtime', 'manual', 'paused')),
  ADD COLUMN IF NOT EXISTS manual_total_game_minutes BIGINT NOT NULL DEFAULT 0
    CHECK (manual_total_game_minutes >= 0);

CREATE OR REPLACE FUNCTION earth_get_current_game_time()
RETURNS TABLE (total_game_minutes BIGINT, genesis_at TIMESTAMPTZ, elapsed_real_seconds NUMERIC)
LANGUAGE sql STABLE
AS $$
  SELECT
    CASE WHEN w.clock_mode IN ('manual', 'paused') THEN w.manual_total_game_minutes
         ELSE FLOOR(GREATEST(0, EXTRACT(EPOCH FROM (NOW() - COALESCE(w.genesis_at, '2026-01-01T00:00:00Z'::timestamptz)))))::BIGINT END,
    COALESCE(w.genesis_at, '2026-01-01T00:00:00Z'::timestamptz),
    CASE WHEN w.clock_mode IN ('manual', 'paused') THEN w.manual_total_game_minutes * 60
         ELSE GREATEST(0, EXTRACT(EPOCH FROM (NOW() - COALESCE(w.genesis_at, '2026-01-01T00:00:00Z'::timestamptz)))) END
  FROM world_state w
  WHERE w.id = 'WORLD'
  UNION ALL
  SELECT 0::BIGINT, '2026-01-01T00:00:00Z'::timestamptz, 0::NUMERIC
  WHERE NOT EXISTS (SELECT 1 FROM world_state WHERE id = 'WORLD');
$$;

CREATE OR REPLACE FUNCTION earth_local_set_clock_mode(p_mode TEXT)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
  IF p_mode NOT IN ('realtime', 'manual', 'paused') THEN RAISE EXCEPTION 'Invalid local clock mode'; END IF;
  UPDATE world_state
     SET manual_total_game_minutes = CASE
       WHEN p_mode IN ('manual', 'paused') AND clock_mode = 'realtime'
         THEN FLOOR(GREATEST(0, EXTRACT(EPOCH FROM (NOW() - COALESCE(genesis_at, '2026-01-01T00:00:00Z'::timestamptz)))))::BIGINT
       ELSE manual_total_game_minutes
     END,
     clock_mode = p_mode
   WHERE id = 'WORLD';
END;
$$;

CREATE OR REPLACE FUNCTION earth_local_advance_minutes(p_minutes BIGINT)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE next_total BIGINT;
BEGIN
  IF p_minutes < 0 THEN RAISE EXCEPTION 'Local clock cannot move backwards'; END IF;
  UPDATE world_state
     SET clock_mode = 'manual', manual_total_game_minutes = manual_total_game_minutes + p_minutes
   WHERE id = 'WORLD'
   RETURNING manual_total_game_minutes INTO next_total;
  IF next_total IS NULL THEN RAISE EXCEPTION 'WORLD state is required'; END IF;
  RETURN next_total;
END;
$$;
