-- EARTH ACTIVE MIGRATION: durable construction project lifecycle

ALTER TABLE buildings DROP CONSTRAINT IF EXISTS buildings_status_check;
ALTER TABLE buildings ADD CONSTRAINT buildings_status_check
  CHECK (status IN ('ACTIVE', 'UNDER_CONSTRUCTION', 'INACTIVE', 'DESTROYED'));
ALTER TABLE buildings ADD COLUMN IF NOT EXISTS commissioned_game_day BIGINT;
ALTER TABLE buildings ADD COLUMN IF NOT EXISTS last_major_rebuild_game_day BIGINT;

CREATE TABLE IF NOT EXISTS construction_projects (
  id TEXT PRIMARY KEY,
  building_id TEXT NOT NULL UNIQUE REFERENCES buildings(id),
  owner_economic_id TEXT NOT NULL REFERENCES owner_registry(economic_id),
  territory_id TEXT NOT NULL REFERENCES territories(id),
  target_catalog_id TEXT NOT NULL REFERENCES building_catalog(id),
  credit_cost_units BIGINT NOT NULL CHECK (credit_cost_units >= 0),
  resource_cost_units JSONB NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(resource_cost_units) = 'object'),
  started_game_day BIGINT NOT NULL CHECK (started_game_day >= 1),
  expected_completion_game_day BIGINT NOT NULL CHECK (expected_completion_game_day >= started_game_day),
  status TEXT NOT NULL DEFAULT 'IN_PROGRESS' CHECK (status IN ('IN_PROGRESS', 'COMPLETED', 'CANCELLED')),
  cancellation_refund_bps INTEGER NOT NULL DEFAULT 8000 CHECK (cancellation_refund_bps BETWEEN 0 AND 10000),
  completed_game_day BIGINT,
  cancelled_game_day BIGINT,
  correlation_id TEXT NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS construction_projects_due_idx
  ON construction_projects (expected_completion_game_day, status);
CREATE INDEX IF NOT EXISTS construction_projects_owner_idx
  ON construction_projects (owner_economic_id, status, started_game_day DESC);
