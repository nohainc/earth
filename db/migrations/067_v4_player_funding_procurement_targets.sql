-- EARTH ACTIVE MIGRATION: player funding, procurement disputes, and measurable catch-up targets

ALTER TABLE global_programs ADD COLUMN IF NOT EXISTS matching_authorized_units BIGINT NOT NULL DEFAULT 0 CHECK (matching_authorized_units >= 0);
ALTER TABLE global_programs ADD COLUMN IF NOT EXISTS matching_used_units BIGINT NOT NULL DEFAULT 0 CHECK (matching_used_units >= 0 AND matching_used_units <= matching_authorized_units);
CREATE TABLE IF NOT EXISTS global_program_contributions (
  id TEXT PRIMARY KEY, program_id TEXT NOT NULL REFERENCES global_programs(id), house_id TEXT NOT NULL REFERENCES houses(id),
  amount_units BIGINT NOT NULL CHECK (amount_units > 0), matching_units BIGINT NOT NULL DEFAULT 0 CHECK (matching_units >= 0),
  transaction_id BIGINT NOT NULL, game_day BIGINT NOT NULL, correlation_id TEXT NOT NULL UNIQUE, created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS global_program_contributions_program_idx ON global_program_contributions (program_id, game_day DESC);
ALTER TABLE contract_performance_events DROP CONSTRAINT IF EXISTS contract_performance_events_status_check;
ALTER TABLE contract_performance_events ADD CONSTRAINT contract_performance_events_status_check CHECK (status IN ('DUE','PERFORMED','FAILED','DISPUTED','WAIVED'));
ALTER TABLE contract_performance_events ADD COLUMN IF NOT EXISTS dispute_reason TEXT;
ALTER TABLE contract_performance_events ADD COLUMN IF NOT EXISTS resolved_by_human_id TEXT REFERENCES humans(id);
ALTER TABLE contract_performance_events ADD COLUMN IF NOT EXISTS resolved_game_day BIGINT;
CREATE TABLE IF NOT EXISTS house_catch_up_targets (
  house_id TEXT PRIMARY KEY REFERENCES houses(id), rules_version TEXT NOT NULL, target_game_day BIGINT NOT NULL,
  target_buildings INTEGER NOT NULL CHECK (target_buildings >= 1), target_open_orders INTEGER NOT NULL CHECK (target_open_orders >= 1),
  target_affiliations INTEGER NOT NULL CHECK (target_affiliations >= 1), achieved_game_day BIGINT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP, updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
