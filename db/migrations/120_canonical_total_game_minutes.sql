-- Canonical clock contract: the database returns one absolute game-minute value.
-- Day and minute-of-day are presentation/settlement projections, not clock state.

DROP FUNCTION IF EXISTS earth_get_current_game_time();

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
  v_offset_days BIGINT;
  v_elapsed_seconds NUMERIC;
BEGIN
  SELECT
    COALESCE(w.genesis_at, '2026-01-01T00:00:00Z'::TIMESTAMPTZ),
    COALESCE(w.simulated_day_offset, 0)
  INTO v_genesis, v_offset_days
  FROM world_state w
  WHERE w.id = 'WORLD';

  IF NOT FOUND THEN
    v_genesis := '2026-01-01T00:00:00Z'::TIMESTAMPTZ;
    v_offset_days := 0;
  END IF;

  v_elapsed_seconds := GREATEST(0, EXTRACT(EPOCH FROM (NOW() - v_genesis)));
  RETURN QUERY SELECT
    FLOOR(v_elapsed_seconds)::BIGINT + (v_offset_days * 1440),
    v_genesis,
    v_elapsed_seconds;
END;
$$;

CREATE OR REPLACE FUNCTION earth_game_day_from_total_minutes(p_total_game_minutes BIGINT)
RETURNS BIGINT
LANGUAGE SQL
IMMUTABLE
AS $$ SELECT 1 + FLOOR(GREATEST(0, p_total_game_minutes) / 1440.0)::BIGINT $$;

CREATE OR REPLACE FUNCTION earth_minute_of_day_from_total_minutes(p_total_game_minutes BIGINT)
RETURNS INTEGER
LANGUAGE SQL
IMMUTABLE
AS $$ SELECT MOD(GREATEST(0, p_total_game_minutes), 1440)::INTEGER $$;

-- Rebuild active PL/pgSQL functions which still persist day/minute columns in
-- their ledger records. Their public APIs remain unchanged; they now derive
-- those audit dimensions from the canonical absolute minute.
DO $$
DECLARE
  v_function RECORD;
  v_definition TEXT;
BEGIN
  FOR v_function IN
    SELECT p.oid
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.prosrc LIKE '%earth_get_current_game_time%'
      AND p.proname <> 'earth_get_current_game_time'
  LOOP
    v_definition := pg_get_functiondef(v_function.oid);
    v_definition := replace(v_definition,
      'SELECT t.game_day, t.game_minute INTO v_game_day, v_game_minute FROM earth_get_current_game_time() t;',
      'SELECT earth_game_day_from_total_minutes(t.total_game_minutes), earth_minute_of_day_from_total_minutes(t.total_game_minutes) INTO v_game_day, v_game_minute FROM earth_get_current_game_time() t;');
    v_definition := replace(v_definition,
      'SELECT t.game_day INTO v_target_day FROM earth_get_current_game_time() t;',
      'SELECT earth_game_day_from_total_minutes(t.total_game_minutes) INTO v_target_day FROM earth_get_current_game_time() t;');
    v_definition := replace(v_definition,
      'v_time.game_day',
      'earth_game_day_from_total_minutes(v_time.total_game_minutes)');
    v_definition := replace(v_definition,
      'v_time.game_minute',
      'earth_minute_of_day_from_total_minutes(v_time.total_game_minutes)');
    EXECUTE v_definition;
  END LOOP;
END;
$$;
