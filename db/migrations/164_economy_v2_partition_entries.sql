-- Economy V2 Plan 15: range-partition the high-volume entry history only.
-- Headers remain a normal table so correlation_id stays globally unique.

ALTER TABLE economic_entries RENAME TO economic_entries_pre_partition;

CREATE TABLE economic_entries (
  id BIGINT NOT NULL DEFAULT nextval('economic_entries_id_seq'),
  transaction_id BIGINT NOT NULL REFERENCES economic_transactions(id) ON DELETE CASCADE,
  account_id BIGINT NOT NULL REFERENCES economic_accounts(id),
  game_day BIGINT NOT NULL CHECK (game_day >= 0),
  delta BIGINT NOT NULL CHECK (delta <> 0),
  reason_code TEXT NOT NULL CHECK (length(btrim(reason_code)) > 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id, game_day)
) PARTITION BY RANGE (game_day);

CREATE TABLE economic_entries_days_0000_1000
  PARTITION OF economic_entries FOR VALUES FROM (0) TO (1001);
CREATE TABLE economic_entries_days_1001_2000
  PARTITION OF economic_entries FOR VALUES FROM (1001) TO (2001);
CREATE TABLE economic_entries_days_2001_3000
  PARTITION OF economic_entries FOR VALUES FROM (2001) TO (3001);
CREATE TABLE economic_entries_default
  PARTITION OF economic_entries DEFAULT;

INSERT INTO economic_entries (id, transaction_id, account_id, game_day, delta, reason_code, created_at)
SELECT id, transaction_id, account_id, game_day, delta, reason_code, created_at
FROM economic_entries_pre_partition;

DROP TRIGGER IF EXISTS economic_entries_owner_totals ON economic_entries_pre_partition;
CREATE TRIGGER economic_entries_owner_totals
AFTER INSERT ON economic_entries
REFERENCING NEW TABLE AS new_entries
FOR EACH STATEMENT
EXECUTE FUNCTION earth_update_economic_owner_totals();

CREATE INDEX IF NOT EXISTS economic_entries_transaction_idx
  ON economic_entries (transaction_id, id);
CREATE INDEX IF NOT EXISTS economic_entries_account_day_idx
  ON economic_entries (account_id, game_day DESC, id DESC);
CREATE INDEX IF NOT EXISTS economic_entries_reason_idx
  ON economic_entries (reason_code, game_day DESC);

DROP TABLE economic_entries_pre_partition;
