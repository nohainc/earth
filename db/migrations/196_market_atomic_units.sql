-- Market V2 Plan 2: integer atomic values for matching and accounting.
ALTER TABLE market_orders
  ADD COLUMN IF NOT EXISTS quantity_units BIGINT,
  ADD COLUMN IF NOT EXISTS limit_price_units BIGINT,
  ADD COLUMN IF NOT EXISTS filled_quantity_units BIGINT NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS reserved_quote_units BIGINT NOT NULL DEFAULT 0;

UPDATE market_orders
SET quantity_units = ROUND(quantity * 1000000)::BIGINT,
    limit_price_units = ROUND(limit_price * 100)::BIGINT,
    filled_quantity_units = ROUND(filled_quantity * 1000000)::BIGINT,
    reserved_quote_units = ROUND(reserved_credits * 100)::BIGINT
WHERE quantity_units IS NULL OR limit_price_units IS NULL;

ALTER TABLE market_orders
  ALTER COLUMN quantity_units SET NOT NULL,
  ALTER COLUMN limit_price_units SET NOT NULL,
  ADD CONSTRAINT market_orders_atomic_units_ck CHECK (quantity_units > 0 AND limit_price_units > 0 AND filled_quantity_units >= 0 AND reserved_quote_units >= 0);

ALTER TABLE market_trades
  ADD COLUMN IF NOT EXISTS quantity_units BIGINT,
  ADD COLUMN IF NOT EXISTS clearing_price_units BIGINT,
  ADD COLUMN IF NOT EXISTS quote_units BIGINT NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS fee_units BIGINT NOT NULL DEFAULT 0;

UPDATE market_trades
SET quantity_units = ROUND(quantity * 1000000)::BIGINT,
    clearing_price_units = ROUND(clearing_price * 100)::BIGINT
WHERE quantity_units IS NULL OR clearing_price_units IS NULL;

ALTER TABLE market_trades
  ALTER COLUMN quantity_units SET NOT NULL,
  ALTER COLUMN clearing_price_units SET NOT NULL,
  ADD CONSTRAINT market_trades_atomic_units_ck CHECK (quantity_units > 0 AND clearing_price_units > 0 AND quote_units >= 0 AND fee_units >= 0);

ALTER TABLE market_prices
  ADD COLUMN IF NOT EXISTS price_units BIGINT,
  ADD COLUMN IF NOT EXISTS supply_units BIGINT NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS demand_units BIGINT NOT NULL DEFAULT 0;

UPDATE market_prices
SET price_units = ROUND(price * 100)::BIGINT,
    supply_units = ROUND(supply * 1000000)::BIGINT,
    demand_units = ROUND(demand * 1000000)::BIGINT
WHERE price_units IS NULL;

ALTER TABLE market_prices
  ALTER COLUMN price_units SET NOT NULL,
  ADD CONSTRAINT market_prices_atomic_units_ck CHECK (price_units > 0 AND supply_units >= 0 AND demand_units >= 0);

CREATE INDEX IF NOT EXISTS market_orders_atomic_matching_idx
  ON market_orders(product, side, status, limit_price_units, created_at);
CREATE INDEX IF NOT EXISTS market_orders_atomic_reserved_idx
  ON market_orders(human_id, side, status, reserved_quote_units);
