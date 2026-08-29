-- Contract terms remain authoritative structured data. Migration 019 removed
-- the legacy JSONB field, so restore the capability with canonical Nano Markup
-- and typed business references for safe scheduler joins.
ALTER TABLE negotiated_contracts
  ADD COLUMN IF NOT EXISTS terms_markup TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS proposer_business_id TEXT REFERENCES businesses(id),
  ADD COLUMN IF NOT EXISTS counterparty_business_id TEXT REFERENCES businesses(id);

CREATE INDEX IF NOT EXISTS negotiated_contracts_service_business_idx
  ON negotiated_contracts (kind, status, ends_game_day, proposer_business_id);
