-- Finance V2 Plan 1: make CREDIT issuance, retirement, and supply measurable.

CREATE TABLE IF NOT EXISTS monetary_supply_snapshots (
  game_day BIGINT PRIMARY KEY CHECK (game_day >= 0),
  issued_total_units BIGINT NOT NULL CHECK (issued_total_units >= 0),
  retired_total_units BIGINT NOT NULL CHECK (retired_total_units >= 0),
  circulating_units BIGINT NOT NULL CHECK (circulating_units >= 0),
  escrow_units BIGINT NOT NULL CHECK (escrow_units >= 0),
  bank_reserve_units BIGINT NOT NULL CHECK (bank_reserve_units >= 0),
  institution_reserve_units BIGINT NOT NULL CHECK (institution_reserve_units >= 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CHECK (issued_total_units >= retired_total_units)
);
CREATE INDEX IF NOT EXISTS monetary_supply_snapshots_day_idx
  ON monetary_supply_snapshots (game_day DESC);

-- Separate owners let the existing ISSUANCE and CONSUMPTION_SINK semantics
-- remain valid for physical resources while giving CREDIT its own authority.
INSERT INTO owner_registry (id, owner_type, source_id)
VALUES
  ('SYSTEM-MONETARY-AUTHORITY', 'system', 'SYSTEM-MONETARY-AUTHORITY'),
  ('SYSTEM-MONETARY-RETIREMENT', 'system', 'SYSTEM-MONETARY-RETIREMENT')
ON CONFLICT (id) DO NOTHING;

INSERT INTO economic_accounts (owner_economic_id, asset_id, account_type, is_default_settlement, legacy_account_id)
SELECT o.economic_id, 1, t.id, FALSE,
       CASE t.id WHEN 7 THEN 'monetary-issuance' ELSE 'monetary-retirement' END
FROM owner_registry o
JOIN economic_account_types t ON t.id = CASE
  WHEN o.id = 'SYSTEM-MONETARY-AUTHORITY' THEN 7
  WHEN o.id = 'SYSTEM-MONETARY-RETIREMENT' THEN 8
END
WHERE o.id IN ('SYSTEM-MONETARY-AUTHORITY', 'SYSTEM-MONETARY-RETIREMENT')
  AND NOT EXISTS (SELECT 1 FROM economic_accounts a WHERE a.legacy_account_id = CASE t.id WHEN 7 THEN 'monetary-issuance' ELSE 'monetary-retirement' END);

CREATE OR REPLACE FUNCTION earth_validate_monetary_authority_transaction(p_transaction_id BIGINT)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
  invalid_count BIGINT;
BEGIN
  SELECT COUNT(*) INTO invalid_count
  FROM economic_entries e
  JOIN economic_accounts a ON a.id = e.account_id
  JOIN owner_registry o ON o.economic_id = a.owner_economic_id
  JOIN economic_transactions t ON t.id = e.transaction_id
  WHERE e.transaction_id = p_transaction_id
    AND (
      (o.id = 'SYSTEM-MONETARY-AUTHORITY' AND (a.asset_id <> 1 OR a.account_type <> 7 OR e.delta >= 0 OR e.reason_code NOT IN ('GENESIS_ISSUANCE', 'PLAYER_STARTING_GRANT', 'MONETARY_STABILIZATION') OR t.source_type <> 'monetary_authority')
      OR
      (o.id = 'SYSTEM-MONETARY-RETIREMENT' AND (a.asset_id <> 1 OR a.account_type <> 8 OR e.delta <= 0 OR e.reason_code <> 'CREDIT_RETIREMENT' OR t.source_type <> 'monetary_authority'))
    );
  IF invalid_count > 0 THEN
    RAISE EXCEPTION 'Transaction % violates monetary authority rules', p_transaction_id;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM economic_entries e
    JOIN economic_accounts a ON a.id = e.account_id
    JOIN owner_registry o ON o.economic_id = a.owner_economic_id
    JOIN economic_transactions t ON t.id = e.transaction_id
    WHERE e.transaction_id = p_transaction_id
      AND o.id IN ('SYSTEM-MONETARY-AUTHORITY', 'SYSTEM-MONETARY-RETIREMENT')
      AND (length(btrim(t.rules_version)) = 0 OR t.source_id IS NULL OR length(btrim(t.source_id)) = 0)
  ) THEN
    RAISE EXCEPTION 'Monetary authority transaction % requires rules_version and source_id', p_transaction_id;
  END IF;
END;
$$;

-- Replace the existing deferred balance trigger function so direct inserts and
-- both posting primitives enforce the monetary boundary as well.
CREATE OR REPLACE FUNCTION earth_assert_economic_transaction_balanced()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  transaction_key BIGINT;
  transaction_keys BIGINT[];
  entry_count BIGINT;
  unbalanced_count BIGINT;
BEGIN
  IF TG_TABLE_NAME = 'economic_transactions' THEN
    transaction_keys := ARRAY[COALESCE(NEW.id, OLD.id)];
  ELSE
    transaction_keys := ARRAY[COALESCE(NEW.transaction_id, OLD.transaction_id)];
    IF TG_OP = 'UPDATE' AND OLD.transaction_id IS DISTINCT FROM NEW.transaction_id THEN
      transaction_keys := array_append(transaction_keys, OLD.transaction_id);
    END IF;
  END IF;
  FOREACH transaction_key IN ARRAY transaction_keys LOOP
    SELECT COUNT(*) INTO entry_count FROM economic_entries WHERE transaction_id = transaction_key;
    IF entry_count < 2 THEN RAISE EXCEPTION 'Economic transaction % requires at least two entries', transaction_key; END IF;
    SELECT COUNT(*) INTO unbalanced_count
    FROM (SELECT a.asset_id FROM economic_entries e JOIN economic_accounts a ON a.id = e.account_id WHERE e.transaction_id = transaction_key GROUP BY a.asset_id HAVING SUM(e.delta) <> 0) invalid;
    IF unbalanced_count > 0 THEN RAISE EXCEPTION 'Economic transaction % is not balanced per asset', transaction_key; END IF;
    PERFORM earth_validate_monetary_authority_transaction(transaction_key);
  END LOOP;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION earth_post_monetary_operation(
  p_correlation_id TEXT,
  p_game_day BIGINT,
  p_game_minute SMALLINT,
  p_reason_code TEXT,
  p_source_id TEXT,
  p_rules_version TEXT,
  p_entries JSONB
)
RETURNS TABLE (transaction_id BIGINT, created BOOLEAN, entry_count BIGINT)
LANGUAGE plpgsql
AS $$
BEGIN
  IF p_reason_code NOT IN ('GENESIS_ISSUANCE', 'PLAYER_STARTING_GRANT', 'MONETARY_STABILIZATION', 'CREDIT_RETIREMENT') THEN
    RAISE EXCEPTION 'Unsupported monetary operation reason: %', p_reason_code;
  END IF;
  RETURN QUERY SELECT * FROM earth_post_transaction(
    p_correlation_id, p_game_day, p_game_minute, 'monetary_operation',
    'monetary_authority', p_source_id, p_rules_version,
    p_entries
  );
END;
$$;

CREATE OR REPLACE FUNCTION earth_refresh_monetary_supply_snapshot(p_game_day BIGINT)
RETURNS monetary_supply_snapshots
LANGUAGE plpgsql
AS $$
DECLARE
  snapshot monetary_supply_snapshots;
BEGIN
  INSERT INTO monetary_supply_snapshots (
    game_day, issued_total_units, retired_total_units, circulating_units,
    escrow_units, bank_reserve_units, institution_reserve_units
  )
  SELECT p_game_day,
    COALESCE((SELECT -SUM(e.delta) FROM economic_entries e JOIN economic_accounts a ON a.id = e.account_id JOIN owner_registry o ON o.economic_id = a.owner_economic_id WHERE a.asset_id = 1 AND a.account_type = 7 AND o.id = 'SYSTEM-MONETARY-AUTHORITY' AND e.delta < 0), 0),
    COALESCE((SELECT SUM(e.delta) FROM economic_entries e JOIN economic_accounts a ON a.id = e.account_id JOIN owner_registry o ON o.economic_id = a.owner_economic_id WHERE a.asset_id = 1 AND a.account_type = 8 AND o.id = 'SYSTEM-MONETARY-RETIREMENT' AND e.delta > 0), 0),
    COALESCE((SELECT SUM(balance) FROM economic_accounts WHERE asset_id = 1 AND account_type NOT IN (7, 8)), 0),
    COALESCE((SELECT SUM(balance) FROM economic_accounts WHERE asset_id = 1 AND account_type = 6), 0),
    COALESCE((SELECT SUM(balance) FROM economic_accounts WHERE asset_id = 1 AND account_type = 10), 0),
    COALESCE((SELECT SUM(a.balance) FROM economic_accounts a JOIN owner_registry o ON o.economic_id = a.owner_economic_id WHERE a.asset_id = 1 AND a.account_type IN (3, 4, 5) AND o.owner_type IN ('city', 'corporation', 'system')), 0)
  ON CONFLICT (game_day) DO UPDATE SET
    issued_total_units = EXCLUDED.issued_total_units,
    retired_total_units = EXCLUDED.retired_total_units,
    circulating_units = EXCLUDED.circulating_units,
    escrow_units = EXCLUDED.escrow_units,
    bank_reserve_units = EXCLUDED.bank_reserve_units,
    institution_reserve_units = EXCLUDED.institution_reserve_units,
    created_at = CURRENT_TIMESTAMP
  RETURNING * INTO snapshot;
  RETURN snapshot;
END;
$$;

CREATE OR REPLACE FUNCTION earth_monetary_supply_integrity()
RETURNS TABLE(check_name TEXT, invalid_count BIGINT)
LANGUAGE SQL
AS $$
  SELECT 'monetary_supply_balance_mismatch', COUNT(*)::BIGINT
  FROM monetary_supply_snapshots s
  WHERE s.issued_total_units - s.retired_total_units <> s.circulating_units
  UNION ALL
  SELECT 'unauthorized_monetary_reason', COUNT(*)::BIGINT
  FROM economic_entries e
  JOIN economic_accounts a ON a.id = e.account_id
  JOIN owner_registry o ON o.economic_id = a.owner_economic_id
  JOIN economic_transactions t ON t.id = e.transaction_id
  WHERE o.id IN ('SYSTEM-MONETARY-AUTHORITY', 'SYSTEM-MONETARY-RETIREMENT')
    AND NOT (
      (o.id = 'SYSTEM-MONETARY-AUTHORITY' AND e.reason_code IN ('GENESIS_ISSUANCE', 'PLAYER_STARTING_GRANT', 'MONETARY_STABILIZATION') AND e.delta < 0 AND t.source_type = 'monetary_authority')
      OR (o.id = 'SYSTEM-MONETARY-RETIREMENT' AND e.reason_code = 'CREDIT_RETIREMENT' AND e.delta > 0 AND t.source_type = 'monetary_authority')
    )
$$;

CREATE OR REPLACE FUNCTION earth_integrity_report()
RETURNS TABLE(check_name TEXT, invalid_count BIGINT)
LANGUAGE SQL
AS $$
  SELECT check_name, invalid_count FROM earth_base_integrity_report()
  UNION ALL
  SELECT check_name, invalid_count FROM earth_market_integrity_report()
  UNION ALL
  SELECT check_name, invalid_count FROM earth_monetary_supply_integrity()
$$;
