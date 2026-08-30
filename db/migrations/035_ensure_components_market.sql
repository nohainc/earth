-- Keep the Components commodity available for existing production databases
-- created before the market catalog included it.
INSERT INTO market_prices (product, price, supply, demand, game_day)
SELECT 'components', 118.70, 186, 276, game_day
FROM world_state
WHERE id = 'WORLD'
  AND NOT EXISTS (
    SELECT 1 FROM market_prices WHERE product = 'components'
  );
