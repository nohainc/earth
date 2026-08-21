-- Migration 048: corporation admission policy and explicit capital city.

ALTER TABLE corporations
  ADD COLUMN IF NOT EXISTS capital_city_id TEXT REFERENCES cities(id),
  ADD COLUMN IF NOT EXISTS admission_policy TEXT NOT NULL DEFAULT 'open'
    CHECK (admission_policy IN ('open', 'approval'));

UPDATE corporations c
SET capital_city_id = source.city_id
FROM (
  SELECT corporation_id, MIN(id) AS city_id
  FROM cities
  WHERE corporation_id IS NOT NULL
  GROUP BY corporation_id
) AS source
WHERE c.id = source.corporation_id
  AND c.capital_city_id IS NULL;

CREATE TABLE IF NOT EXISTS corporation_membership_requests (
  id TEXT PRIMARY KEY,
  corporation_id TEXT NOT NULL REFERENCES corporations(id),
  human_id TEXT NOT NULL REFERENCES humans(id),
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'cancelled')),
  requested_game_day BIGINT NOT NULL,
  decided_game_day BIGINT,
  decided_by TEXT REFERENCES humans(id),
  UNIQUE (corporation_id, human_id, status)
);

CREATE INDEX IF NOT EXISTS corporation_membership_requests_corporation_idx
  ON corporation_membership_requests(corporation_id, status, requested_game_day);

CREATE INDEX IF NOT EXISTS corporation_membership_requests_human_idx
  ON corporation_membership_requests(human_id, status, requested_game_day);
