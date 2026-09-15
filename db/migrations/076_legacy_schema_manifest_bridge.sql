-- EARTH ACTIVE MIGRATION: bridge older production schemas to the V4 manifest.
-- This migration is additive and keeps existing data and applied history intact.

ALTER TABLE corporations
  ADD COLUMN IF NOT EXISTS charter_version TEXT NOT NULL DEFAULT 'corporation-charter-v1';

CREATE TABLE IF NOT EXISTS territory_capacity_state (
  territory_id TEXT NOT NULL REFERENCES territories(id),
  game_day BIGINT NOT NULL CHECK (game_day >= 1),
  active_house_count BIGINT NOT NULL DEFAULT 0 CHECK (active_house_count >= 0),
  house_capacity BIGINT NOT NULL DEFAULT 0 CHECK (house_capacity >= 0),
  population_capacity BIGINT NOT NULL DEFAULT 0 CHECK (population_capacity >= 0),
  private_slot_capacity BIGINT NOT NULL DEFAULT 0 CHECK (private_slot_capacity >= 0),
  public_slot_capacity BIGINT NOT NULL DEFAULT 0 CHECK (public_slot_capacity >= 0),
  private_slots_used BIGINT NOT NULL DEFAULT 0 CHECK (private_slots_used >= 0),
  public_slots_used BIGINT NOT NULL DEFAULT 0 CHECK (public_slots_used >= 0),
  housing_capacity BIGINT NOT NULL DEFAULT 0 CHECK (housing_capacity >= 0),
  health_capacity BIGINT NOT NULL DEFAULT 0 CHECK (health_capacity >= 0),
  energy_capacity BIGINT NOT NULL DEFAULT 0 CHECK (energy_capacity >= 0),
  connectivity_capacity BIGINT NOT NULL DEFAULT 0 CHECK (connectivity_capacity >= 0),
  service_capacity BIGINT NOT NULL DEFAULT 0 CHECK (service_capacity >= 0),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (territory_id, game_day)
);

CREATE INDEX IF NOT EXISTS territory_capacity_state_game_day_idx
  ON territory_capacity_state (game_day, territory_id);

ALTER TABLE market_instruments
  ADD COLUMN IF NOT EXISTS instrument_type TEXT NOT NULL DEFAULT 'SPOT',
  ADD COLUMN IF NOT EXISTS lot_size_units BIGINT NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS price_tick_units BIGINT NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS rules_version TEXT NOT NULL DEFAULT 'spot-market-v1';

ALTER TABLE market_orders
  ADD COLUMN IF NOT EXISTS buyer_fee_bps INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS seller_fee_bps INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS correlation_id TEXT;

UPDATE market_orders
   SET correlation_id = 'legacy-market-order:' || id
 WHERE correlation_id IS NULL;

ALTER TABLE market_orders
  ALTER COLUMN correlation_id SET NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS market_orders_correlation_id_idx
  ON market_orders (correlation_id);

CREATE TABLE IF NOT EXISTS market_order_reservations (
  id BIGSERIAL PRIMARY KEY,
  order_id TEXT NOT NULL REFERENCES market_orders(id),
  escrow_account_id BIGINT NOT NULL REFERENCES economic_accounts(id),
  asset_id INTEGER NOT NULL REFERENCES economic_assets(id),
  reserved_units BIGINT NOT NULL CHECK (reserved_units > 0),
  remaining_units BIGINT NOT NULL CHECK (remaining_units >= 0 AND remaining_units <= reserved_units),
  status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','CONSUMED','RELEASED')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (order_id, asset_id)
);

ALTER TABLE proposals
  ADD COLUMN IF NOT EXISTS target_type TEXT NOT NULL DEFAULT 'INSTITUTION',
  ADD COLUMN IF NOT EXISTS target_id TEXT,
  ADD COLUMN IF NOT EXISTS target_value JSONB NOT NULL DEFAULT '{}'::jsonb;

CREATE UNIQUE INDEX IF NOT EXISTS territories_one_active_primary_idx
  ON territories (corporation_id)
 WHERE is_primary = TRUE AND status = 'ACTIVE';

CREATE UNIQUE INDEX IF NOT EXISTS house_affiliations_one_active_idx
  ON house_affiliations (house_id)
 WHERE status = 'ACTIVE';
