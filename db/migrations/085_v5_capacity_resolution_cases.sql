-- EARTH ACTIVE MIGRATION: explicit V5 capacity distress and asset-resolution cases.

CREATE TABLE v5_capacity_resolution_cases (
  id TEXT PRIMARY KEY,
  house_id TEXT NOT NULL REFERENCES houses(id),
  corporation_id TEXT REFERENCES corporations(id),
  trigger_status TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'OPEN' CHECK (status IN ('OPEN','MOTHBALLED','RESOLVED','CANCELLED')),
  opened_game_day BIGINT NOT NULL CHECK (opened_game_day >= 1),
  closed_game_day BIGINT,
  opened_by_human_id TEXT NOT NULL REFERENCES humans(id),
  closed_by_human_id TEXT REFERENCES humans(id),
  resolution_reason TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE UNIQUE INDEX v5_capacity_resolution_open_house_uq ON v5_capacity_resolution_cases(house_id) WHERE status IN ('OPEN','MOTHBALLED');

CREATE TABLE v5_capacity_resolution_assets (
  case_id TEXT NOT NULL REFERENCES v5_capacity_resolution_cases(id),
  building_id TEXT NOT NULL REFERENCES buildings(id),
  footprint_units BIGINT NOT NULL CHECK (footprint_units > 0),
  proceeds_units BIGINT NOT NULL DEFAULT 0 CHECK (proceeds_units >= 0),
  resolved_game_day BIGINT NOT NULL CHECK (resolved_game_day >= 1),
  PRIMARY KEY (case_id, building_id),
  UNIQUE (building_id)
);
CREATE INDEX v5_capacity_resolution_house_idx ON v5_capacity_resolution_cases(house_id, status, opened_game_day DESC);
