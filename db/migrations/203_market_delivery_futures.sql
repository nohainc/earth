-- Market V2 Plan 11: fully collateralized delivery-future obligations.
ALTER TABLE market_fills
  ALTER COLUMN economic_transaction_id DROP NOT NULL;

CREATE TABLE IF NOT EXISTS market_delivery_obligations (
  fill_id UUID PRIMARY KEY REFERENCES market_fills(id),
  instrument_id TEXT NOT NULL REFERENCES market_instruments(id),
  batch_id BIGINT NOT NULL REFERENCES market_batches(id),
  buyer_order_id UUID NOT NULL REFERENCES market_orders(id),
  seller_order_id UUID NOT NULL REFERENCES market_orders(id),
  buyer_economic_id BIGINT NOT NULL REFERENCES owner_registry(economic_id),
  seller_economic_id BIGINT NOT NULL REFERENCES owner_registry(economic_id),
  quantity_units BIGINT NOT NULL CHECK (quantity_units > 0),
  agreed_price_units BIGINT NOT NULL CHECK (agreed_price_units > 0),
  expiry_total_game_minute BIGINT NOT NULL CHECK (expiry_total_game_minute > 0),
  buyer_escrow_account_id BIGINT NOT NULL REFERENCES economic_accounts(id),
  seller_escrow_account_id BIGINT NOT NULL REFERENCES economic_accounts(id),
  status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'delivered', 'defaulted', 'cancelled')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  settled_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS market_delivery_obligations_expiry_idx
  ON market_delivery_obligations(status, expiry_total_game_minute);
CREATE INDEX IF NOT EXISTS market_delivery_obligations_instrument_idx
  ON market_delivery_obligations(instrument_id, status, expiry_total_game_minute);
