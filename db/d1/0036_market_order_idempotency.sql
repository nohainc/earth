ALTER TABLE market_orders ADD COLUMN correlation_id TEXT;
CREATE UNIQUE INDEX IF NOT EXISTS idx_market_orders_human_correlation
  ON market_orders (human_id, correlation_id)
  WHERE correlation_id IS NOT NULL;
