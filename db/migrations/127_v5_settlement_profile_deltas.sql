-- EARTH ACTIVE MIGRATION: V5 Settlement Profile Structural Deltas & Provenance

CREATE TABLE IF NOT EXISTS v5_structural_deltas (
  id TEXT PRIMARY KEY,
  action_type TEXT NOT NULL CHECK (action_type IN (
    'CONSTRUCTION', 'TIER_UPGRADE', 'DEMOLITION', 'RETROFIT',
    'MEMBERSHIP_JOIN', 'MEMBERSHIP_LEAVE', 'MEMBERSHIP_TRANSFER',
    'PUBLIC_BUILDING_CHANGE', 'BUILDING_SUSPEND', 'BUILDING_REACTIVATE',
    'PROFILE_REBUILD'
  )),
  entity_type TEXT NOT NULL CHECK (entity_type IN ('HOUSE', 'CORPORATION', 'BUILDING')),
  entity_id TEXT NOT NULL,
  house_id TEXT REFERENCES houses(id),
  corporation_id TEXT REFERENCES corporations(id),
  building_id TEXT REFERENCES buildings(id),
  delta_footprint_units BIGINT NOT NULL DEFAULT 0,
  delta_building_count INTEGER NOT NULL DEFAULT 0,
  delta_residential_units BIGINT NOT NULL DEFAULT 0,
  delta_productive_units BIGINT NOT NULL DEFAULT 0,
  delta_public_units BIGINT NOT NULL DEFAULT 0,
  before_profile_snapshot JSONB,
  after_profile_snapshot JSONB,
  provenance_source TEXT NOT NULL,
  actor_human_id TEXT,
  correlation_id TEXT NOT NULL,
  game_day BIGINT NOT NULL DEFAULT 1,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS v5_structural_deltas_entity_idx
  ON v5_structural_deltas (entity_type, entity_id, game_day);

CREATE INDEX IF NOT EXISTS v5_structural_deltas_correlation_idx
  ON v5_structural_deltas (correlation_id);
