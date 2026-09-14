-- EARTH ACTIVE MIGRATION: market state and genesis reference price

ALTER TABLE market_instruments
  ADD COLUMN genesis_reference_price_units BIGINT NOT NULL DEFAULT 1 CHECK (genesis_reference_price_units > 0);
