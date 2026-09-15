-- EARTH ACTIVE MIGRATION: explicit, time-bounded Territory use rights

CREATE TABLE IF NOT EXISTS territory_rights (
  id TEXT PRIMARY KEY,
  territory_id TEXT NOT NULL REFERENCES territories(id),
  holder_type TEXT NOT NULL CHECK (holder_type IN ('HOUSE','ORGANIZATION')),
  holder_id TEXT NOT NULL,
  slot_class TEXT NOT NULL CHECK (slot_class IN ('PRIVATE','PUBLIC')),
  slot_quantity BIGINT NOT NULL CHECK (slot_quantity > 0),
  rent_per_game_day_units BIGINT NOT NULL CHECK (rent_per_game_day_units > 0),
  effective_from_game_day BIGINT NOT NULL CHECK (effective_from_game_day >= 1),
  effective_to_game_day BIGINT,
  transferability TEXT NOT NULL DEFAULT 'NON_TRANSFERABLE' CHECK (transferability IN ('NON_TRANSFERABLE','TRANSFERABLE')),
  pricing_version TEXT NOT NULL DEFAULT 'territory-lease-v1',
  status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','HOLDOVER','EXPIRED','RELEASED')),
  acquired_transaction_id BIGINT REFERENCES economic_transactions(id),
  released_game_day BIGINT,
  correlation_id TEXT NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CHECK (effective_to_game_day IS NULL OR effective_to_game_day >= effective_from_game_day),
  CHECK (released_game_day IS NULL OR released_game_day >= effective_from_game_day)
);

CREATE UNIQUE INDEX IF NOT EXISTS territory_rights_active_holder_idx
  ON territory_rights (territory_id, holder_type, holder_id, slot_class)
  WHERE status IN ('ACTIVE','HOLDOVER') AND effective_to_game_day IS NULL;
CREATE INDEX IF NOT EXISTS territory_rights_territory_status_idx
  ON territory_rights (territory_id, status, effective_from_game_day);
CREATE INDEX IF NOT EXISTS territory_rights_holder_idx
  ON territory_rights (holder_type, holder_id, status);

CREATE TABLE IF NOT EXISTS territory_lease_payments (
  id TEXT PRIMARY KEY,
  right_id TEXT NOT NULL REFERENCES territory_rights(id),
  territory_id TEXT NOT NULL REFERENCES territories(id),
  holder_type TEXT NOT NULL CHECK (holder_type IN ('HOUSE','ORGANIZATION')),
  holder_id TEXT NOT NULL,
  game_day BIGINT NOT NULL CHECK (game_day >= 1),
  amount_units BIGINT NOT NULL CHECK (amount_units > 0),
  beneficiary_economic_id TEXT NOT NULL REFERENCES owner_registry(economic_id),
  economic_transaction_id BIGINT REFERENCES economic_transactions(id),
  status TEXT NOT NULL DEFAULT 'PAID' CHECK (status IN ('PAID','ARREARS','WAIVED')),
  correlation_id TEXT NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (right_id, game_day)
);

CREATE TABLE IF NOT EXISTS territory_right_events (
  id TEXT PRIMARY KEY,
  right_id TEXT NOT NULL REFERENCES territory_rights(id),
  event_type TEXT NOT NULL CHECK (event_type IN ('ACQUIRED','RENEWED','RELEASED','EXPIRED','HOLDOVER')),
  game_day BIGINT NOT NULL CHECK (game_day >= 1),
  previous_status TEXT,
  next_status TEXT NOT NULL,
  correlation_id TEXT NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE construction_projects
  ADD COLUMN IF NOT EXISTS territory_right_id TEXT REFERENCES territory_rights(id);
ALTER TABLE buildings
  ADD COLUMN IF NOT EXISTS territory_right_id TEXT REFERENCES territory_rights(id);

CREATE INDEX IF NOT EXISTS construction_projects_right_idx ON construction_projects (territory_right_id);
CREATE INDEX IF NOT EXISTS buildings_right_idx ON buildings (territory_right_id);
