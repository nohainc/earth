-- EARTH ACTIVE MIGRATION: House FOOD maintenance journal

CREATE TABLE personal_life_maintenance (
  id BIGSERIAL PRIMARY KEY,
  human_id TEXT NOT NULL REFERENCES humans(id),
  house_id TEXT NOT NULL REFERENCES houses(id),
  game_day BIGINT NOT NULL CHECK (game_day >= 0),
  food_required_units BIGINT NOT NULL CHECK (food_required_units >= 0),
  food_consumed_units BIGINT NOT NULL CHECK (food_consumed_units >= 0),
  food_shortfall_units BIGINT NOT NULL CHECK (food_shortfall_units >= 0),
  status TEXT NOT NULL CHECK (status IN ('FED', 'PARTIAL', 'UNFED')),
  shortfall_notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (human_id, game_day),
  CHECK (food_consumed_units <= food_required_units),
  CHECK (food_shortfall_units = food_required_units - food_consumed_units)
);

CREATE INDEX personal_life_maintenance_house_day_idx
  ON personal_life_maintenance (house_id, game_day DESC);
