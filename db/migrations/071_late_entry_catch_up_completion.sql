-- EARTH ACTIVE MIGRATION: world-age-aware late-entry catch-up completion

ALTER TABLE houses
  ADD COLUMN IF NOT EXISTS created_game_day BIGINT NOT NULL DEFAULT 1
    CHECK (created_game_day >= 1);

ALTER TABLE house_catch_up_targets
  ADD COLUMN IF NOT EXISTS target_territory_opportunities INTEGER NOT NULL DEFAULT 1
    CHECK (target_territory_opportunities >= 1),
  ADD COLUMN IF NOT EXISTS target_sustainable_days INTEGER NOT NULL DEFAULT 7
    CHECK (target_sustainable_days >= 1),
  ADD COLUMN IF NOT EXISTS entry_game_day BIGINT NOT NULL DEFAULT 1
    CHECK (entry_game_day >= 1),
  ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'ACTIVE'
    CHECK (status IN ('ACTIVE', 'COMPLETED', 'EXPIRED'));

CREATE TABLE IF NOT EXISTS house_catch_up_target_events (
  id BIGSERIAL PRIMARY KEY,
  house_id TEXT NOT NULL REFERENCES houses(id),
  milestone_code TEXT NOT NULL CHECK (milestone_code IN (
    'FIRST_PRODUCTIVE_ASSET',
    'FIRST_MARKET_ACTIVITY',
    'FIRST_ORGANIZATION_RELATIONSHIP',
    'FIRST_TERRITORY_OPPORTUNITY',
    'SUSTAINABLE_RESOURCE_BALANCE'
  )),
  achieved_game_day BIGINT NOT NULL CHECK (achieved_game_day >= 1),
  value_units BIGINT NOT NULL DEFAULT 0 CHECK (value_units >= 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (house_id, milestone_code)
);

CREATE INDEX IF NOT EXISTS house_catch_up_target_events_house_idx
  ON house_catch_up_target_events (house_id, achieved_game_day, id);

UPDATE house_catch_up_targets
SET target_territory_opportunities = GREATEST(target_territory_opportunities, 1),
    target_sustainable_days = GREATEST(target_sustainable_days, 7),
    entry_game_day = GREATEST(entry_game_day, 1),
    rules_version = 'catch-up-targets-v2',
    updated_at = CURRENT_TIMESTAMP
WHERE rules_version <> 'catch-up-targets-v2';
