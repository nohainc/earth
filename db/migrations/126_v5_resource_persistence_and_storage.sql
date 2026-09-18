-- EARTH ACTIVE MIGRATION: V5 Resource Persistence Classes and Storage Modifiers

-- 1. Add persistence_class to resource_behavior_metadata
ALTER TABLE resource_behavior_metadata
  ADD COLUMN IF NOT EXISTS persistence_class TEXT NOT NULL DEFAULT 'DURABLE'
  CHECK (persistence_class IN ('DURABLE', 'PERISHABLE', 'FLOW'));

-- 2. Update resource behavior and persistence classes for standard resources
UPDATE resource_behavior_metadata
   SET persistence_class = 'DURABLE',
       decay_bps_per_day = 0
 WHERE asset_id IN (SELECT id FROM economic_assets WHERE code IN ('MATERIAL', 'COMPONENTS'));

UPDATE resource_behavior_metadata
   SET persistence_class = 'PERISHABLE',
       decay_bps_per_day = 500
 WHERE asset_id IN (SELECT id FROM economic_assets WHERE code = 'FOOD');

UPDATE resource_behavior_metadata
   SET persistence_class = 'FLOW',
       decay_bps_per_day = 10000
 WHERE asset_id IN (SELECT id FROM economic_assets WHERE code IN ('ENERGY', 'COMPUTE'));

-- 3. Owner storage capacities table
CREATE TABLE IF NOT EXISTS owner_storage_capacities (
  id TEXT PRIMARY KEY,
  owner_economic_id TEXT NOT NULL REFERENCES owner_registry(economic_id),
  asset_id INTEGER NOT NULL REFERENCES economic_assets(id),
  storage_type TEXT NOT NULL CHECK (storage_type IN ('BATTERY_STORAGE', 'FOOD_RESERVE', 'COMPUTE_STORAGE', 'GENERIC_STORAGE')),
  storage_capacity_units BIGINT NOT NULL CHECK (storage_capacity_units >= 0),
  decay_reduction_bps INTEGER NOT NULL DEFAULT 0 CHECK (decay_reduction_bps BETWEEN 0 AND 10000),
  source_type TEXT NOT NULL CHECK (source_type IN ('BUILDING', 'TECHNOLOGY', 'POLICY', 'MANUAL')),
  source_id TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'INACTIVE', 'REVOKED')),
  effective_from_game_day BIGINT NOT NULL DEFAULT 1,
  effective_to_game_day BIGINT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS owner_storage_capacities_active_idx
  ON owner_storage_capacities (owner_economic_id, asset_id, status, effective_from_game_day);
