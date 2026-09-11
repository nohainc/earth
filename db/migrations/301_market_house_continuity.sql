-- Market V2 orders are House-owned. The Human column remains the historical
-- acting representative, while idempotency and control use the economic owner.
CREATE UNIQUE INDEX IF NOT EXISTS market_orders_owner_correlation_idx
  ON market_orders(owner_economic_id, correlation_id)
  WHERE owner_economic_id IS NOT NULL AND correlation_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS market_orders_house_control_idx
  ON market_orders(owner_economic_id, status, created_at DESC);
