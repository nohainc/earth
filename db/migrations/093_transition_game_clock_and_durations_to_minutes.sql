-- Migration 093: Transition Game Clock, Durations, and Building Construction to Authoritative Game Minutes

-- 1. World State - Total Game Minutes
ALTER TABLE world_state ADD COLUMN IF NOT EXISTS total_game_minutes BIGINT NOT NULL DEFAULT 0;

-- 2. Building Catalog - Construction Minutes
ALTER TABLE building_catalog ADD COLUMN IF NOT EXISTS construction_minutes INTEGER NOT NULL DEFAULT 1440;
UPDATE building_catalog SET construction_minutes = COALESCE(construction_days, 1) * 1440 WHERE construction_minutes IS NULL OR construction_minutes = 1440;

-- 3. Buildings - Construction Start & Complete Minute
ALTER TABLE buildings ADD COLUMN IF NOT EXISTS construction_started_minute BIGINT;
ALTER TABLE buildings ADD COLUMN IF NOT EXISTS construction_complete_minute BIGINT;

UPDATE buildings SET
  construction_started_minute = COALESCE(construction_started_game_day * 1440, created_game_day * 1440, 0),
  construction_complete_minute = COALESCE(construction_complete_game_day * 1440, (COALESCE(construction_started_game_day, created_game_day, 0) + 1) * 1440)
WHERE construction_started_minute IS NULL;

-- 4. Update earth_get_current_game_time stored function
DROP FUNCTION IF EXISTS earth_get_current_game_time();

CREATE OR REPLACE FUNCTION earth_get_current_game_time()
RETURNS TABLE (
  total_game_minutes BIGINT,
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
  v_total_min BIGINT;
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
  -- 1 real second = 1 game minute; 1,440 real seconds (24 real minutes) = 1 game day (1440 game minutes)
  v_total_min := FLOOR(v_elapsed_sec)::BIGINT + (v_offset * 1440);
  v_day := 1 + FLOOR(v_total_min / 1440.0)::BIGINT;
  v_minute := MOD(v_total_min, 1440)::INTEGER;

  RETURN QUERY SELECT v_total_min, v_day, v_minute, v_genesis, v_elapsed_sec;
END;
$$;
