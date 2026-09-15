-- EARTH ACTIVE MIGRATION: transparent, effective-dated world conditions
CREATE TABLE IF NOT EXISTS world_conditions (
  id TEXT PRIMARY KEY,
  condition_code TEXT NOT NULL,
  title TEXT NOT NULL,
  description TEXT NOT NULL,
  source_type TEXT NOT NULL CHECK (source_type IN ('EARTH_PROGRAM','GOVERNANCE','SYSTEM_EVENT')),
  source_id TEXT NOT NULL,
  scope_type TEXT NOT NULL CHECK (scope_type IN ('WORLD','TERRITORY','ORGANIZATION')),
  scope_id TEXT,
  effect_type TEXT NOT NULL CHECK (effect_type IN ('SUPPLY_MULTIPLIER','DEMAND_MULTIPLIER','CAPACITY_MULTIPLIER','LABOR_INDEX','CONSTRUCTION_INDEX')),
  target_key TEXT NOT NULL,
  modifier_bps INTEGER NOT NULL CHECK (modifier_bps BETWEEN -5000 AND 5000),
  effective_from_game_day BIGINT NOT NULL CHECK (effective_from_game_day >= 1),
  effective_to_game_day BIGINT CHECK (effective_to_game_day IS NULL OR effective_to_game_day >= effective_from_game_day),
  rules_version TEXT NOT NULL DEFAULT 'world-conditions-v1',
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CHECK ((scope_type = 'WORLD' AND scope_id IS NULL) OR (scope_type <> 'WORLD' AND scope_id IS NOT NULL))
);
CREATE INDEX IF NOT EXISTS world_conditions_effective_idx
  ON world_conditions (effective_from_game_day, effective_to_game_day, scope_type, scope_id);
CREATE INDEX IF NOT EXISTS world_conditions_source_idx
  ON world_conditions (source_type, source_id, id);
