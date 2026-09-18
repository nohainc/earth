-- EARTH ACTIVE MIGRATION: V5 Scale Capabilities and Upgrades

CREATE TABLE IF NOT EXISTS earth_scale_capabilities (
  scale_capability TEXT PRIMARY KEY CHECK (scale_capability IN ('SCALE_COMMERCIAL', 'SCALE_INDUSTRIAL', 'SCALE_STRATEGIC')),
  unlocked_game_day BIGINT NOT NULL DEFAULT 1,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
