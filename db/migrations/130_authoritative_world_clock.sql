-- Migration: 130_authoritative_world_clock.sql
-- EARTH V5 Authoritative Clock & Settlement Architecture
--
-- 1. Canonical world epoch (genesis_at) in world_state with immutability guard.
-- 2. Authoritative PostgreSQL clock function derived from real-world elapsed time.
-- 3. Contiguous settlement cursor (settled_through_game_day) on daily_settlement_control.
-- 4. Atomic settlement cursor advance function and complete_settlement integration.

-- 1. Genesis epoch in world_state
ALTER TABLE world_state ADD COLUMN IF NOT EXISTS genesis_at TIMESTAMPTZ;

-- Backfill genesis_at for existing world_state row if needed
UPDATE world_state
SET genesis_at = CURRENT_TIMESTAMP - (((COALESCE(game_day, 1) - 1) * 1440 + COALESCE(game_minute, 0)) * INTERVAL '1 second')
WHERE id = 'WORLD' AND genesis_at IS NULL;

-- Ensure default WORLD row exists with immutable genesis_at
INSERT INTO world_state (id, game_day, game_minute, world_seed, status, genesis_at)
VALUES ('WORLD', 1, 0, 'earth_genesis', 'ACTIVE', CURRENT_TIMESTAMP)
ON CONFLICT (id) DO UPDATE
  SET genesis_at = EXCLUDED.genesis_at
  WHERE world_state.genesis_at IS NULL;

-- Immutability guard trigger for genesis_at
CREATE OR REPLACE FUNCTION earth_guard_world_genesis_immutability()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.genesis_at IS NOT NULL AND NEW.genesis_at IS DISTINCT FROM OLD.genesis_at THEN
    RAISE EXCEPTION 'world_state.genesis_at is immutable and cannot be changed';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_world_genesis_immutability ON world_state;
CREATE TRIGGER trg_world_genesis_immutability
BEFORE UPDATE OF genesis_at ON world_state
FOR EACH ROW EXECUTE FUNCTION earth_guard_world_genesis_immutability();

-- 2. Settlement cursor in daily_settlement_control
ALTER TABLE daily_settlement_control ADD COLUMN IF NOT EXISTS settled_through_game_day BIGINT NOT NULL DEFAULT 0;

-- Backfill contiguous settlement cursor
DO $$
DECLARE
  v_day BIGINT := 1;
  v_max_contiguous BIGINT := 0;
BEGIN
  WHILE EXISTS (SELECT 1 FROM daily_settlement_runs WHERE game_day = v_day AND status = 'completed') LOOP
    v_max_contiguous := v_day;
    v_day := v_day + 1;
  END LOOP;
  UPDATE daily_settlement_control
  SET settled_through_game_day = v_max_contiguous
  WHERE id = 'WORLD';
END;
$$;

-- 3. Canonical clock functions
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

CREATE OR REPLACE FUNCTION earth_game_day_from_total_minutes(p_total_minutes BIGINT)
RETURNS BIGINT LANGUAGE SQL IMMUTABLE STRICT AS $$
  SELECT FLOOR(GREATEST(0, p_total_minutes) / 1440)::BIGINT + 1;
$$;

CREATE OR REPLACE FUNCTION earth_absolute_game_minute(p_game_day BIGINT, p_game_minute INTEGER)
RETURNS BIGINT LANGUAGE SQL IMMUTABLE STRICT AS $$
  SELECT (GREATEST(1, p_game_day) - 1) * 1440 + GREATEST(0, LEAST(1439, p_game_minute));
$$;

-- 4. Contiguous settlement cursor advance & completion
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

CREATE OR REPLACE FUNCTION earth_complete_settlement_day(p_game_day BIGINT)
RETURNS BOOLEAN LANGUAGE plpgsql AS $$
DECLARE
  v_updated BOOLEAN;
  v_current_cursor BIGINT;
BEGIN
  UPDATE daily_settlement_runs
     SET status = 'completed', completed_at = CURRENT_TIMESTAMP,
         current_phase = NULL, lease_owner = NULL,
         lease_heartbeat_at = NULL, updated_at = CURRENT_TIMESTAMP
   WHERE game_day = p_game_day AND status = 'running'
     AND NOT EXISTS (SELECT 1 FROM daily_settlement_phase_runs WHERE game_day = p_game_day AND status <> 'completed');
  GET DIAGNOSTICS v_updated = ROW_COUNT;
  IF v_updated THEN
    SELECT settled_through_game_day INTO v_current_cursor
    FROM daily_settlement_control
    WHERE id = 'WORLD'
    FOR UPDATE;

    IF v_current_cursor IS NOT NULL AND p_game_day = v_current_cursor + 1 THEN
      PERFORM earth_advance_settlement_cursor(p_game_day);
    END IF;
    RETURN TRUE;
  END IF;
  RETURN FALSE;
END;
$$;
