-- V5 House continuity: a House is not extinct merely because its current
-- Human is between lifecycle states. Extinction is an explicit, rare state.

ALTER TABLE houses
  ADD COLUMN IF NOT EXISTS extinction_game_day BIGINT;

ALTER TABLE houses
  DROP CONSTRAINT IF EXISTS houses_status_check;

ALTER TABLE houses
  ADD CONSTRAINT houses_status_check
  CHECK (status IN ('ACTIVE', 'SUSPENDED', 'EXTINCT'));

ALTER TABLE houses
  ADD CONSTRAINT houses_extinction_day_check
  CHECK (extinction_game_day IS NULL OR extinction_game_day >= 1);

CREATE TABLE IF NOT EXISTS house_lifecycle_events (
  id BIGSERIAL PRIMARY KEY,
  house_id TEXT NOT NULL REFERENCES houses(id),
  event_type TEXT NOT NULL CHECK (event_type IN ('HOUSE_EXTINCT')),
  game_day BIGINT NOT NULL CHECK (game_day >= 1),
  reason_code TEXT,
  details JSONB NOT NULL DEFAULT '{}'::JSONB,
  correlation_id TEXT NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS house_lifecycle_events_house_day_idx
  ON house_lifecycle_events (house_id, game_day DESC, id DESC);

COMMENT ON COLUMN houses.extinction_game_day IS
  'Set only by an explicit HOUSE_EXTINCT lifecycle event; never inferred from temporary absence of an active Human.';
