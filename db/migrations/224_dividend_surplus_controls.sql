-- Finance V2 Plan 14: dividend capacity is computed from available surplus.

ALTER TABLE civic_dividend_payouts
  ADD COLUMN IF NOT EXISTS economic_transaction_id BIGINT REFERENCES economic_transactions(id),
  ADD COLUMN IF NOT EXISTS committed_obligations_units BIGINT NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS required_reserve_units BIGINT NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS distributable_units BIGINT NOT NULL DEFAULT 0;

CREATE TABLE IF NOT EXISTS dividend_settlement_runs (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  payer_owner_economic_id BIGINT NOT NULL REFERENCES owner_registry(economic_id),
  beneficiary_kind TEXT NOT NULL CHECK (beneficiary_kind IN ('CITY_RESIDENT', 'CORPORATION_SHAREHOLDER')),
  game_day BIGINT NOT NULL,
  gross_surplus_units BIGINT NOT NULL DEFAULT 0,
  committed_obligations_units BIGINT NOT NULL DEFAULT 0,
  required_reserve_units BIGINT NOT NULL DEFAULT 0,
  distributable_units BIGINT NOT NULL DEFAULT 0,
  economic_transaction_id BIGINT REFERENCES economic_transactions(id),
  status TEXT NOT NULL CHECK (status IN ('COMPLETED', 'NO_SURPLUS', 'INSUFFICIENT_SURPLUS')),
  correlation_id TEXT NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (payer_owner_economic_id, beneficiary_kind, game_day)
);
