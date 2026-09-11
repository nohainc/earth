-- A successor is created during the closing day but becomes the House's
-- active representative only when the next game day starts.
ALTER TABLE humans
  ADD COLUMN IF NOT EXISTS activation_game_day BIGINT NOT NULL DEFAULT 0;

ALTER TABLE humans DROP CONSTRAINT IF EXISTS humans_life_status_check;
ALTER TABLE humans ADD CONSTRAINT humans_life_status_check
  CHECK (life_status IN ('active', 'pending', 'deceased', 'estate'));

CREATE INDEX IF NOT EXISTS humans_pending_activation_idx
  ON humans (activation_game_day, house_id)
  WHERE life_status = 'pending';
