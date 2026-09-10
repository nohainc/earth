-- Economy V2 Plan 36: shadow comparison storage.

CREATE TABLE IF NOT EXISTS economy_shadow_openings (
  game_day BIGINT NOT NULL,
  owner_economic_id BIGINT NOT NULL REFERENCES owner_registry(economic_id),
  owner_id TEXT NOT NULL,
  asset_id SMALLINT NOT NULL REFERENCES economic_assets(id),
  legacy_units BIGINT NOT NULL,
  v2_units BIGINT NOT NULL,
  captured_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (game_day, owner_economic_id, asset_id)
);

CREATE TABLE IF NOT EXISTS economy_shadow_reconciliations (
  game_day BIGINT NOT NULL,
  owner_economic_id BIGINT NOT NULL REFERENCES owner_registry(economic_id),
  owner_id TEXT NOT NULL,
  asset_id SMALLINT NOT NULL REFERENCES economic_assets(id),
  legacy_opening_units BIGINT NOT NULL,
  v2_opening_units BIGINT NOT NULL,
  legacy_closing_units BIGINT NOT NULL,
  v2_closing_units BIGINT NOT NULL,
  legacy_delta_units BIGINT NOT NULL,
  v2_delta_units BIGINT NOT NULL,
  difference_units BIGINT NOT NULL,
  difference_kind TEXT NOT NULL CHECK (difference_kind IN ('none','balance','delta')),
  details JSONB NOT NULL DEFAULT '{}'::jsonb,
  reconciled_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (game_day, owner_economic_id, asset_id)
);

CREATE TABLE IF NOT EXISTS economy_shadow_runs (
  game_day BIGINT PRIMARY KEY,
  status TEXT NOT NULL CHECK (status IN ('captured','reconciled','failed')),
  owners_checked BIGINT NOT NULL DEFAULT 0,
  assets_checked BIGINT NOT NULL DEFAULT 0,
  differences BIGINT NOT NULL DEFAULT 0,
  absolute_difference_units NUMERIC(30,0) NOT NULL DEFAULT 0,
  unexplained_difference BOOLEAN NOT NULL DEFAULT FALSE,
  error_message TEXT,
  started_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  completed_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS economy_shadow_reconciliation_difference_idx
  ON economy_shadow_reconciliations (game_day, difference_kind)
  WHERE difference_kind <> 'none';
