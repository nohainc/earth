-- Market V2 Plan 7: durable fill records for atomic batch settlement.
CREATE TABLE IF NOT EXISTS market_fills (
  id UUID PRIMARY KEY,
  batch_id BIGINT NOT NULL REFERENCES market_batches(id),
  instrument_id TEXT NOT NULL REFERENCES market_instruments(id),
  buy_order_id UUID NOT NULL REFERENCES market_orders(id),
  sell_order_id UUID NOT NULL REFERENCES market_orders(id),
  quantity_units BIGINT NOT NULL CHECK (quantity_units > 0),
  price_units BIGINT NOT NULL CHECK (price_units > 0),
  quote_units BIGINT NOT NULL CHECK (quote_units >= 0),
  fee_units BIGINT NOT NULL DEFAULT 0 CHECK (fee_units >= 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (batch_id, buy_order_id, sell_order_id)
);
CREATE INDEX IF NOT EXISTS market_fills_instrument_idx ON market_fills(instrument_id, batch_id);
