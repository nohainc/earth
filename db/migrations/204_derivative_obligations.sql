-- Market V2 Plan 12: explicit, fully collateralized derivative positions.
CREATE TABLE IF NOT EXISTS derivative_obligations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  instrument_id TEXT NOT NULL REFERENCES market_instruments(id),
  originating_fill_id UUID NOT NULL REFERENCES market_fills(id),
  long_owner_economic_id BIGINT NOT NULL REFERENCES owner_registry(economic_id),
  short_owner_economic_id BIGINT NOT NULL REFERENCES owner_registry(economic_id),
  quantity_units BIGINT NOT NULL CHECK (quantity_units > 0),
  delivery_price_units BIGINT NOT NULL CHECK (delivery_price_units > 0),
  long_escrow_account_id BIGINT NOT NULL REFERENCES economic_accounts(id),
  short_escrow_account_id BIGINT NOT NULL REFERENCES economic_accounts(id),
  expiry_total_game_minute BIGINT NOT NULL CHECK (expiry_total_game_minute > 0),
  expiry_batch_id BIGINT NOT NULL CHECK (expiry_batch_id >= 0),
  status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'settling', 'settled', 'cancelled')),
  settlement_transaction_id BIGINT REFERENCES economic_transactions(id),
  created_game_day BIGINT NOT NULL,
  created_game_minute INTEGER NOT NULL CHECK (created_game_minute BETWEEN 0 AND 1439),
  settled_game_day BIGINT,
  settled_game_minute INTEGER CHECK (settled_game_minute BETWEEN 0 AND 1439),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (originating_fill_id)
);

CREATE INDEX IF NOT EXISTS derivative_obligations_expiry_idx
  ON derivative_obligations(status, expiry_total_game_minute);
CREATE INDEX IF NOT EXISTS derivative_obligations_owner_idx
  ON derivative_obligations(long_owner_economic_id, short_owner_economic_id, status);

INSERT INTO derivative_obligations (
  id, instrument_id, originating_fill_id, long_owner_economic_id, short_owner_economic_id,
  quantity_units, delivery_price_units, long_escrow_account_id, short_escrow_account_id,
  expiry_total_game_minute, expiry_batch_id, status, settlement_transaction_id,
  created_game_day, created_game_minute, settled_game_day, settled_game_minute
)
SELECT gen_random_uuid(), instrument_id, fill_id, buyer_economic_id, seller_economic_id,
       quantity_units, agreed_price_units, buyer_escrow_account_id, seller_escrow_account_id,
       expiry_total_game_minute, FLOOR(expiry_total_game_minute / 60)::BIGINT,
       CASE status WHEN 'open' THEN 'open' WHEN 'delivered' THEN 'settled' ELSE status END,
       NULL, 1, 0, NULL, NULL
  FROM market_delivery_obligations
ON CONFLICT (originating_fill_id) DO NOTHING;
