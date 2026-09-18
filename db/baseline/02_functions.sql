-- Final baseline database logic only. Compatibility transfer functions are excluded.

CREATE OR REPLACE FUNCTION earth_validate_economic_account_capability()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  v_owner_type TEXT;
  v_asset_kind TEXT;
BEGIN
  SELECT owner_type INTO v_owner_type
    FROM owner_registry
   WHERE economic_id = NEW.owner_economic_id;
  IF v_owner_type IS NULL THEN
    RAISE EXCEPTION 'economic account owner does not exist: %', NEW.owner_economic_id;
  END IF;

  SELECT asset_kind INTO v_asset_kind
    FROM economic_assets
   WHERE id = NEW.asset_id;
  IF v_asset_kind IS NULL THEN
    RAISE EXCEPTION 'economic account asset does not exist: %', NEW.asset_id;
  END IF;

  IF NOT EXISTS (
    SELECT 1
      FROM economic_account_policies p
     WHERE p.owner_type = v_owner_type
       AND p.account_type = NEW.account_type
       AND (p.allowed_asset_kind = v_asset_kind OR p.allowed_asset_kind = 'ANY')
  ) THEN
    RAISE EXCEPTION 'economic account capability denied: owner_type=%, account_type=%, asset_kind=%',
      v_owner_type, NEW.account_type, v_asset_kind;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER economic_accounts_capability_integrity
BEFORE INSERT OR UPDATE OF owner_economic_id, asset_id, account_type ON economic_accounts
FOR EACH ROW EXECUTE FUNCTION earth_validate_economic_account_capability();

CREATE OR REPLACE FUNCTION earth_validate_market_order_owner()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  v_owner_type TEXT;
  v_asset_kind TEXT;
BEGIN
  SELECT o.owner_type, a.asset_kind
    INTO v_owner_type, v_asset_kind
    FROM owner_registry o
    JOIN economic_assets a ON a.id = (SELECT asset_id FROM market_instruments WHERE id = NEW.instrument_id)
   WHERE o.economic_id = NEW.owner_economic_id;
  IF v_owner_type NOT IN ('HOUSE', 'CORPORATION') THEN
    RAISE EXCEPTION 'Market orders must be House or Corporation-owned';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER market_orders_house_owner_integrity
BEFORE INSERT OR UPDATE OF owner_economic_id, instrument_id ON market_orders
FOR EACH ROW EXECUTE FUNCTION earth_validate_market_order_owner();

CREATE OR REPLACE FUNCTION earth_provision_house_economy(p_economic_id TEXT)
RETURNS INTEGER LANGUAGE plpgsql AS $$
DECLARE
  v_owner_type TEXT;
  v_account_count INTEGER;
BEGIN
  SELECT owner_type INTO v_owner_type FROM owner_registry WHERE economic_id = p_economic_id;
  IF v_owner_type IS DISTINCT FROM 'HOUSE' THEN
    RAISE EXCEPTION 'House economy provisioning requires a HOUSE owner: %', p_economic_id;
  END IF;

  INSERT INTO economic_accounts(owner_economic_id, asset_id, account_type)
  SELECT p_economic_id, id, 'WALLET' FROM economic_assets WHERE asset_kind = 'CREDIT'
  ON CONFLICT (owner_economic_id, asset_id, account_type) DO NOTHING;
  INSERT INTO economic_accounts(owner_economic_id, asset_id, account_type)
  SELECT p_economic_id, id, 'INVENTORY' FROM economic_assets WHERE asset_kind = 'RESOURCE'
  ON CONFLICT (owner_economic_id, asset_id, account_type) DO NOTHING;

  SELECT COUNT(*) INTO v_account_count
    FROM economic_accounts
   WHERE owner_economic_id = p_economic_id
     AND ((account_type = 'WALLET' AND asset_id IN (SELECT id FROM economic_assets WHERE asset_kind = 'CREDIT'))
       OR (account_type = 'INVENTORY' AND asset_id IN (SELECT id FROM economic_assets WHERE asset_kind = 'RESOURCE')));
  RETURN v_account_count;
END;
$$;

CREATE OR REPLACE FUNCTION earth_provision_corporation_economy(p_economic_id TEXT)
RETURNS INTEGER LANGUAGE plpgsql AS $$
DECLARE
  v_owner_type TEXT;
  v_account_count INTEGER;
BEGIN
  SELECT owner_type INTO v_owner_type FROM owner_registry WHERE economic_id = p_economic_id;
  IF v_owner_type IS DISTINCT FROM 'CORPORATION' THEN
    RAISE EXCEPTION 'Corporation economy provisioning requires a CORPORATION owner: %', p_economic_id;
  END IF;

  -- CREDIT Accounts: TREASURY, OPERATIONS, RESERVE
  INSERT INTO economic_accounts(owner_economic_id, asset_id, account_type)
  SELECT p_economic_id, id, account_type
    FROM economic_assets
   CROSS JOIN (VALUES ('TREASURY'::TEXT), ('OPERATIONS'::TEXT), ('RESERVE'::TEXT)) types(account_type)
   WHERE asset_kind = 'CREDIT'
  ON CONFLICT (owner_economic_id, asset_id, account_type) DO NOTHING;

  -- RESOURCE Accounts: INVENTORY for all 5 resources
  INSERT INTO economic_accounts(owner_economic_id, asset_id, account_type)
  SELECT p_economic_id, id, 'INVENTORY'
    FROM economic_assets
   WHERE asset_kind = 'RESOURCE'
  ON CONFLICT (owner_economic_id, asset_id, account_type) DO NOTHING;

  -- MARKET_ESCROW Accounts for CREDIT and all 5 resources
  INSERT INTO economic_accounts(owner_economic_id, asset_id, account_type)
  SELECT p_economic_id, id, 'MARKET_ESCROW'
    FROM economic_assets
   WHERE asset_kind IN ('CREDIT', 'RESOURCE')
  ON CONFLICT (owner_economic_id, asset_id, account_type) DO NOTHING;

  SELECT COUNT(*) INTO v_account_count
    FROM economic_accounts
   WHERE owner_economic_id = p_economic_id
     AND (
       (account_type IN ('TREASURY', 'OPERATIONS', 'RESERVE') AND asset_id IN (SELECT id FROM economic_assets WHERE asset_kind = 'CREDIT'))
       OR (account_type = 'INVENTORY' AND asset_id IN (SELECT id FROM economic_assets WHERE asset_kind = 'RESOURCE'))
       OR (account_type = 'MARKET_ESCROW' AND asset_id IN (SELECT id FROM economic_assets WHERE asset_kind IN ('CREDIT', 'RESOURCE')))
     );
  RETURN v_account_count;
END;
$$;

CREATE OR REPLACE FUNCTION earth_provision_earth_economy(p_economic_id TEXT)
RETURNS INTEGER LANGUAGE plpgsql AS $$
DECLARE
  v_owner_type TEXT;
  v_account_count INTEGER;
BEGIN
  SELECT owner_type INTO v_owner_type FROM owner_registry WHERE economic_id = p_economic_id;
  IF v_owner_type IS DISTINCT FROM 'EARTH' THEN
    RAISE EXCEPTION 'EARTH economy provisioning requires an EARTH owner: %', p_economic_id;
  END IF;

  INSERT INTO economic_accounts(owner_economic_id, asset_id, account_type)
  SELECT p_economic_id, id, account_type
    FROM economic_assets
   CROSS JOIN (VALUES ('TREASURY'::TEXT), ('OPERATIONS'::TEXT), ('RESERVE'::TEXT)) types(account_type)
   WHERE asset_kind = 'CREDIT'
  ON CONFLICT (owner_economic_id, asset_id, account_type) DO NOTHING;

  SELECT COUNT(*) INTO v_account_count
    FROM economic_accounts
   WHERE owner_economic_id = p_economic_id AND account_type IN ('TREASURY', 'OPERATIONS', 'RESERVE')
     AND asset_id IN (SELECT id FROM economic_assets WHERE asset_kind = 'CREDIT');
  RETURN v_account_count;
END;
$$;

CREATE OR REPLACE FUNCTION earth_provision_bank_economy(p_economic_id TEXT)
RETURNS INTEGER LANGUAGE plpgsql AS $$
DECLARE
  v_owner_type TEXT;
  v_account_count INTEGER;
BEGIN
  SELECT owner_type INTO v_owner_type FROM owner_registry WHERE economic_id = p_economic_id;
  IF v_owner_type IS DISTINCT FROM 'BANK' THEN
    RAISE EXCEPTION 'Bank economy provisioning requires a BANK owner: %', p_economic_id;
  END IF;

  INSERT INTO economic_accounts(owner_economic_id, asset_id, account_type)
  SELECT p_economic_id, id, account_type
    FROM economic_assets
   CROSS JOIN (VALUES ('OPERATIONS'::TEXT), ('RESERVE'::TEXT)) types(account_type)
   WHERE asset_kind = 'CREDIT'
  ON CONFLICT (owner_economic_id, asset_id, account_type) DO NOTHING;

  SELECT COUNT(*) INTO v_account_count
    FROM economic_accounts
   WHERE owner_economic_id = p_economic_id AND account_type IN ('OPERATIONS', 'RESERVE')
     AND asset_id IN (SELECT id FROM economic_assets WHERE asset_kind = 'CREDIT');
  RETURN v_account_count;
END;
$$;

CREATE OR REPLACE FUNCTION earth_settlement_watermark(p_game_day BIGINT)
RETURNS BIGINT LANGUAGE SQL STABLE AS $$
  SELECT COALESCE(MAX(game_day) FILTER (WHERE status IN ('completed', 'baseline')), 0)::BIGINT
    FROM daily_settlement_runs
   WHERE game_day <= p_game_day;
$$;

CREATE OR REPLACE FUNCTION earth_claim_settlement_day(
  p_game_day BIGINT, p_worker_id TEXT, p_lease_seconds INTEGER DEFAULT 30
) RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE v_id BIGINT;
BEGIN
  WITH candidate AS (
    SELECT current.id
      FROM daily_settlement_phase_runs current
     WHERE current.game_day = p_game_day
       AND (current.status = 'pending' OR (current.status = 'running' AND current.lease_expires_at < CURRENT_TIMESTAMP))
       AND NOT EXISTS (
         SELECT 1 FROM daily_settlement_phase_runs prior
          WHERE prior.game_day = current.game_day AND prior.phase_order < current.phase_order AND prior.status <> 'completed'
       )
     ORDER BY current.phase_order, current.shard FOR UPDATE SKIP LOCKED LIMIT 1
  )
  UPDATE daily_settlement_phase_runs work
     SET status = 'running', lease_owner = p_worker_id,
         lease_expires_at = CURRENT_TIMESTAMP + (p_lease_seconds::TEXT || ' seconds')::INTERVAL,
         attempt_count = work.attempt_count + 1,
         started_at = COALESCE(work.started_at, CURRENT_TIMESTAMP), updated_at = CURRENT_TIMESTAMP
    FROM candidate WHERE work.id = candidate.id
  RETURNING work.id INTO v_id;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION earth_heartbeat_settlement_day(
  p_game_day BIGINT, p_worker_id TEXT, p_phase_id TEXT
) RETURNS BOOLEAN LANGUAGE plpgsql AS $$
BEGIN
  UPDATE daily_settlement_runs
     SET current_phase = p_phase_id, lease_owner = p_worker_id,
         lease_heartbeat_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP
   WHERE game_day = p_game_day AND status = 'running';
  RETURN FOUND;
END;
$$;

CREATE OR REPLACE FUNCTION earth_complete_settlement_day(p_game_day BIGINT)
RETURNS BOOLEAN LANGUAGE plpgsql AS $$
BEGIN
  UPDATE daily_settlement_runs
     SET status = 'completed', completed_at = CURRENT_TIMESTAMP,
         current_phase = NULL, lease_owner = NULL,
         lease_heartbeat_at = NULL, updated_at = CURRENT_TIMESTAMP
   WHERE game_day = p_game_day AND status = 'running'
     AND NOT EXISTS (SELECT 1 FROM daily_settlement_phase_runs WHERE game_day = p_game_day AND status <> 'completed');
  RETURN FOUND;
END;
$$;

CREATE OR REPLACE FUNCTION earth_fail_settlement_day(
  p_work_id BIGINT, p_worker_id TEXT, p_error_message TEXT
) RETURNS BOOLEAN LANGUAGE plpgsql AS $$
BEGIN
  UPDATE daily_settlement_phase_runs
     SET status = CASE WHEN attempt_count >= 5 THEN 'failed' ELSE 'pending' END,
         lease_owner = NULL, lease_expires_at = NULL,
         error_message = LEFT(p_error_message, 1000), updated_at = CURRENT_TIMESTAMP
   WHERE id = p_work_id AND status = 'running' AND lease_owner = p_worker_id;
  RETURN FOUND;
END;
$$;

CREATE OR REPLACE FUNCTION earth_begin_economic_transaction(
  p_correlation_id TEXT, p_game_day BIGINT, p_game_minute INTEGER,
  p_transaction_kind TEXT, p_source_type TEXT, p_source_id TEXT,
  p_rules_version TEXT
) RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE v_id BIGINT;
BEGIN
  IF NULLIF(TRIM(p_transaction_kind), '') IS NULL OR NULLIF(TRIM(p_source_type), '') IS NULL THEN
    RAISE EXCEPTION 'economic transaction kind and source type are required';
  END IF;
  INSERT INTO economic_transactions(correlation_id, game_day, game_minute, transaction_kind, source_type, source_id, rules_version)
  VALUES (p_correlation_id, p_game_day, p_game_minute, p_transaction_kind, p_source_type, p_source_id, p_rules_version)
  ON CONFLICT (correlation_id) DO UPDATE SET correlation_id = EXCLUDED.correlation_id
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION earth_post_transaction(
  p_correlation_id TEXT, p_game_day BIGINT, p_game_minute INTEGER,
  p_transaction_kind TEXT, p_source_type TEXT, p_source_id TEXT,
  p_rules_version TEXT, p_entries JSONB
) RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE
  v_id BIGINT;
  v_entry JSONB;
  v_account_asset_id INTEGER;
  v_entry_asset_kind TEXT;
  v_semantic_class TEXT;
  v_asset_kind TEXT;
  v_asset_id INTEGER;
  v_asset_total BIGINT;
BEGIN
  v_id := earth_begin_economic_transaction(p_correlation_id, p_game_day, p_game_minute, p_transaction_kind, p_source_type, p_source_id, p_rules_version);
  IF EXISTS (SELECT 1 FROM economic_entries WHERE transaction_id = v_id) THEN RETURN v_id; END IF;
  IF COALESCE(jsonb_array_length(p_entries), 0) = 0 THEN RAISE EXCEPTION 'economic transaction must contain entries'; END IF;

  SELECT COALESCE(k.semantic_class, 'ASSET_TRANSFER'), COALESCE(k.asset_kind, 'ANY')
    INTO v_semantic_class, v_asset_kind
    FROM (SELECT 1) seed
    LEFT JOIN economic_transaction_kinds k ON k.code = p_transaction_kind;

  FOR v_entry IN SELECT value FROM jsonb_array_elements(p_entries) LOOP
    SELECT asset_id INTO v_account_asset_id FROM economic_accounts WHERE id = (v_entry->>'account_id')::BIGINT;
    IF v_account_asset_id IS NULL THEN
      RAISE EXCEPTION 'economic transaction account does not exist: %', v_entry->>'account_id';
    END IF;
    IF v_account_asset_id <> (v_entry->>'asset_id')::INTEGER THEN
      RAISE EXCEPTION 'economic entry asset does not match account asset: account=%, entry_asset=%', v_entry->>'account_id', v_entry->>'asset_id';
    END IF;
    SELECT asset_kind INTO v_entry_asset_kind FROM economic_assets WHERE id = (v_entry->>'asset_id')::INTEGER;
    IF v_entry_asset_kind IS NULL THEN
      RAISE EXCEPTION 'economic transaction asset does not exist: %', v_entry->>'asset_id';
    END IF;
    IF v_asset_kind <> 'ANY' AND v_entry_asset_kind <> v_asset_kind THEN
      RAISE EXCEPTION 'transaction semantic % only accepts % assets', v_semantic_class, v_asset_kind;
    END IF;
  END LOOP;

  FOR v_asset_id, v_asset_total IN
    SELECT (value->>'asset_id')::INTEGER, SUM((value->>'delta_units')::BIGINT)
      FROM jsonb_array_elements(p_entries)
     GROUP BY (value->>'asset_id')::INTEGER
  LOOP
    IF v_semantic_class = 'ASSET_TRANSFER' AND v_asset_total <> 0 THEN
      RAISE EXCEPTION 'asset transfer is not balanced for asset %', v_asset_id;
    ELSIF v_semantic_class = 'CREDIT_ISSUANCE' AND v_asset_total <= 0 THEN
      RAISE EXCEPTION 'CREDIT issuance must create a positive CREDIT amount for asset %', v_asset_id;
    ELSIF v_semantic_class = 'CREDIT_RETIREMENT' AND v_asset_total >= 0 THEN
      RAISE EXCEPTION 'CREDIT retirement must destroy a positive CREDIT amount for asset %', v_asset_id;
    ELSIF v_semantic_class IN ('RESOURCE_PRODUCTION', 'RESOURCE_CONSUMPTION') AND v_asset_total <> 0 THEN
      RAISE EXCEPTION 'resource production/consumption must balance against its dedicated system account for asset %', v_asset_id;
    END IF;
  END LOOP;

  IF v_semantic_class = 'CREDIT_ISSUANCE' AND EXISTS (
    SELECT 1 FROM jsonb_array_elements(p_entries) WHERE (value->>'delta_units')::BIGINT <= 0
  ) THEN
    RAISE EXCEPTION 'CREDIT issuance entries must all be positive';
  ELSIF v_semantic_class = 'CREDIT_RETIREMENT' AND EXISTS (
    SELECT 1 FROM jsonb_array_elements(p_entries) WHERE (value->>'delta_units')::BIGINT >= 0
  ) THEN
    RAISE EXCEPTION 'CREDIT retirement entries must all be negative';
  END IF;
  FOR v_entry IN SELECT value FROM jsonb_array_elements(p_entries) LOOP
    INSERT INTO economic_entries(transaction_id, account_id, delta_units, asset_id)
    VALUES (v_id, (v_entry->>'account_id')::BIGINT, (v_entry->>'delta_units')::BIGINT, (v_entry->>'asset_id')::INTEGER);
    UPDATE economic_accounts SET balance_units = balance_units + (v_entry->>'delta_units')::BIGINT WHERE id = (v_entry->>'account_id')::BIGINT;
    IF EXISTS (SELECT 1 FROM economic_accounts WHERE id = (v_entry->>'account_id')::BIGINT AND balance_units < 0 AND account_type <> 'SYSTEM_ACCOUNT') THEN RAISE EXCEPTION 'economic account would become negative'; END IF;
  END LOOP;
  RETURN v_id;
END;
$$;

-- Starter packages are the only player-facing issuance in the baseline. They
-- are explicit, auditable and idempotent; ordinary transfers remain balanced.
CREATE OR REPLACE FUNCTION earth_issue_starter_package(
  p_correlation_id TEXT, p_game_day BIGINT, p_house_economic_id TEXT,
  p_asset_id INTEGER, p_amount_units BIGINT
) RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE v_target_account BIGINT; v_source_account BIGINT; v_tx BIGINT;
BEGIN
  IF p_amount_units <= 0 THEN RAISE EXCEPTION 'starter issuance amount must be positive'; END IF;
  SELECT id INTO v_target_account FROM economic_accounts
   WHERE owner_economic_id = p_house_economic_id AND asset_id = p_asset_id
     AND account_type = CASE WHEN p_asset_id = 1 THEN 'WALLET' ELSE 'INVENTORY' END
     AND status = 'ACTIVE' FOR UPDATE;
  IF v_target_account IS NULL THEN RAISE EXCEPTION 'starter account is not provisioned'; END IF;
  IF p_asset_id = 1 THEN
    v_tx := earth_post_transaction(
      p_correlation_id, p_game_day, 0, 'CREDIT_ISSUANCE', 'SYSTEM_ISSUANCE',
      p_house_economic_id, 'starter-package-v1',
      jsonb_build_array(jsonb_build_object(
        'account_id', v_target_account, 'asset_id', p_asset_id, 'delta_units', p_amount_units
      ))
    );
  ELSE
    SELECT a.id INTO v_source_account
      FROM economic_accounts a
      JOIN owner_registry o ON o.economic_id = a.owner_economic_id
     WHERE o.economic_id = 'ECON-RESOURCE-PRODUCTION'
       AND a.asset_id = p_asset_id AND a.account_type = 'SYSTEM_ACCOUNT' AND a.status = 'ACTIVE'
     FOR UPDATE;
    IF v_source_account IS NULL THEN RAISE EXCEPTION 'resource production account is not provisioned'; END IF;
    v_tx := earth_post_transaction(
      p_correlation_id, p_game_day, 0, 'RESOURCE_PRODUCTION', 'SYSTEM_PRODUCTION',
      p_house_economic_id, 'starter-package-v1',
      jsonb_build_array(
        jsonb_build_object('account_id', v_source_account, 'asset_id', p_asset_id, 'delta_units', -p_amount_units),
        jsonb_build_object('account_id', v_target_account, 'asset_id', p_asset_id, 'delta_units', p_amount_units)
      )
    );
  END IF;
  RETURN v_tx;
END;
$$;

CREATE OR REPLACE FUNCTION earth_daily_asset_flow(p_game_day BIGINT)
RETURNS TABLE(asset_code TEXT, asset_kind TEXT, credit_created BIGINT, credit_destroyed BIGINT, resource_produced BIGINT, resource_consumed BIGINT)
LANGUAGE SQL STABLE AS $$
  SELECT a.code, a.asset_kind,
    COALESCE(SUM(CASE WHEN k.semantic_class = 'CREDIT_ISSUANCE' AND e.delta_units > 0 THEN e.delta_units ELSE 0 END), 0)::BIGINT,
    COALESCE(SUM(CASE WHEN k.semantic_class = 'CREDIT_RETIREMENT' AND e.delta_units < 0 THEN ABS(e.delta_units) ELSE 0 END), 0)::BIGINT,
    COALESCE(SUM(CASE WHEN k.semantic_class = 'RESOURCE_PRODUCTION' AND e.delta_units > 0 AND o.owner_type <> 'SYSTEM' THEN e.delta_units ELSE 0 END), 0)::BIGINT,
    COALESCE(SUM(CASE WHEN k.semantic_class = 'RESOURCE_CONSUMPTION' AND e.delta_units < 0 AND o.owner_type <> 'SYSTEM' THEN ABS(e.delta_units) ELSE 0 END), 0)::BIGINT
    FROM economic_assets a
    LEFT JOIN economic_entries e ON e.asset_id = a.id
    LEFT JOIN economic_transactions t ON t.id = e.transaction_id AND t.game_day = p_game_day
    LEFT JOIN economic_transaction_kinds k ON k.code = t.transaction_kind
    LEFT JOIN economic_accounts ea ON ea.id = e.account_id
    LEFT JOIN owner_registry o ON o.economic_id = ea.owner_economic_id
   GROUP BY a.id, a.code, a.asset_kind
   ORDER BY a.id;
$$;

CREATE OR REPLACE FUNCTION earth_assert_baseline_integrity() RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
  IF EXISTS (
    SELECT 1
      FROM economic_accounts a
      JOIN owner_registry o ON o.economic_id = a.owner_economic_id
      JOIN economic_assets e ON e.id = a.asset_id
     WHERE NOT EXISTS (
       SELECT 1 FROM economic_account_policies p
        WHERE p.owner_type = o.owner_type
          AND p.account_type = a.account_type
          AND (p.allowed_asset_kind = e.asset_kind OR p.allowed_asset_kind = 'ANY')
     )
  ) THEN RAISE EXCEPTION 'economic account capability invariant failed'; END IF;
  IF EXISTS (
    SELECT 1
      FROM market_orders m
      JOIN owner_registry o ON o.economic_id = m.owner_economic_id
      JOIN market_instruments i ON i.id = m.instrument_id
      JOIN economic_assets a ON a.id = i.asset_id
     WHERE o.owner_type <> 'HOUSE'
  ) THEN RAISE EXCEPTION 'market owner invariant failed'; END IF;
  IF EXISTS (SELECT 1 FROM market_orders WHERE remaining_units < 0 OR remaining_units > quantity_units) THEN RAISE EXCEPTION 'market order quantity invariant failed'; END IF;
  IF EXISTS (SELECT 1 FROM institution_budget_lines WHERE authorized_units < committed_units + spent_units) THEN RAISE EXCEPTION 'budget authority invariant failed'; END IF;
  IF EXISTS (SELECT 1 FROM humans h JOIN houses x ON x.current_human_id = h.id WHERE h.status <> 'ACTIVE') THEN RAISE EXCEPTION 'House current Human invariant failed'; END IF;
END;
$$;

CREATE OR REPLACE FUNCTION earth_game_day_from_total_minutes(p_total_minutes BIGINT)
RETURNS BIGINT LANGUAGE SQL IMMUTABLE STRICT AS $$
  SELECT FLOOR(p_total_minutes / 1440)::BIGINT;
$$;

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

CREATE OR REPLACE FUNCTION earth_post_settlement_batch(
  p_correlation_id TEXT, p_game_day BIGINT, p_game_minute INTEGER,
  p_source_type TEXT, p_source_id TEXT, p_rules_version TEXT, p_effects JSONB
) RETURNS TABLE(transaction_id BIGINT, created BOOLEAN)
LANGUAGE plpgsql AS $$
DECLARE v_id BIGINT;
BEGIN
  v_id := earth_post_transaction(p_correlation_id, p_game_day, p_game_minute, 'SETTLEMENT', p_source_type, p_source_id, p_rules_version, p_effects);
  RETURN QUERY SELECT v_id, TRUE;
END;
$$;

CREATE OR REPLACE FUNCTION earth_refresh_territory_capacity(
  p_territory_id TEXT,
  p_game_day BIGINT
)
RETURNS territory_capacity_state
LANGUAGE plpgsql
AS $$
DECLARE result territory_capacity_state;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM territories WHERE id = p_territory_id) THEN
    RAISE EXCEPTION 'Territory not found';
  END IF;

  INSERT INTO territory_capacity_state (
    territory_id, game_day, active_house_count, house_capacity, population_capacity,
    private_slot_capacity, public_slot_capacity, private_slots_used, public_slots_used,
    housing_capacity, health_capacity, energy_capacity, connectivity_capacity,
    service_capacity, updated_at
  )
  SELECT
    p_territory_id,
    p_game_day,
    (SELECT COUNT(*)::INTEGER FROM house_affiliations ha
      WHERE ha.primary_territory_id = p_territory_id AND ha.status = 'ACTIVE'),
    COALESCE(SUM(e.effect_value) FILTER (WHERE e.effect_code IN ('POPULATION_CAPACITY', 'HOUSE_CAPACITY')), 0),
    COALESCE(SUM(e.effect_value) FILTER (WHERE e.effect_code IN ('POPULATION_CAPACITY', 'HOUSE_CAPACITY')), 0),
    COALESCE(SUM(e.effect_value) FILTER (WHERE e.effect_code = 'PRIVATE_SLOTS'), 0),
    COALESCE(SUM(e.effect_value) FILTER (WHERE e.effect_code = 'PUBLIC_SLOTS'), 0),
    COALESCE((SELECT SUM(b.slot_footprint)::BIGINT FROM buildings b JOIN owner_registry o ON o.economic_id = b.owner_economic_id WHERE b.territory_id = p_territory_id AND b.status = 'ACTIVE' AND o.owner_type = 'HOUSE'), 0),
    COALESCE((SELECT SUM(b.slot_footprint)::BIGINT FROM buildings b JOIN owner_registry o ON o.economic_id = b.owner_economic_id WHERE b.territory_id = p_territory_id AND b.status = 'ACTIVE' AND o.owner_type = 'CORPORATION'), 0),
    COALESCE(SUM(e.effect_value) FILTER (WHERE e.effect_code = 'HOUSING_CAPACITY'), 0),
    COALESCE(SUM(e.effect_value) FILTER (WHERE e.effect_code = 'HEALTH_CAPACITY'), 0),
    COALESCE(SUM(e.effect_value) FILTER (WHERE e.effect_code = 'ENERGY_CAPACITY'), 0),
    COALESCE(SUM(e.effect_value) FILTER (WHERE e.effect_code = 'CONNECTIVITY_CAPACITY'), 0),
    COALESCE((SELECT jsonb_object_agg(service_key, service_total) FROM (
      SELECT COALESCE(NULLIF(bc.service_type, ''), 'UNSPECIFIED') AS service_key,
             SUM(bc.service_capacity_units)::BIGINT AS service_total
        FROM buildings b JOIN building_catalog bc ON bc.id = b.catalog_id
       WHERE b.territory_id = p_territory_id AND b.status = 'ACTIVE' AND bc.service_capacity_units > 0
       GROUP BY COALESCE(NULLIF(bc.service_type, ''), 'UNSPECIFIED')
    ) services), '{}'::jsonb),
    now()
  FROM buildings b
  LEFT JOIN building_catalog_effects e ON e.catalog_id = b.catalog_id
  WHERE b.territory_id = p_territory_id AND b.status = 'ACTIVE'
  RETURNING * INTO result;
  RETURN result;
END;
$$;

CREATE OR REPLACE FUNCTION earth_validate_building_ownership()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  owner_kind TEXT;
  ownership_scope TEXT;
  territory_corporation_id TEXT;
BEGIN
  SELECT owner_type INTO owner_kind FROM owner_registry WHERE economic_id = NEW.owner_economic_id;
  SELECT bc.ownership_scope INTO ownership_scope FROM building_catalog bc WHERE bc.id = NEW.catalog_id;
  SELECT t.corporation_id INTO territory_corporation_id FROM territories t WHERE t.id = NEW.territory_id;

  IF owner_kind IS NULL OR ownership_scope IS NULL OR territory_corporation_id IS NULL THEN
    RAISE EXCEPTION 'Building owner, blueprint, and Territory must exist';
  END IF;
  IF ownership_scope = 'PUBLIC' AND owner_kind <> 'CORPORATION' THEN
    RAISE EXCEPTION 'Public infrastructure must be Corporation-owned';
  END IF;
  IF ownership_scope = 'PRIVATE' AND owner_kind <> 'HOUSE' THEN
    RAISE EXCEPTION 'Private buildings must be House-owned';
  END IF;
  IF ownership_scope = 'PUBLIC' AND NOT EXISTS (
    SELECT 1 FROM owner_registry o
    WHERE o.id = territory_corporation_id AND o.economic_id = NEW.owner_economic_id AND o.owner_type = 'CORPORATION'
  ) THEN
    RAISE EXCEPTION 'Public infrastructure owner must be the Territory Corporation';
  END IF;
  IF ownership_scope = 'PRIVATE' AND NOT EXISTS (
    SELECT 1 FROM owner_registry o
    JOIN house_affiliations ha ON ha.house_id = o.id
    WHERE o.economic_id = NEW.owner_economic_id AND o.owner_type = 'HOUSE'
      AND ha.corporation_id = territory_corporation_id AND ha.status = 'ACTIVE'
  ) THEN
    RAISE EXCEPTION 'Private building owner must be an active House in the Territory Corporation';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER buildings_ownership_integrity
BEFORE INSERT OR UPDATE OF owner_economic_id, territory_id, catalog_id ON buildings
FOR EACH ROW EXECUTE FUNCTION earth_validate_building_ownership();

CREATE OR REPLACE FUNCTION earth_integrity_report()
RETURNS TABLE(check_name TEXT, invalid_count BIGINT)
LANGUAGE SQL STABLE AS $$
  SELECT 'negative_economic_balances', COUNT(*)::BIGINT
    FROM economic_accounts
   WHERE balance_units < 0 AND account_type <> 'SYSTEM_ACCOUNT'
  UNION ALL
  SELECT 'invalid_economic_account_capabilities', COUNT(*)::BIGINT
    FROM economic_accounts a
    JOIN owner_registry o ON o.economic_id = a.owner_economic_id
    JOIN economic_assets e ON e.id = a.asset_id
   WHERE NOT EXISTS (
     SELECT 1 FROM economic_account_policies p
      WHERE p.owner_type = o.owner_type
        AND p.account_type = a.account_type
        AND (p.allowed_asset_kind = e.asset_kind OR p.allowed_asset_kind = 'ANY')
   )
  UNION ALL
  SELECT 'invalid_resource_inventory_owners', COUNT(*)::BIGINT
    FROM economic_accounts a
    JOIN owner_registry o ON o.economic_id = a.owner_economic_id
    JOIN economic_assets e ON e.id = a.asset_id
   WHERE a.account_type = 'INVENTORY' AND e.asset_kind = 'RESOURCE'
     AND o.owner_type NOT IN ('HOUSE', 'CORPORATION')
  UNION ALL
  SELECT 'invalid_market_order_owners', COUNT(*)::BIGINT
    FROM market_orders m
    JOIN owner_registry o ON o.economic_id = m.owner_economic_id
   WHERE o.owner_type NOT IN ('HOUSE', 'CORPORATION')
  UNION ALL
  SELECT 'invalid_market_orders', COUNT(*)::BIGINT
    FROM market_orders WHERE remaining_units < 0 OR remaining_units > quantity_units
  UNION ALL
  SELECT 'invalid_asset_transfer_balance', COUNT(*)::BIGINT
    FROM (
      SELECT t.id, e.asset_id
        FROM economic_transactions t
        JOIN economic_transaction_kinds k ON k.code = t.transaction_kind
        JOIN economic_entries e ON e.transaction_id = t.id
       WHERE k.semantic_class = 'ASSET_TRANSFER'
       GROUP BY t.id, e.asset_id
      HAVING SUM(e.delta_units) <> 0
    ) invalid
  UNION ALL
  SELECT 'invalid_resource_production_authority', COUNT(*)::BIGINT
    FROM economic_transactions t
    JOIN economic_transaction_kinds k ON k.code = t.transaction_kind
   WHERE k.semantic_class = 'RESOURCE_PRODUCTION'
     AND (t.source_type <> 'SYSTEM_PRODUCTION' OR NOT EXISTS (
       SELECT 1 FROM economic_entries e
       JOIN economic_accounts a ON a.id = e.account_id
       JOIN owner_registry o ON o.economic_id = a.owner_economic_id
       WHERE e.transaction_id = t.id AND a.account_type = 'SYSTEM_ACCOUNT'
         AND o.owner_type = 'SYSTEM' AND e.delta_units < 0
     ))
  UNION ALL
  SELECT 'invalid_resource_consumption_authority', COUNT(*)::BIGINT
    FROM economic_transactions t
    JOIN economic_transaction_kinds k ON k.code = t.transaction_kind
   WHERE k.semantic_class = 'RESOURCE_CONSUMPTION'
     AND (t.source_type <> 'SYSTEM_CONSUMPTION' OR NOT EXISTS (
       SELECT 1 FROM economic_entries e
       JOIN economic_accounts a ON a.id = e.account_id
       JOIN owner_registry o ON o.economic_id = a.owner_economic_id
       WHERE e.transaction_id = t.id AND a.account_type = 'SYSTEM_ACCOUNT'
         AND o.owner_type = 'SYSTEM' AND e.delta_units > 0
     ))
  UNION ALL
  SELECT 'invalid_credit_issuance_authority', COUNT(*)::BIGINT
    FROM economic_transactions t
    JOIN economic_transaction_kinds k ON k.code = t.transaction_kind
   WHERE k.semantic_class = 'CREDIT_ISSUANCE'
     AND t.source_type <> 'SYSTEM_ISSUANCE'
  UNION ALL
  SELECT 'invalid_house_current_human', COUNT(*)::BIGINT
    FROM houses h JOIN humans x ON x.id = h.current_human_id
   WHERE x.status <> 'ACTIVE'
  UNION ALL
  SELECT 'invalid_budget_authority', COUNT(*)::BIGINT
    FROM institution_budget_lines
   WHERE authorized_units < committed_units + spent_units;
$$;

CREATE OR REPLACE FUNCTION earth_market_integrity_report()
RETURNS TABLE(check_name TEXT, invalid_count BIGINT)
LANGUAGE SQL STABLE AS $$
  SELECT 'invalid_market_orders', COUNT(*) FROM market_orders WHERE remaining_units < 0 OR remaining_units > quantity_units;
$$;

-- Tax amendments are serialized by rule lineage and always close the
-- previous open interval before the successor becomes effective.
CREATE OR REPLACE FUNCTION earth_create_tax_rule_version(
  p_tax_rule_id TEXT,
  p_scope TEXT,
  p_category TEXT,
  p_rate_bps INTEGER,
  p_tax_base_definition TEXT,
  p_beneficiary_economic_id TEXT,
  p_effective_from_game_day BIGINT,
  p_authorization_proposal_id TEXT
) RETURNS TEXT LANGUAGE plpgsql AS $$
DECLARE
  v_version INTEGER;
  v_id TEXT;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended(p_tax_rule_id, 0));
  SELECT COALESCE(MAX(version), 0) + 1 INTO v_version
    FROM tax_rule_versions
   WHERE tax_rule_id = p_tax_rule_id;
  UPDATE tax_rule_versions
     SET effective_to_game_day = p_effective_from_game_day - 1
   WHERE tax_rule_id = p_tax_rule_id
     AND effective_to_game_day IS NULL;
  v_id := p_tax_rule_id || '-V' || v_version::TEXT;
  INSERT INTO tax_rule_versions (
    id, tax_rule_id, scope, category, version, effective_from_game_day,
    rate_bps, tax_base_definition, beneficiary_economic_id, authorization_proposal_id
  ) VALUES (
    v_id, p_tax_rule_id, p_scope, p_category, v_version, p_effective_from_game_day,
    p_rate_bps, p_tax_base_definition, p_beneficiary_economic_id, p_authorization_proposal_id
  );
  RETURN v_id;
END;
$$;
-- Technology/IP V2 functions.
CREATE OR REPLACE FUNCTION earth_technology_is_patentable(p_technology_id TEXT)
RETURNS BOOLEAN LANGUAGE SQL STABLE AS $$
  SELECT COALESCE((SELECT patentable FROM technology_catalog
    WHERE id = p_technology_id OR code = p_technology_id
    ORDER BY effective_from_game_day DESC, definition_version DESC LIMIT 1), FALSE);
$$;

CREATE OR REPLACE FUNCTION earth_resolve_corporation_technology_access(
  p_corporation_economic_id TEXT, p_technology_id TEXT, p_game_day BIGINT
) RETURNS TABLE(has_access BOOLEAN, access_reason TEXT, source_id TEXT)
LANGUAGE SQL STABLE AS $$
  SELECT TRUE, a.access_source, a.source_id
  FROM corporation_technology_access a
  WHERE a.corporation_economic_id = p_corporation_economic_id
    AND a.technology_id = p_technology_id AND a.status = 'ACTIVE'
    AND a.effective_from_game_day <= p_game_day
    AND (a.effective_to_game_day IS NULL OR a.effective_to_game_day >= p_game_day)
  ORDER BY CASE a.access_source WHEN 'RESEARCHED' THEN 1 WHEN 'LICENSED' THEN 2 ELSE 3 END
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION earth_assert_technology_research_allowed(p_technology_id TEXT, p_game_day BIGINT)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM technology_catalog WHERE id = p_technology_id AND status = 'ACTIVE' AND effective_from_game_day <= p_game_day AND (effective_to_game_day IS NULL OR effective_to_game_day >= p_game_day)) THEN
    RAISE EXCEPTION 'Technology catalog entry is not active for research';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION earth_assert_technology_prerequisites_met(p_corporation_economic_id TEXT, p_technology_id TEXT, p_game_day BIGINT)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
  IF p_corporation_economic_id IS NULL OR p_technology_id IS NULL OR p_game_day < 0 THEN
    RAISE EXCEPTION 'Invalid technology research prerequisites';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION earth_grant_corporation_technology_access(
  p_corporation_economic_id TEXT, p_technology_id TEXT, p_access_source TEXT,
  p_source_id TEXT, p_effective_from_game_day BIGINT, p_effective_to_game_day BIGINT DEFAULT NULL
) RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
  IF p_access_source NOT IN ('RESEARCHED','LICENSED','GRANTED') THEN RAISE EXCEPTION 'Invalid technology access source'; END IF;
  INSERT INTO corporation_technology_access (corporation_economic_id, technology_id, access_source, source_id, effective_from_game_day, effective_to_game_day, status)
  VALUES (p_corporation_economic_id, p_technology_id, p_access_source, p_source_id, p_effective_from_game_day, p_effective_to_game_day, 'ACTIVE')
  ON CONFLICT (corporation_economic_id, technology_id) DO UPDATE SET access_source = EXCLUDED.access_source, source_id = EXCLUDED.source_id, effective_from_game_day = EXCLUDED.effective_from_game_day, effective_to_game_day = EXCLUDED.effective_to_game_day, status = 'ACTIVE', updated_at = CURRENT_TIMESTAMP;
END;
$$;

CREATE OR REPLACE FUNCTION earth_grant_completed_technology_patents(p_game_day BIGINT)
RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE v_count BIGINT;
BEGIN
  UPDATE technology_patents SET status = 'EXPIRED' WHERE status = 'ACTIVE' AND exclusive_through_game_day < p_game_day;
  INSERT INTO technology_patents (id, technology_id, owner_economic_id, granted_game_day, exclusive_through_game_day, status, granting_project_id)
  SELECT 'PATENT-' || p.target_id || '-' || p.id, p.target_id, p.corporation_economic_id, p.completed_game_day,
    p.completed_game_day + t.patent_exclusivity_days - 1, 'ACTIVE', p.id
  FROM corporation_research_projects p JOIN technology_catalog t ON t.id = p.target_id
  WHERE p.target_type = 'TECHNOLOGY' AND p.status = 'COMPLETED' AND p.completed_game_day = p_game_day
    AND t.patentable AND t.patent_exclusivity_days > 0 AND NOT EXISTS (SELECT 1 FROM technology_patents x WHERE x.technology_id = p.target_id AND x.status = 'ACTIVE')
  ON CONFLICT DO NOTHING;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

CREATE OR REPLACE FUNCTION earth_finalize_technology_public_domain(p_game_day BIGINT)
RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE v_count BIGINT;
BEGIN
  UPDATE technology_patents SET status = 'EXPIRED' WHERE status = 'ACTIVE' AND exclusive_through_game_day < p_game_day;
  INSERT INTO technology_public_domain (technology_id, effective_from_game_day, source_patent_id)
  SELECT p.technology_id, p.exclusive_through_game_day + 1, p.id FROM technology_patents p
  WHERE p.status = 'EXPIRED' AND p.exclusive_through_game_day < p_game_day ON CONFLICT DO NOTHING;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

CREATE OR REPLACE FUNCTION earth_refresh_house_daily_statements(p_game_day BIGINT)
RETURNS INTEGER LANGUAGE plpgsql AS $$
DECLARE v_count INTEGER;
BEGIN
  WITH owners AS (
    SELECT h.id AS house_id, o.economic_id FROM houses h
    JOIN owner_registry o ON o.id = h.id AND o.owner_type = 'HOUSE'
  ), daily_delta AS (
    SELECT o.house_id, a.asset_id, SUM(e.delta_units)::BIGINT AS delta_units
    FROM owners o JOIN economic_accounts a ON a.owner_economic_id = o.economic_id
    JOIN economic_entries e ON e.account_id = a.id
    JOIN economic_transactions t ON t.id = e.transaction_id AND t.game_day = p_game_day
    GROUP BY o.house_id, a.asset_id
  ), balances AS (
    SELECT o.house_id, asset.code, COALESCE(SUM(a.balance_units), 0)::BIGINT AS closing_units,
      COALESCE(SUM(a.balance_units), 0)::BIGINT - COALESCE(SUM(d.delta_units), 0)::BIGINT AS opening_units
    FROM owners o JOIN economic_accounts a ON a.owner_economic_id = o.economic_id AND a.status = 'ACTIVE'
    JOIN economic_assets asset ON asset.id = a.asset_id
    LEFT JOIN daily_delta d ON d.house_id = o.house_id AND d.asset_id = a.asset_id
    GROUP BY o.house_id, asset.code
  ), balance_json AS (
    SELECT house_id, jsonb_object_agg(code, opening_units::TEXT ORDER BY code) AS opening_assets,
      jsonb_object_agg(code, closing_units::TEXT ORDER BY code) AS closing_assets FROM balances GROUP BY house_id
  ), flow_json AS (
    SELECT o.house_id,
      COALESCE(jsonb_object_agg(asset.code, flow.produced::TEXT ORDER BY asset.code) FILTER (WHERE flow.produced > 0), '{}'::jsonb) AS production,
      COALESCE(jsonb_object_agg(asset.code, flow.consumed::TEXT ORDER BY asset.code) FILTER (WHERE flow.consumed > 0), '{}'::jsonb) AS consumption
    FROM owners o JOIN economic_accounts a ON a.owner_economic_id = o.economic_id
    JOIN economic_assets asset ON asset.id = a.asset_id
    LEFT JOIN LATERAL (
      SELECT COALESCE(SUM(e.delta_units) FILTER (WHERE t.transaction_kind = 'RESOURCE_PRODUCTION' AND e.delta_units > 0), 0)::BIGINT AS produced,
        COALESCE(SUM(-e.delta_units) FILTER (WHERE t.transaction_kind = 'RESOURCE_CONSUMPTION' AND e.delta_units < 0), 0)::BIGINT AS consumed
      FROM economic_entries e JOIN economic_transactions t ON t.id = e.transaction_id
      WHERE e.account_id = a.id AND t.game_day = p_game_day
    ) flow ON TRUE GROUP BY o.house_id
  ), market_json AS (
    SELECT owner.house_id, jsonb_object_agg(m.symbol, jsonb_build_object('purchases', m.purchases::TEXT, 'sales', m.sales::TEXT, 'volume', m.volume::TEXT, 'fees', m.fees::TEXT) ORDER BY m.symbol) AS market_activity
    FROM owners owner JOIN LATERAL (
      SELECT i.symbol, COALESCE(SUM(f.quantity_units) FILTER (WHERE f.buyer_economic_id = owner.economic_id), 0)::BIGINT AS purchases,
        COALESCE(SUM(f.quantity_units) FILTER (WHERE f.seller_economic_id = owner.economic_id), 0)::BIGINT AS sales,
        COALESCE(SUM(f.quantity_units), 0)::BIGINT AS volume,
        COALESCE(SUM(f.buyer_fee_units) FILTER (WHERE f.buyer_economic_id = owner.economic_id), 0)::BIGINT + COALESCE(SUM(f.seller_fee_units) FILTER (WHERE f.seller_economic_id = owner.economic_id), 0)::BIGINT AS fees
      FROM market_fills f JOIN market_batches b ON b.id = f.batch_id JOIN market_instruments i ON i.id = f.instrument_id
      WHERE b.game_day = p_game_day AND (f.buyer_economic_id = owner.economic_id OR f.seller_economic_id = owner.economic_id) GROUP BY i.symbol
    ) m ON TRUE GROUP BY owner.house_id
  ), obligation_json AS (
    SELECT owner.house_id, jsonb_build_object('taxes', COALESCE(SUM(o.amount_units) FILTER (WHERE o.status IN ('PAID', 'SETTLED')), 0)::TEXT, 'total', COALESCE(SUM(o.amount_units), 0)::TEXT, 'count', COUNT(*)::TEXT) AS obligations
    FROM owners owner LEFT JOIN tax_obligations o ON o.taxpayer_economic_id = owner.economic_id AND o.game_day = p_game_day GROUP BY owner.house_id
  ), exception_json AS (
    SELECT h.id AS house_id, jsonb_build_object('food_shortfall_units', COALESCE(SUM(m.food_shortfall_units), 0)::TEXT, 'unfed_humans', COUNT(*) FILTER (WHERE m.status = 'UNFED')::TEXT) AS exceptions
    FROM houses h LEFT JOIN personal_life_maintenance m ON m.house_id = h.id AND m.game_day = p_game_day GROUP BY h.id
  ), rows_to_write AS (
    SELECT b.house_id, p_game_day, b.opening_assets, b.closing_assets, COALESCE(f.production, '{}'::jsonb), COALESCE(f.consumption, '{}'::jsonb), COALESCE(m.market_activity, '{}'::jsonb), COALESCE(o.obligations, '{}'::jsonb), COALESCE(x.exceptions, '{}'::jsonb), COALESCE((b.closing_assets ->> 'CREDIT')::BIGINT, 0) - COALESCE((b.opening_assets ->> 'CREDIT')::BIGINT, 0)
    FROM balance_json b LEFT JOIN flow_json f USING (house_id) LEFT JOIN market_json m USING (house_id) LEFT JOIN obligation_json o USING (house_id) LEFT JOIN exception_json x USING (house_id)
  )
  INSERT INTO house_daily_statements (house_id, game_day, opening_assets, closing_assets, production, consumption, market_activity, obligations, exceptions, net_credit_units)
  SELECT * FROM rows_to_write
  ON CONFLICT (house_id, game_day) DO UPDATE SET opening_assets = EXCLUDED.opening_assets, closing_assets = EXCLUDED.closing_assets, production = EXCLUDED.production, consumption = EXCLUDED.consumption, market_activity = EXCLUDED.market_activity, obligations = EXCLUDED.obligations, exceptions = EXCLUDED.exceptions, net_credit_units = EXCLUDED.net_credit_units, updated_at = CURRENT_TIMESTAMP;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;
