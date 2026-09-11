-- Death, Inheritance & House Continuity V2 Plan 5.
-- Succession belongs to the persistent House, never to another active Human.

CREATE TABLE IF NOT EXISTS house_succession_plans (
  house_id TEXT PRIMARY KEY REFERENCES houses(id) ON DELETE CASCADE,
  successor_name TEXT NOT NULL CHECK (length(btrim(successor_name)) > 0),
  successor_profile JSONB NOT NULL DEFAULT '{}'::JSONB,
  registered_game_day BIGINT NOT NULL,
  status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','USED','CANCELLED')),
  used_game_day BIGINT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Preserve the newest legacy name as the initial House plan. Legacy links to
-- other Humans are deliberately not copied into the V2 plan.
INSERT INTO house_succession_plans (house_id, successor_name, registered_game_day, status)
SELECT h.house_id, MAX(s.successor_name), MAX(s.registered_game_day), 'ACTIVE'
FROM succession_plans s
JOIN humans h ON h.id = s.human_id
WHERE s.successor_name IS NOT NULL
GROUP BY h.house_id
ON CONFLICT (house_id) DO UPDATE
SET successor_name = EXCLUDED.successor_name,
    registered_game_day = EXCLUDED.registered_game_day,
    updated_at = CURRENT_TIMESTAMP;

CREATE INDEX IF NOT EXISTS house_succession_plans_status_idx
  ON house_succession_plans(status, registered_game_day);

COMMENT ON TABLE house_succession_plans IS
  'House-level successor configuration. It creates the next Human in the same House; it never points to another player Human.';

CREATE OR REPLACE FUNCTION earth_house_succession_name(p_house_id TEXT)
RETURNS TEXT
LANGUAGE SQL
STABLE
RETURNS NULL ON NULL INPUT
AS $$
  SELECT successor_name
  FROM house_succession_plans
  WHERE house_id = p_house_id AND status = 'ACTIVE';
$$;
