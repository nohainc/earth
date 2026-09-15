-- EARTH ACTIVE MIGRATION: staged physical resource behavior metadata

CREATE TABLE IF NOT EXISTS resource_behavior_metadata (
  asset_id INTEGER PRIMARY KEY REFERENCES economic_assets(id),
  behavior TEXT NOT NULL CHECK (behavior IN ('STOCK', 'PERISHABLE_STOCK', 'FLOW')),
  storage_limit_units BIGINT CHECK (storage_limit_units IS NULL OR storage_limit_units >= 0),
  delivery_period_game_days BIGINT NOT NULL CHECK (delivery_period_game_days >= 1),
  decay_bps_per_day INTEGER NOT NULL DEFAULT 0 CHECK (decay_bps_per_day BETWEEN 0 AND 10000),
  settlement_mode TEXT NOT NULL CHECK (settlement_mode IN ('INVENTORY', 'EXPLICIT_SINK', 'CAPACITY_ENTITLEMENT')),
  definition_version TEXT NOT NULL,
  UNIQUE (asset_id, definition_version)
);

INSERT INTO resource_behavior_metadata
  (asset_id, behavior, storage_limit_units, delivery_period_game_days, decay_bps_per_day, settlement_mode, definition_version)
SELECT id, seed.behavior, seed.storage_limit_units, seed.delivery_period_game_days,
       seed.decay_bps_per_day, seed.settlement_mode, 'resource-behavior-v1'
  FROM economic_assets asset
  JOIN (VALUES
    ('MATERIAL', 'STOCK', NULL::BIGINT, 1::BIGINT, 0, 'INVENTORY'),
    ('COMPONENTS', 'STOCK', NULL::BIGINT, 1::BIGINT, 0, 'INVENTORY'),
    ('FOOD', 'PERISHABLE_STOCK', NULL::BIGINT, 1::BIGINT, 500, 'EXPLICIT_SINK'),
    ('ENERGY', 'FLOW', NULL::BIGINT, 1::BIGINT, 0, 'CAPACITY_ENTITLEMENT'),
    ('COMPUTE', 'FLOW', NULL::BIGINT, 1::BIGINT, 0, 'CAPACITY_ENTITLEMENT')
  ) AS seed(code, behavior, storage_limit_units, delivery_period_game_days, decay_bps_per_day, settlement_mode)
    ON seed.code = asset.code
 WHERE asset.asset_kind = 'RESOURCE'
ON CONFLICT (asset_id) DO UPDATE SET
  behavior = EXCLUDED.behavior,
  storage_limit_units = EXCLUDED.storage_limit_units,
  delivery_period_game_days = EXCLUDED.delivery_period_game_days,
  decay_bps_per_day = EXCLUDED.decay_bps_per_day,
  settlement_mode = EXCLUDED.settlement_mode,
  definition_version = EXCLUDED.definition_version;
