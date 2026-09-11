-- Building Economy V2 Plan 5: compile exact physical debits/credits.

ALTER TABLE building_settlement_journals
  ADD COLUMN IF NOT EXISTS consumed_units JSONB NOT NULL DEFAULT '{}'::JSONB;
ALTER TABLE building_settlement_journals
  ADD COLUMN IF NOT EXISTS produced_units JSONB NOT NULL DEFAULT '{}'::JSONB;

CREATE UNLOGGED TABLE IF NOT EXISTS building_settlement_physical_effects (
  building_id TEXT NOT NULL REFERENCES buildings(id) ON DELETE CASCADE,
  game_day BIGINT NOT NULL,
  owner_economic_id BIGINT NOT NULL REFERENCES owner_registry(economic_id),
  asset_id SMALLINT NOT NULL REFERENCES economic_assets(id),
  account_id BIGINT NOT NULL REFERENCES economic_accounts(id),
  counterparty_account_id BIGINT NOT NULL REFERENCES economic_accounts(id),
  delta BIGINT NOT NULL CHECK (delta <> 0),
  effect_kind TEXT NOT NULL CHECK (effect_kind IN ('CONSUMPTION', 'PRODUCTION')),
  source_id TEXT NOT NULL,
  PRIMARY KEY (building_id, game_day, asset_id, effect_kind)
);
CREATE INDEX IF NOT EXISTS building_settlement_physical_effects_day_idx
  ON building_settlement_physical_effects (game_day, owner_economic_id, asset_id, building_id);

CREATE OR REPLACE FUNCTION earth_compile_building_physical_effects(
  p_game_day BIGINT,
  p_shard SMALLINT
)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE v_count BIGINT;
BEGIN
  IF p_game_day < 0 OR p_shard < 0 OR p_shard > 63 THEN
    RAISE EXCEPTION 'Invalid building physical effect day or shard';
  END IF;

  DELETE FROM building_settlement_physical_effects
  WHERE game_day = p_game_day AND owner_economic_id IN (
    SELECT owner_economic_id FROM building_settlement_plans
    WHERE game_day = p_game_day AND shard = p_shard
  );

  WITH plan_values AS (
    SELECT p.building_id, p.game_day, p.owner_economic_id,
      v.kind, a.id AS asset_id,
      ROUND((amounts.amount)::NUMERIC * a.scale)::BIGINT AS units
    FROM building_settlement_plans p
    CROSS JOIN LATERAL (VALUES
      ('CONSUMPTION'::TEXT, p.consumption), ('PRODUCTION'::TEXT, p.production)
    ) v(kind, values)
    CROSS JOIN LATERAL jsonb_each_text(v.values) amounts(code, amount)
    JOIN economic_assets a ON a.code = amounts.code
    WHERE p.game_day = p_game_day AND p.shard = p_shard
      AND amounts.amount::NUMERIC > 0 AND a.id BETWEEN 2 AND 6
  ), accounts AS (
    SELECT x.*, owner_account.id AS owner_account_id,
      CASE WHEN x.kind = 'CONSUMPTION' THEN sink_account.id ELSE source_account.id END AS counterparty_id
    FROM plan_values x
    JOIN economic_accounts owner_account
      ON owner_account.owner_economic_id = x.owner_economic_id
     AND owner_account.asset_id = x.asset_id AND owner_account.account_type = 2
     AND owner_account.status = 'active'
    JOIN owner_registry system_owner ON system_owner.id = 'SYSTEM'
    LEFT JOIN economic_accounts sink_account
      ON sink_account.owner_economic_id = system_owner.economic_id
     AND sink_account.asset_id = x.asset_id AND sink_account.account_type = 8
     AND sink_account.status = 'active'
    LEFT JOIN economic_accounts source_account
      ON source_account.owner_economic_id = system_owner.economic_id
     AND source_account.asset_id = x.asset_id AND source_account.account_type = 7
     AND source_account.status = 'active'
  )
  INSERT INTO building_settlement_physical_effects (
    building_id, game_day, owner_economic_id, asset_id, account_id,
    counterparty_account_id, delta, effect_kind, source_id
  )
  SELECT building_id, game_day, owner_economic_id, asset_id, owner_account_id,
    counterparty_id, CASE WHEN kind = 'CONSUMPTION' THEN -units ELSE units END,
    kind, building_id
  FROM accounts
  WHERE counterparty_id IS NOT NULL AND units > 0
  ON CONFLICT (building_id, game_day, asset_id, effect_kind) DO UPDATE SET
    account_id = EXCLUDED.account_id,
    counterparty_account_id = EXCLUDED.counterparty_account_id,
    delta = EXCLUDED.delta,
    source_id = EXCLUDED.source_id;

  WITH journal_values AS (
    SELECT p.building_id, p.game_day,
      COALESCE((SELECT jsonb_object_agg(a.code, to_jsonb(e.units))
        FROM building_settlement_physical_effects e JOIN economic_assets a ON a.id = e.asset_id
        WHERE e.building_id = p.building_id AND e.game_day = p.game_day
          AND e.effect_kind = 'CONSUMPTION'), '{}'::JSONB) AS consumed,
      COALESCE((SELECT jsonb_object_agg(a.code, to_jsonb(e.units))
        FROM building_settlement_physical_effects e JOIN economic_assets a ON a.id = e.asset_id
        WHERE e.building_id = p.building_id AND e.game_day = p.game_day
          AND e.effect_kind = 'PRODUCTION'), '{}'::JSONB) AS produced
    FROM building_settlement_plans p
    WHERE p.game_day = p_game_day AND p.shard = p_shard
  )
  UPDATE building_settlement_journals j
  SET consumed_units = v.consumed, produced_units = v.produced
  FROM journal_values v
  WHERE j.building_id = v.building_id AND j.day = v.game_day;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

COMMENT ON TABLE building_settlement_physical_effects IS
  'Exact fixed-point physical building effects; later posting must use these quantities.';
