-- EARTH ACTIVE MIGRATION: bounded late-entry support
-- This table is an entitlement ledger, not a balance.  The only supported
-- issuance is the fixed resource bundle in catch-up-postgres.ts; CREDIT is
-- intentionally excluded.
CREATE TABLE IF NOT EXISTS house_entry_support (
  house_id TEXT PRIMARY KEY REFERENCES houses(id),
  rules_version TEXT NOT NULL DEFAULT 'entry-support-v1',
  status TEXT NOT NULL DEFAULT 'ELIGIBLE' CHECK (status IN ('ELIGIBLE','CLAIMED','INELIGIBLE')),
  entry_game_day BIGINT,
  eligible_until_game_day BIGINT,
  claimed_game_day BIGINT,
  claimed_transaction_ids BIGINT[] NOT NULL DEFAULT ARRAY[]::BIGINT[],
  correlation_id TEXT UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CHECK ((status = 'CLAIMED' AND claimed_game_day IS NOT NULL) OR status <> 'CLAIMED')
);
CREATE INDEX IF NOT EXISTS house_entry_support_status_idx
  ON house_entry_support (status, eligible_until_game_day, house_id);

INSERT INTO house_entry_support (house_id, eligible_until_game_day)
SELECT h.id, NULL FROM houses h
ON CONFLICT (house_id) DO NOTHING;
