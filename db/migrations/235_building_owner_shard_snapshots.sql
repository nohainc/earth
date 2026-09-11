-- Building Economy V2 Plan 2: materialize owner-level inputs per settlement
-- shard. All buildings for one economic owner are planned in one shard.

CREATE UNLOGGED TABLE IF NOT EXISTS building_settlement_owner_inputs (
  owner_economic_id BIGINT NOT NULL REFERENCES owner_registry(economic_id),
  game_day BIGINT NOT NULL CHECK (game_day >= 0),
  shard SMALLINT NOT NULL CHECK (shard BETWEEN 0 AND 63),
  available_units JSONB NOT NULL DEFAULT '{}'::JSONB,
  account_ids JSONB NOT NULL DEFAULT '{}'::JSONB,
  building_count INTEGER NOT NULL DEFAULT 0 CHECK (building_count >= 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (owner_economic_id, game_day)
);

CREATE INDEX IF NOT EXISTS building_settlement_owner_inputs_shard_idx
  ON building_settlement_owner_inputs (game_day, shard, owner_economic_id);

CREATE OR REPLACE FUNCTION earth_prepare_building_owner_shard(
  p_game_day BIGINT,
  p_shard SMALLINT
)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE
  v_count BIGINT;
BEGIN
  IF p_game_day < 0 THEN
    RAISE EXCEPTION 'Building settlement game day must be non-negative';
  END IF;
  IF p_shard < 0 OR p_shard > 63 THEN
    RAISE EXCEPTION 'Building settlement shard must be between 0 and 63';
  END IF;

  PERFORM earth_prepare_building_settlement(p_game_day, p_shard);

  INSERT INTO building_settlement_owner_inputs (
    owner_economic_id, game_day, shard, available_units, account_ids,
    building_count
  )
  SELECT owners.owner_economic_id,
    p_game_day,
    p_shard,
    COALESCE(balances.available_units, '{}'::JSONB),
    COALESCE(balances.account_ids, '{}'::JSONB),
    owners.building_count
  FROM (
    SELECT owner_economic_id, COUNT(*)::INTEGER AS building_count
    FROM building_settlement_plans
    WHERE game_day = p_game_day AND shard = p_shard
    GROUP BY owner_economic_id
  ) owners
  LEFT JOIN LATERAL (
    SELECT
      jsonb_object_agg(asset.code, asset_balance.total_units) AS available_units,
      jsonb_object_agg(asset.code, asset_balance.account_ids) AS account_ids
    FROM economic_assets asset
    LEFT JOIN LATERAL (
      SELECT COALESCE(SUM(a.balance), 0)::BIGINT AS total_units,
        COALESCE(jsonb_agg(a.id ORDER BY a.id) FILTER (WHERE a.id IS NOT NULL), '[]'::JSONB) AS account_ids
      FROM economic_accounts a
      WHERE a.owner_economic_id = owners.owner_economic_id
        AND a.asset_id = asset.id
        AND a.account_type IN (1, 2, 3, 4, 5, 6)
        AND a.status = 'active'
    ) asset_balance ON TRUE
  ) balances ON TRUE
  ON CONFLICT (owner_economic_id, game_day) DO UPDATE SET
    shard = EXCLUDED.shard,
    available_units = EXCLUDED.available_units,
    account_ids = EXCLUDED.account_ids,
    building_count = EXCLUDED.building_count,
    created_at = CURRENT_TIMESTAMP;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

COMMENT ON TABLE building_settlement_owner_inputs IS
  'Disposable owner-level Economy V2 input snapshot; one owner belongs to one settlement shard.';
