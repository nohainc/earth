-- EARTH ACTIVE MIGRATION: make policy-originated Spot orders auditable and expirable

ALTER TABLE market_orders
  ADD COLUMN IF NOT EXISTS source_type TEXT NOT NULL DEFAULT 'MANUAL',
  ADD COLUMN IF NOT EXISTS policy_id TEXT REFERENCES house_operating_policies(id),
  ADD COLUMN IF NOT EXISTS policy_budget_id TEXT,
  ADD COLUMN IF NOT EXISTS good_til_game_day BIGINT;

ALTER TABLE market_orders DROP CONSTRAINT IF EXISTS market_orders_source_type_check;
ALTER TABLE market_orders ADD CONSTRAINT market_orders_source_type_check
  CHECK (source_type IN ('MANUAL', 'HOUSE_POLICY'));
ALTER TABLE market_orders DROP CONSTRAINT IF EXISTS market_orders_good_til_check;
ALTER TABLE market_orders ADD CONSTRAINT market_orders_good_til_check
  CHECK (good_til_game_day IS NULL OR good_til_game_day >= 1);
ALTER TABLE market_orders DROP CONSTRAINT IF EXISTS market_orders_policy_link_check;
ALTER TABLE market_orders ADD CONSTRAINT market_orders_policy_link_check
  CHECK (source_type = 'MANUAL' OR policy_id IS NOT NULL);

CREATE INDEX IF NOT EXISTS market_orders_expiry_idx
  ON market_orders (good_til_game_day, status)
  WHERE good_til_game_day IS NOT NULL;
CREATE INDEX IF NOT EXISTS market_orders_policy_idx
  ON market_orders (policy_id, good_til_game_day)
  WHERE policy_id IS NOT NULL;
