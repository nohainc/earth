ALTER TABLE market_orders ADD COLUMN side TEXT NOT NULL DEFAULT 'buy' CHECK (side IN ('buy', 'sell'));
CREATE INDEX IF NOT EXISTS market_orders_matching_idx ON market_orders(product, side, status, limit_price, created_at);
