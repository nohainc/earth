-- EARTH ACTIVE MIGRATION: fractional ownership positions and capitalization history

CREATE TABLE IF NOT EXISTS asset_ownership_positions (
  id TEXT PRIMARY KEY,
  asset_type TEXT NOT NULL CHECK (asset_type IN ('BUILDING','CONSTRUCTION_PROJECT','ORGANIZATION')),
  asset_id TEXT NOT NULL,
  holder_type TEXT NOT NULL CHECK (holder_type IN ('HOUSE','ORGANIZATION')),
  holder_id TEXT NOT NULL,
  ownership_class TEXT NOT NULL DEFAULT 'COMMON' CHECK (ownership_class IN ('COMMON','PREFERRED','COOPERATIVE')),
  units BIGINT NOT NULL CHECK (units > 0),
  effective_from_game_day BIGINT NOT NULL,
  effective_to_game_day BIGINT,
  status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','SUPERSEDED')),
  correlation_id TEXT NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CHECK (effective_to_game_day IS NULL OR effective_to_game_day >= effective_from_game_day)
);
CREATE UNIQUE INDEX IF NOT EXISTS asset_ownership_positions_holder_idx
  ON asset_ownership_positions (asset_type, asset_id, holder_type, holder_id, ownership_class)
  WHERE status = 'ACTIVE' AND effective_to_game_day IS NULL;
CREATE INDEX IF NOT EXISTS asset_ownership_positions_asset_idx
  ON asset_ownership_positions (asset_type, asset_id, status, effective_from_game_day);
CREATE TABLE IF NOT EXISTS capitalization_events (
  id TEXT PRIMARY KEY,
  asset_type TEXT NOT NULL,
  asset_id TEXT NOT NULL,
  organization_id TEXT NOT NULL REFERENCES organizations(id),
  investor_type TEXT NOT NULL CHECK (investor_type IN ('HOUSE','ORGANIZATION')),
  investor_id TEXT NOT NULL,
  units BIGINT NOT NULL CHECK (units > 0),
  price_units BIGINT NOT NULL CHECK (price_units > 0),
  ownership_class TEXT NOT NULL,
  economic_transaction_id BIGINT,
  game_day BIGINT NOT NULL,
  correlation_id TEXT NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS capitalization_events_org_day_idx ON capitalization_events (organization_id, game_day DESC);
CREATE TABLE IF NOT EXISTS ownership_distributions (
  id TEXT PRIMARY KEY,
  asset_type TEXT NOT NULL,
  asset_id TEXT NOT NULL,
  organization_id TEXT NOT NULL REFERENCES organizations(id),
  total_units BIGINT NOT NULL CHECK (total_units > 0),
  amount_units BIGINT NOT NULL CHECK (amount_units > 0),
  status TEXT NOT NULL DEFAULT 'DECLARED' CHECK (status IN ('DECLARED','PAID','CANCELLED')),
  game_day BIGINT NOT NULL,
  correlation_id TEXT NOT NULL UNIQUE
);

-- Existing legal owners become the initial 100%-position; the legal owner
-- remains on buildings and continues to drive operational settlement.
INSERT INTO asset_ownership_positions (id, asset_type, asset_id, holder_type, holder_id, units, effective_from_game_day, correlation_id)
SELECT 'OWN-' || b.id || '-LEGAL', 'BUILDING', b.id, o.owner_type, o.id, 10000, b.started_game_day, 'ownership-backfill:' || b.id
FROM buildings b JOIN owner_registry o ON o.economic_id = b.owner_economic_id
WHERE o.owner_type IN ('HOUSE','ORGANIZATION')
ON CONFLICT (correlation_id) DO NOTHING;
