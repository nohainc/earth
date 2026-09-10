-- Economy V2 Plan 4: one auditable transaction language for every asset.
-- This migration creates the transaction/entry layer only. Posting into live
-- balances is intentionally deferred to the next economic-engine phase.

CREATE SEQUENCE IF NOT EXISTS economic_transactions_id_seq
  AS BIGINT START WITH 1 INCREMENT BY 1 MINVALUE 1;
CREATE SEQUENCE IF NOT EXISTS economic_entries_id_seq
  AS BIGINT START WITH 1 INCREMENT BY 1 MINVALUE 1;

CREATE TABLE IF NOT EXISTS economic_transactions (
  id BIGINT PRIMARY KEY DEFAULT nextval('economic_transactions_id_seq'),
  correlation_id TEXT NOT NULL UNIQUE,
  game_day BIGINT NOT NULL CHECK (game_day >= 0),
  game_minute SMALLINT NOT NULL DEFAULT 0 CHECK (game_minute BETWEEN 0 AND 1439),
  transaction_kind TEXT NOT NULL CHECK (length(btrim(transaction_kind)) > 0),
  source_type TEXT NOT NULL CHECK (length(btrim(source_type)) > 0),
  source_id TEXT,
  rules_version TEXT NOT NULL CHECK (length(btrim(rules_version)) > 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS economic_entries (
  id BIGINT PRIMARY KEY DEFAULT nextval('economic_entries_id_seq'),
  transaction_id BIGINT NOT NULL REFERENCES economic_transactions(id) ON DELETE CASCADE,
  account_id BIGINT NOT NULL REFERENCES economic_accounts(id),
  game_day BIGINT NOT NULL CHECK (game_day >= 0),
  delta BIGINT NOT NULL CHECK (delta <> 0),
  reason_code TEXT NOT NULL CHECK (length(btrim(reason_code)) > 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS economic_transactions_day_idx
  ON economic_transactions (game_day DESC, id DESC);
CREATE INDEX IF NOT EXISTS economic_transactions_source_idx
  ON economic_transactions (source_type, source_id, game_day DESC);
CREATE INDEX IF NOT EXISTS economic_entries_transaction_idx
  ON economic_entries (transaction_id, id);
CREATE INDEX IF NOT EXISTS economic_entries_account_day_idx
  ON economic_entries (account_id, game_day DESC, id DESC);
CREATE INDEX IF NOT EXISTS economic_entries_reason_idx
  ON economic_entries (reason_code, game_day DESC);

-- A transaction may contain several assets, but each asset must balance to
-- zero. The constraint is deferred so callers can insert all entries in any
-- order within one database transaction.
CREATE OR REPLACE FUNCTION earth_assert_economic_transaction_balanced()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  unbalanced_count BIGINT;
  entry_count BIGINT;
  transaction_key BIGINT;
BEGIN
  transaction_key := CASE
    WHEN TG_TABLE_NAME = 'economic_transactions' THEN COALESCE(NEW.id, OLD.id)
    ELSE COALESCE(NEW.transaction_id, OLD.transaction_id)
  END;
  SELECT COUNT(*) INTO entry_count
  FROM economic_entries
  WHERE transaction_id = transaction_key;
  IF entry_count < 2 THEN
    RAISE EXCEPTION 'Economic transaction % requires at least two entries', transaction_key;
  END IF;

  SELECT COUNT(*) INTO unbalanced_count
  FROM (
    SELECT ea.id
    FROM economic_entries ee
    JOIN economic_accounts acc ON acc.id = ee.account_id
    JOIN economic_assets ea ON ea.id = acc.asset_id
    WHERE ee.transaction_id = transaction_key
    GROUP BY ea.id
    HAVING SUM(ee.delta) <> 0
  ) unbalanced;
  IF unbalanced_count > 0 THEN
    RAISE EXCEPTION 'Economic transaction % is not balanced per asset', transaction_key;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS economic_entries_balance_check ON economic_entries;
CREATE CONSTRAINT TRIGGER economic_entries_balance_check
AFTER INSERT OR UPDATE OR DELETE ON economic_entries
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW
EXECUTE FUNCTION earth_assert_economic_transaction_balanced();

DROP TRIGGER IF EXISTS economic_transaction_balance_check ON economic_transactions;
CREATE CONSTRAINT TRIGGER economic_transaction_balance_check
AFTER INSERT OR UPDATE ON economic_transactions
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW
EXECUTE FUNCTION earth_assert_economic_transaction_balanced();
