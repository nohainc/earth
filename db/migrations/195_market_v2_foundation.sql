-- Market V2 foundation: one instrument catalog for spot and delivery futures.
CREATE TABLE IF NOT EXISTS market_instruments (
  id TEXT PRIMARY KEY,
  symbol TEXT NOT NULL UNIQUE,
  instrument_type TEXT NOT NULL CHECK (instrument_type IN ('SPOT', 'DELIVERY_FUTURE')),
  base_asset_id SMALLINT NOT NULL REFERENCES economic_assets(id),
  quote_asset_id SMALLINT NOT NULL REFERENCES economic_assets(id),
  expiry_total_game_minute BIGINT,
  lot_size_units BIGINT NOT NULL CHECK (lot_size_units > 0),
  price_tick_units BIGINT NOT NULL CHECK (price_tick_units > 0),
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('draft', 'active', 'halted', 'expired')),
  rules_version TEXT NOT NULL DEFAULT 'market-v2',
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CHECK (instrument_type = 'SPOT' OR expiry_total_game_minute IS NOT NULL),
  CHECK (instrument_type = 'DELIVERY_FUTURE' OR expiry_total_game_minute IS NULL)
);

CREATE INDEX IF NOT EXISTS market_instruments_active_symbol_idx
  ON market_instruments (status, symbol);
CREATE INDEX IF NOT EXISTS market_instruments_expiry_idx
  ON market_instruments (expiry_total_game_minute)
  WHERE instrument_type = 'DELIVERY_FUTURE';

INSERT INTO market_instruments
  (id, symbol, instrument_type, base_asset_id, quote_asset_id,
   expiry_total_game_minute, lot_size_units, price_tick_units, status, rules_version)
VALUES
  ('SPOT-MATERIAL', 'SPOT-MATERIAL', 'SPOT', 2, 1, NULL, 1000000, 1, 'active', 'market-v2'),
  ('SPOT-COMPONENTS', 'SPOT-COMPONENTS', 'SPOT', 3, 1, NULL, 1000000, 1, 'active', 'market-v2'),
  ('SPOT-ENERGY', 'SPOT-ENERGY', 'SPOT', 4, 1, NULL, 1000000, 1, 'active', 'market-v2'),
  ('SPOT-COMPUTE', 'SPOT-COMPUTE', 'SPOT', 5, 1, NULL, 1000000, 1, 'active', 'market-v2'),
  ('SPOT-FOOD', 'SPOT-FOOD', 'SPOT', 6, 1, NULL, 1000000, 1, 'active', 'market-v2')
ON CONFLICT (id) DO NOTHING;
