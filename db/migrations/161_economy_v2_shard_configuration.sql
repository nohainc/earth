-- Economy V2 Plan 12: persist shard configuration per settlement day and
-- reduce shared targets before phase posting.

ALTER TABLE daily_settlement_runs
  ADD COLUMN IF NOT EXISTS shard_count INTEGER NOT NULL DEFAULT 1
  CHECK (shard_count BETWEEN 1 AND 1024);

CREATE OR REPLACE FUNCTION earth_settlement_shard(
  p_owner_economic_id BIGINT,
  p_shard_count INTEGER
)
RETURNS SMALLINT
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
  IF p_owner_economic_id IS NULL OR p_shard_count IS NULL OR p_shard_count < 1 OR p_shard_count > 1024 THEN
    RAISE EXCEPTION 'Settlement shard mapping requires a valid owner ID and shard count';
  END IF;
  RETURN mod(p_owner_economic_id, p_shard_count)::SMALLINT;
END;
$$;

CREATE OR REPLACE FUNCTION earth_reduce_shared_settlement_effects(
  p_game_day BIGINT,
  p_phase TEXT,
  p_shard_count INTEGER
)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE
  v_count BIGINT;
BEGIN
  IF p_shard_count < 1 OR p_shard_count > 1024 THEN
    RAISE EXCEPTION 'Settlement shard count must be between 1 and 1024';
  END IF;

  -- Shared targets are reduced across all owner shards. Shard 0 is the
  -- single posting shard for the reduced target set; ordinary owner effects
  -- remain in their mapped shards.
  DELETE FROM settlement_effect_nets n
  USING economic_accounts a
  JOIN owner_registry o ON o.economic_id = a.owner_economic_id
  WHERE n.account_id = a.id
    AND n.game_day = p_game_day AND n.phase = p_phase
    AND o.owner_type IN ('city', 'corporation', 'system');

  INSERT INTO settlement_effect_nets (
    game_day, phase, shard, owner_economic_id, account_id, asset_id,
    delta, reason_code, source_id
  )
  SELECT e.game_day, e.phase, 0::SMALLINT, a.owner_economic_id, e.account_id,
         e.asset_id, SUM(e.delta)::BIGINT, 'global_reduce:' || e.phase,
         'global-reduce:' || e.game_day || ':' || e.phase
  FROM settlement_effects e
  JOIN economic_accounts a ON a.id = e.account_id
  JOIN owner_registry o ON o.economic_id = a.owner_economic_id
  WHERE e.game_day = p_game_day AND e.phase = p_phase
    AND o.owner_type IN ('city', 'corporation', 'system')
  GROUP BY e.game_day, e.phase, a.owner_economic_id, e.account_id, e.asset_id
  HAVING SUM(e.delta) <> 0;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;
