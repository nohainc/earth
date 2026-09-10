-- Economy V2 Plan 9: phase-scoped effect netting.
-- Never net effects across phases: gameplay ordering and debit resolution are
-- part of the economic semantics.

CREATE SEQUENCE IF NOT EXISTS settlement_effect_nets_id_seq
  AS BIGINT START WITH 1 INCREMENT BY 1 MINVALUE 1;

CREATE UNLOGGED TABLE IF NOT EXISTS settlement_effect_nets (
  id BIGINT PRIMARY KEY DEFAULT nextval('settlement_effect_nets_id_seq'),
  game_day BIGINT NOT NULL CHECK (game_day >= 0),
  phase TEXT NOT NULL CHECK (length(btrim(phase)) > 0),
  shard SMALLINT NOT NULL CHECK (shard BETWEEN 0 AND 63),
  owner_economic_id BIGINT NOT NULL REFERENCES owner_registry(economic_id),
  account_id BIGINT NOT NULL REFERENCES economic_accounts(id),
  asset_id SMALLINT NOT NULL REFERENCES economic_assets(id),
  delta BIGINT NOT NULL CHECK (delta <> 0),
  reason_code TEXT NOT NULL,
  source_id TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (game_day, phase, shard, account_id, asset_id)
);

CREATE INDEX IF NOT EXISTS settlement_effect_nets_batch_idx
  ON settlement_effect_nets (game_day, phase, shard, account_id);

CREATE OR REPLACE FUNCTION earth_net_settlement_effects(
  p_game_day BIGINT,
  p_phase TEXT,
  p_shard SMALLINT
)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE
  v_count BIGINT;
BEGIN
  IF p_phase IS NULL OR length(btrim(p_phase)) = 0 THEN
    RAISE EXCEPTION 'Settlement net phase is required';
  END IF;
  IF p_shard < 0 OR p_shard > 63 THEN
    RAISE EXCEPTION 'Settlement net shard must be between 0 and 63';
  END IF;

  -- The caller must have resolved phase-specific debit priority and partial
  -- payment rules before effects reach this netting step.
  DELETE FROM settlement_effect_nets
  WHERE game_day = p_game_day AND phase = p_phase AND shard = p_shard;

  INSERT INTO settlement_effect_nets (
    game_day, phase, shard, owner_economic_id, account_id, asset_id,
    delta, reason_code, source_id
  )
  SELECT e.game_day,
         e.phase,
         e.shard,
         a.owner_economic_id,
         e.account_id,
         e.asset_id,
         SUM(e.delta)::BIGINT,
         'phase_net:' || e.phase,
         'settlement:' || e.game_day || ':' || e.phase || ':' || e.shard
  FROM settlement_effects e
  JOIN economic_accounts a ON a.id = e.account_id
  WHERE e.game_day = p_game_day
    AND e.phase = p_phase
    AND e.shard = p_shard
  GROUP BY e.game_day, e.phase, e.shard, a.owner_economic_id, e.account_id, e.asset_id
  HAVING SUM(e.delta) <> 0;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;
