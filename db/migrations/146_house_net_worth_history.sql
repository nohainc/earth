-- EARTH ACTIVE MIGRATION: V5 House net-worth history.
-- V5 House net-worth history. Wealth belongs to the House, not to a Human.
-- The current Human is retained only as settlement provenance.
CREATE TABLE IF NOT EXISTS net_worth_snapshots (
  id TEXT PRIMARY KEY,
  house_id TEXT NOT NULL REFERENCES houses(id),
  current_human_id TEXT REFERENCES humans(id),
  game_day BIGINT NOT NULL CHECK (game_day >= 1),
  liquid_credits_units BIGINT NOT NULL DEFAULT 0,
  deposit_principal_units BIGINT NOT NULL DEFAULT 0,
  commodity_valuation_units BIGINT NOT NULL DEFAULT 0,
  buildings_valuation_units BIGINT NOT NULL DEFAULT 0,
  debt_units BIGINT NOT NULL DEFAULT 0,
  total_net_worth_units BIGINT NOT NULL,
  valuation_policy TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (house_id, game_day)
);

CREATE INDEX IF NOT EXISTS net_worth_snapshots_house_day_idx
  ON net_worth_snapshots (house_id, game_day);
