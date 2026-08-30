-- Food is a first-class market commodity, including deferred limit orders.
ALTER TABLE market_orders DROP CONSTRAINT IF EXISTS market_orders_product_check;
ALTER TABLE market_orders ADD CONSTRAINT market_orders_product_check
  CHECK (product IN ('food', 'material', 'components', 'energy', 'compute'));

INSERT INTO market_prices (product, price, supply, demand, game_day)
SELECT 'food', 20.00, 700, 620, game_day
FROM world_state
WHERE id = 'WORLD'
  AND NOT EXISTS (SELECT 1 FROM market_prices WHERE product = 'food');
