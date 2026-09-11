-- Building Economy V2 Plan 15: atomic customer-to-operator service payments.

CREATE TABLE IF NOT EXISTS service_payment_batches (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  game_day BIGINT NOT NULL,
  city_id TEXT NOT NULL REFERENCES cities(id),
  service_type TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'PENDING'
    CHECK (status IN ('PENDING', 'WAITING_FUNDS', 'COMPLETED', 'FAILED')),
  rules_version TEXT NOT NULL DEFAULT 'building-service-v2',
  service_settlement_id TEXT NOT NULL UNIQUE,
  correlation_id TEXT NOT NULL UNIQUE,
  economic_transaction_id BIGINT REFERENCES economic_transactions(id),
  consumer_units BIGINT NOT NULL DEFAULT 0,
  operator_units BIGINT NOT NULL DEFAULT 0,
  allocation_count INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  completed_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS service_payment_effects (
  service_settlement_id TEXT NOT NULL REFERENCES service_payment_batches(service_settlement_id) ON DELETE CASCADE,
  allocation_id BIGINT NOT NULL REFERENCES service_allocations(id) ON DELETE CASCADE,
  account_id BIGINT NOT NULL REFERENCES economic_accounts(id),
  delta BIGINT NOT NULL CHECK (delta <> 0),
  role TEXT NOT NULL CHECK (role IN ('CONSUMER', 'OPERATOR')),
  PRIMARY KEY (service_settlement_id, allocation_id, account_id)
);
CREATE INDEX IF NOT EXISTS service_payment_effects_account_idx
  ON service_payment_effects (account_id, service_settlement_id);

CREATE OR REPLACE FUNCTION earth_post_service_payment_batch(
  p_game_day BIGINT,
  p_city_id TEXT,
  p_service_type TEXT
)
RETURNS TABLE(service_settlement_id TEXT, economic_transaction_id BIGINT, status TEXT, allocation_count INTEGER)
LANGUAGE plpgsql
AS $$
DECLARE
  v_settlement_id TEXT := format('service-settlement:%s:%s:%s', p_game_day, p_city_id, p_service_type);
  v_correlation_id TEXT := v_settlement_id;
  v_batch_id BIGINT;
  v_effects JSONB;
  v_posting RECORD;
  v_count INTEGER;
  v_total BIGINT;
BEGIN
  INSERT INTO service_payment_batches (
    game_day, city_id, service_type, service_settlement_id, correlation_id
  ) VALUES (p_game_day, p_city_id, p_service_type, v_settlement_id, v_correlation_id)
  ON CONFLICT (service_settlement_id) DO NOTHING
  RETURNING id INTO v_batch_id;

  SELECT b.id, b.status, b.economic_transaction_id INTO v_batch_id, status, economic_transaction_id
  FROM service_payment_batches b
  WHERE b.service_settlement_id = v_settlement_id
  FOR UPDATE;
  service_settlement_id := v_settlement_id;
  allocation_count := 0;
  IF status = 'COMPLETED' THEN
    SELECT COUNT(*)::INTEGER INTO allocation_count FROM service_allocations a
    JOIN service_demand d ON d.id = a.demand_id
    WHERE a.game_day = p_game_day AND a.status = 'POSTED'
      AND d.city_id = p_city_id AND d.service_type = p_service_type;
    RETURN NEXT;
    RETURN;
  END IF;

  DELETE FROM service_payment_effects WHERE service_settlement_id = v_settlement_id;

  -- A payer is admitted only when its total service bill for this group fits
  -- in its wallet. This prevents the batch from relying on row order.
  WITH candidates AS (
    SELECT a.id AS allocation_id, a.delivered_units * a.price_units AS amount,
      d.payer_economic_id, provider.owner_economic_id,
      payer_account.id AS payer_account_id, operator_account.id AS operator_account_id
    FROM service_allocations a
    JOIN service_demand d ON d.id = a.demand_id
    JOIN building_settlement_plans provider_plan
      ON provider_plan.building_id = a.building_id AND provider_plan.game_day = a.game_day
    JOIN owner_registry provider ON provider.economic_id = provider_plan.owner_economic_id
    JOIN economic_accounts payer_account
      ON payer_account.owner_economic_id = d.payer_economic_id
     AND payer_account.asset_id = 1 AND payer_account.account_type = 1
     AND payer_account.is_default_settlement AND payer_account.status = 'active'
    JOIN economic_accounts operator_account
      ON operator_account.owner_economic_id = provider_plan.owner_economic_id
     AND operator_account.asset_id = 1 AND operator_account.is_default_settlement
     AND operator_account.status = 'active'
    WHERE a.game_day = p_game_day AND a.status = 'RESOLVED'
      AND d.city_id = p_city_id AND d.service_type = p_service_type
  ), payer_totals AS (
    SELECT payer_economic_id, payer_account_id, SUM(amount)::BIGINT AS total_amount
    FROM candidates GROUP BY payer_economic_id, payer_account_id
  ), funded AS (
    SELECT c.* FROM candidates c JOIN payer_totals t USING (payer_economic_id, payer_account_id)
    JOIN economic_accounts pa ON pa.id = t.payer_account_id
    WHERE pa.balance >= t.total_amount
  )
  INSERT INTO service_payment_effects (service_settlement_id, allocation_id, account_id, delta, role)
  SELECT v_settlement_id, allocation_id, payer_account_id, -amount, 'CONSUMER' FROM funded
  UNION ALL
  SELECT v_settlement_id, allocation_id, operator_account_id, amount, 'OPERATOR' FROM funded;

  SELECT COUNT(DISTINCT allocation_id)::INTEGER, COALESCE(SUM(ABS(delta)) FILTER (WHERE role = 'CONSUMER'), 0)::BIGINT
  INTO v_count, v_total
  FROM service_payment_effects WHERE service_settlement_id = v_settlement_id;
  allocation_count := COALESCE(v_count, 0);
  IF allocation_count = 0 THEN
    UPDATE service_payment_batches SET status = 'WAITING_FUNDS' WHERE id = v_batch_id;
    status := 'WAITING_FUNDS';
    RETURN NEXT;
    RETURN;
  END IF;

  SELECT jsonb_agg(jsonb_build_object('account_id', account_id, 'delta', delta, 'reason_code', 'SERVICE_PAYMENT') ORDER BY account_id)
  INTO v_effects
  FROM (
    SELECT account_id, SUM(delta)::BIGINT AS delta
    FROM service_payment_effects WHERE service_settlement_id = v_settlement_id
    GROUP BY account_id
  ) grouped;

  IF COALESCE((SELECT SUM(delta) FROM service_payment_effects WHERE service_settlement_id = v_settlement_id), 0) <> 0 THEN
    RAISE EXCEPTION 'Service payment batch % is unbalanced', v_settlement_id;
  END IF;

  SELECT * INTO v_posting FROM earth_post_settlement_batch(
    v_correlation_id, p_game_day, 1439, 'building_service', p_city_id,
    'building-service-v2', v_effects
  );

  UPDATE service_allocations a
  SET status = 'POSTED'
  WHERE a.id IN (
    SELECT DISTINCT allocation_id FROM service_payment_effects
    WHERE service_settlement_id = v_settlement_id
  );
  UPDATE service_payment_batches b
  SET status = 'COMPLETED', economic_transaction_id = v_posting.transaction_id,
      consumer_units = v_total, operator_units = v_total,
      allocation_count = v_count, completed_at = CURRENT_TIMESTAMP
  WHERE b.id = v_batch_id;

  economic_transaction_id := v_posting.transaction_id;
  status := 'COMPLETED';
  RETURN NEXT;
END;
$$;
