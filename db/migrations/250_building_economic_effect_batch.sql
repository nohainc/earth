-- Building Economy V2 Plan 17: compile and post one auditable economic batch.

CREATE TABLE IF NOT EXISTS building_economic_batches (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  game_day BIGINT NOT NULL,
  shard SMALLINT NOT NULL CHECK (shard BETWEEN 0 AND 63),
  status TEXT NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'WAITING_FUNDS', 'POSTED', 'FAILED')),
  correlation_id TEXT NOT NULL UNIQUE,
  rules_version TEXT NOT NULL DEFAULT 'building-economy-v2',
  economic_transaction_id BIGINT REFERENCES economic_transactions(id),
  effect_count INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  posted_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS building_economic_effects (
  batch_id BIGINT NOT NULL REFERENCES building_economic_batches(id) ON DELETE CASCADE,
  account_id BIGINT NOT NULL REFERENCES economic_accounts(id),
  delta BIGINT NOT NULL CHECK (delta <> 0),
  reason_code TEXT NOT NULL,
  source_id TEXT NOT NULL,
  detail JSONB NOT NULL DEFAULT '{}'::JSONB,
  PRIMARY KEY (batch_id, account_id, reason_code, source_id)
);
CREATE INDEX IF NOT EXISTS building_economic_effects_account_idx
  ON building_economic_effects (account_id, batch_id);

CREATE OR REPLACE FUNCTION earth_post_building_economic_batch(
  p_game_day BIGINT, p_shard SMALLINT
)
RETURNS TABLE(batch_id BIGINT, economic_transaction_id BIGINT, status TEXT, effect_count INTEGER)
LANGUAGE plpgsql
AS $$
DECLARE
  v_correlation TEXT := format('building-settlement:%s:%s', p_game_day, p_shard);
  v_batch_id BIGINT;
  v_effects JSONB;
  v_posting RECORD;
  v_total INTEGER;
BEGIN
  IF p_game_day < 0 OR p_shard < 0 OR p_shard > 63 THEN
    RAISE EXCEPTION 'Invalid building economic batch day or shard';
  END IF;

  INSERT INTO building_economic_batches (game_day, shard, correlation_id)
  VALUES (p_game_day, p_shard, v_correlation)
  ON CONFLICT (correlation_id) DO NOTHING;

  SELECT b.id, b.status, b.economic_transaction_id
  INTO v_batch_id, status, economic_transaction_id
  FROM building_economic_batches b
  WHERE b.correlation_id = v_correlation
  FOR UPDATE;
  IF status = 'POSTED' THEN
    SELECT b.effect_count INTO effect_count FROM building_economic_batches b WHERE b.id = v_batch_id;
    RETURN NEXT;
    RETURN;
  END IF;

  DELETE FROM building_economic_effects WHERE building_economic_effects.batch_id = v_batch_id;

  -- Physical effects retain their building/source identity. Each logical flow
  -- has both sides in the compiled relation.
  INSERT INTO building_economic_effects (batch_id, account_id, delta, reason_code, source_id, detail)
  SELECT v_batch_id, e.account_id, e.delta, 'BUILDING_' || e.effect_kind, e.source_id,
    jsonb_build_object('asset_id', e.asset_id, 'counterparty_account_id', e.counterparty_account_id)
  FROM building_settlement_physical_effects e
  WHERE e.game_day = p_game_day
    AND earth_settlement_shard(e.owner_economic_id, 64) = p_shard
  UNION ALL
  SELECT v_batch_id, e.counterparty_account_id, -e.delta, 'BUILDING_' || e.effect_kind, e.source_id,
    jsonb_build_object('asset_id', e.asset_id, 'account_id', e.account_id)
  FROM building_settlement_physical_effects e
  WHERE e.game_day = p_game_day
    AND earth_settlement_shard(e.owner_economic_id, 64) = p_shard;

  -- Explicit operating costs are transfers, never an implicit sink.
  INSERT INTO building_economic_effects (batch_id, account_id, delta, reason_code, source_id)
  SELECT v_batch_id, payer.id, -p.operating_cost_units, 'BUILDING_OPERATING_COST', p.building_id
  FROM building_settlement_plans p
  JOIN economic_accounts payer ON payer.owner_economic_id = p.owner_economic_id
    AND payer.asset_id = 1 AND payer.is_default_settlement AND payer.status = 'active'
  WHERE p.game_day = p_game_day AND p.shard = p_shard
    AND p.operating_cost_units > 0 AND p.operating_cost_recipient_account_id IS NOT NULL
  UNION ALL
  SELECT v_batch_id, p.operating_cost_recipient_account_id, p.operating_cost_units,
    'BUILDING_OPERATING_REVENUE', p.building_id
  FROM building_settlement_plans p
  WHERE p.game_day = p_game_day AND p.shard = p_shard
    AND p.operating_cost_units > 0 AND p.operating_cost_recipient_account_id IS NOT NULL;

  -- Repairs consume only the resources represented by the repair points.
  INSERT INTO building_economic_effects (batch_id, account_id, delta, reason_code, source_id, detail)
  SELECT v_batch_id, owner_account.id, -units.repair_units, 'BUILDING_REPAIR_COST', p.building_id,
    jsonb_build_object('asset_id', asset.id)
  FROM building_settlement_plans p
  JOIN buildings b ON b.id = p.building_id
  LEFT JOIN building_catalog c ON c.id = COALESCE(b.catalog_id, b.building_type || '-t' || COALESCE(b.tier, 1))
  JOIN economic_assets asset ON asset.code = CASE WHEN b.ownership_class = 'civic' THEN 'MATERIAL' ELSE 'COMPONENTS' END
  JOIN economic_accounts owner_account ON owner_account.owner_economic_id = p.owner_economic_id
    AND owner_account.asset_id = asset.id AND owner_account.account_type = 2 AND owner_account.status = 'active'
  CROSS JOIN LATERAL (SELECT ROUND(p.repair_points * CASE WHEN b.ownership_class = 'civic' THEN c.repair_materials_per_point ELSE c.repair_components_per_point END * asset.scale)::BIGINT AS repair_units) units
  WHERE p.game_day = p_game_day AND p.shard = p_shard AND units.repair_units > 0
  UNION ALL
  SELECT v_batch_id, sink.id, units.repair_units, 'BUILDING_REPAIR_CONSUMPTION', p.building_id,
    jsonb_build_object('asset_id', asset.id)
  FROM building_settlement_plans p
  JOIN buildings b ON b.id = p.building_id
  LEFT JOIN building_catalog c ON c.id = COALESCE(b.catalog_id, b.building_type || '-t' || COALESCE(b.tier, 1))
  JOIN economic_assets asset ON asset.code = CASE WHEN b.ownership_class = 'civic' THEN 'MATERIAL' ELSE 'COMPONENTS' END
  JOIN owner_registry system_owner ON system_owner.id = 'SYSTEM'
  JOIN economic_accounts sink ON sink.owner_economic_id = system_owner.economic_id
    AND sink.asset_id = asset.id AND sink.account_type = 8 AND sink.status = 'active'
  CROSS JOIN LATERAL (SELECT ROUND(p.repair_points * CASE WHEN b.ownership_class = 'civic' THEN c.repair_materials_per_point ELSE c.repair_components_per_point END * asset.scale)::BIGINT AS repair_units) units
  WHERE p.game_day = p_game_day AND p.shard = p_shard AND units.repair_units > 0;

  -- Private service payments are included only when each payer can fund its
  -- complete group bill. This keeps affordability independent of row order.
  WITH candidates AS (
    SELECT a.id allocation_id, a.delivered_units * a.price_units amount,
      d.payer_economic_id, payer.id payer_account_id, operator.id operator_account_id
    FROM service_allocations a
    JOIN service_demand d ON d.id = a.demand_id
    JOIN building_settlement_plans p ON p.building_id = a.building_id AND p.game_day = a.game_day
    JOIN economic_accounts payer ON payer.owner_economic_id = d.payer_economic_id
      AND payer.asset_id = 1 AND payer.account_type = 1 AND payer.is_default_settlement AND payer.status = 'active'
    JOIN economic_accounts operator ON operator.owner_economic_id = p.owner_economic_id
      AND operator.asset_id = 1 AND operator.is_default_settlement AND operator.status = 'active'
    WHERE a.game_day = p_game_day AND a.status = 'RESOLVED'
      AND p.shard = p_shard AND p.service_mode = 'PRIVATE'
  ), totals AS (
    SELECT payer_economic_id, payer_account_id, SUM(amount)::BIGINT total_amount
    FROM candidates GROUP BY payer_economic_id, payer_account_id
  ), funded AS (
    SELECT c.* FROM candidates c JOIN totals t USING (payer_economic_id, payer_account_id)
    JOIN economic_accounts pa ON pa.id = t.payer_account_id WHERE pa.balance >= t.total_amount
  )
  INSERT INTO building_economic_effects (batch_id, account_id, delta, reason_code, source_id)
  SELECT v_batch_id, payer_account_id, -amount, 'BUILDING_SERVICE_PAYMENT', allocation_id::TEXT FROM funded
  UNION ALL
  SELECT v_batch_id, operator_account_id, amount, 'BUILDING_SERVICE_REVENUE', allocation_id::TEXT FROM funded;

  SELECT COUNT(*)::INTEGER INTO v_total FROM building_economic_effects WHERE building_economic_effects.batch_id = v_batch_id;
  effect_count := v_total;
  IF v_total = 0 THEN
    status := 'WAITING_FUNDS';
    UPDATE building_economic_batches SET status = 'WAITING_FUNDS', effect_count = 0 WHERE id = v_batch_id;
    RETURN NEXT;
    RETURN;
  END IF;

  SELECT jsonb_agg(jsonb_build_object('account_id', account_id, 'delta', delta, 'reason_code', reason_code) ORDER BY account_id, reason_code, source_id)
  INTO v_effects
  FROM (
    SELECT account_id, SUM(delta)::BIGINT delta, MIN(reason_code) reason_code, MIN(source_id) source_id
    FROM building_economic_effects WHERE building_economic_effects.batch_id = v_batch_id
    GROUP BY account_id
  ) grouped;
  IF (SELECT COALESCE(SUM(delta), 0) FROM building_economic_effects WHERE building_economic_effects.batch_id = v_batch_id) <> 0 THEN
    RAISE EXCEPTION 'Building economic batch % is unbalanced', v_correlation;
  END IF;

  SELECT * INTO v_posting FROM earth_post_settlement_batch(
    v_correlation, p_game_day, 1439, 'building_settlement', p_shard::TEXT,
    'building-economy-v2', v_effects
  );
  UPDATE building_economic_batches SET status = 'POSTED', economic_transaction_id = v_posting.transaction_id,
    effect_count = v_total, posted_at = CURRENT_TIMESTAMP WHERE id = v_batch_id;
  UPDATE service_allocations SET status = 'POSTED'
  WHERE id IN (SELECT source_id::BIGINT FROM building_economic_effects
    WHERE building_economic_effects.batch_id = v_batch_id AND reason_code = 'BUILDING_SERVICE_PAYMENT');
  batch_id := v_batch_id;
  economic_transaction_id := v_posting.transaction_id;
  status := 'POSTED';
  RETURN NEXT;
END;
$$;
