ALTER TABLE market_orders ADD COLUMN reserved_credits NUMERIC NOT NULL DEFAULT 0;
CREATE INDEX IF NOT EXISTS market_orders_reserved_idx ON market_orders(human_id, side, status, reserved_credits);
