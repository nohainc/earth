-- Death & Continuity V2 Plan 23.
-- Succession transition is a short House policy window, not an asset probate
-- period. Existing House-owned economics remain active during the window.

ALTER TABLE houses
  ADD COLUMN IF NOT EXISTS succession_transition_until_game_day BIGINT NOT NULL DEFAULT 0;

CREATE INDEX IF NOT EXISTS houses_succession_transition_idx
  ON houses(succession_transition_until_game_day)
  WHERE succession_transition_until_game_day > 0;

CREATE OR REPLACE FUNCTION earth_house_in_succession_transition(p_house_id TEXT, p_game_day BIGINT)
RETURNS BOOLEAN
LANGUAGE SQL
STABLE
AS $$
  SELECT COALESCE((
    SELECT succession_transition_until_game_day > p_game_day
      FROM houses
     WHERE id = p_house_id
  ), false);
$$;
