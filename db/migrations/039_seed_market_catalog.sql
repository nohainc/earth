-- Keep the market catalog complete for existing installations.
-- Orders may remain open until a later batch settlement, but every supported
-- product needs a price row so it can be displayed and settled.
INSERT INTO market_prices (product, price, supply, demand, game_day)
SELECT seed.product, seed.price, seed.supply, seed.demand, world.game_day
FROM (VALUES
  ('food', 20.00, 700, 620),
  ('material', 45.00, 1200, 900),
  ('components', 118.70, 186, 276),
  ('energy', 30.00, 900, 820),
  ('compute', 60.00, 480, 360)
) AS seed(product, price, supply, demand)
CROSS JOIN world_state AS world
WHERE world.id = 'WORLD'
ON CONFLICT (product) DO NOTHING;
