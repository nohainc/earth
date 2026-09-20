-- EARTH ACTIVE MIGRATION: explainable House automation execution.
-- The action log remains compact and idempotent; daily summaries are the
-- player-facing historical record and may be retained independently.

ALTER TABLE policy_execution_log
  ADD COLUMN IF NOT EXISTS execution_status TEXT NOT NULL DEFAULT 'SKIPPED'
    CHECK (execution_status IN ('NO_ACTION', 'ORDER_PLACED', 'PARTIALLY_FILLED', 'FILLED', 'EXPIRED', 'SKIPPED', 'FAILED')),
  ADD COLUMN IF NOT EXISTS reason_code TEXT,
  ADD COLUMN IF NOT EXISTS market_order_id TEXT REFERENCES market_orders(id),
  ADD COLUMN IF NOT EXISTS market_order_status TEXT,
  ADD COLUMN IF NOT EXISTS evaluated_at_game_minute INTEGER
    CHECK (evaluated_at_game_minute IS NULL OR evaluated_at_game_minute BETWEEN 0 AND 1439),
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP;

CREATE INDEX IF NOT EXISTS policy_execution_log_order_idx
  ON policy_execution_log (market_order_id)
  WHERE market_order_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS policy_execution_daily_summaries (
  id BIGSERIAL PRIMARY KEY,
  house_id TEXT NOT NULL REFERENCES houses(id),
  automation_version_id TEXT REFERENCES house_automation_versions(id),
  game_day BIGINT NOT NULL,
  evaluated_at_game_minute INTEGER NOT NULL CHECK (evaluated_at_game_minute BETWEEN 0 AND 1439),
  no_action_count INTEGER NOT NULL DEFAULT 0 CHECK (no_action_count >= 0),
  order_placed_count INTEGER NOT NULL DEFAULT 0 CHECK (order_placed_count >= 0),
  partially_filled_count INTEGER NOT NULL DEFAULT 0 CHECK (partially_filled_count >= 0),
  filled_count INTEGER NOT NULL DEFAULT 0 CHECK (filled_count >= 0),
  expired_count INTEGER NOT NULL DEFAULT 0 CHECK (expired_count >= 0),
  skipped_count INTEGER NOT NULL DEFAULT 0 CHECK (skipped_count >= 0),
  failed_count INTEGER NOT NULL DEFAULT 0 CHECK (failed_count >= 0),
  reason_codes JSONB NOT NULL DEFAULT '[]'::jsonb CHECK (jsonb_typeof(reason_codes) = 'array'),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (house_id, game_day, automation_version_id)
);

CREATE INDEX IF NOT EXISTS policy_execution_daily_summaries_house_day_idx
  ON policy_execution_daily_summaries (house_id, game_day DESC);
