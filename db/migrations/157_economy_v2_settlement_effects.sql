-- Economy V2 Plan 8: calculation/staging layer for daily settlement effects.
-- This table is intentionally UNLOGGED: it is disposable working state, while
-- economic_transactions/economic_entries remain the durable accounting truth.

CREATE SEQUENCE IF NOT EXISTS settlement_effects_id_seq
  AS BIGINT START WITH 1 INCREMENT BY 1 MINVALUE 1;

CREATE UNLOGGED TABLE IF NOT EXISTS settlement_effects (
  id BIGINT PRIMARY KEY DEFAULT nextval('settlement_effects_id_seq'),
  game_day BIGINT NOT NULL CHECK (game_day >= 0),
  phase TEXT NOT NULL CHECK (length(btrim(phase)) > 0),
  shard SMALLINT NOT NULL CHECK (shard BETWEEN 0 AND 63),
  owner_economic_id BIGINT NOT NULL REFERENCES owner_registry(economic_id),
  account_id BIGINT NOT NULL REFERENCES economic_accounts(id),
  asset_id SMALLINT NOT NULL REFERENCES economic_assets(id),
  delta BIGINT NOT NULL CHECK (delta <> 0),
  reason_code TEXT NOT NULL CHECK (length(btrim(reason_code)) > 0),
  source_id TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS settlement_effects_phase_shard_day_idx
  ON settlement_effects (game_day, phase, shard, id);
CREATE INDEX IF NOT EXISTS settlement_effects_owner_day_idx
  ON settlement_effects (owner_economic_id, game_day, asset_id);
CREATE INDEX IF NOT EXISTS settlement_effects_account_day_idx
  ON settlement_effects (account_id, game_day, id);
CREATE INDEX IF NOT EXISTS settlement_effects_source_idx
  ON settlement_effects (source_id, game_day, phase)
  WHERE source_id IS NOT NULL;

COMMENT ON TABLE settlement_effects IS
  'Disposable daily calculation effects; durable accounting is stored in economic_transactions/economic_entries.';
