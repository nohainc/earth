ALTER TABLE humans ADD COLUMN political_eligibility_game_day INTEGER NOT NULL DEFAULT 0;

CREATE INDEX IF NOT EXISTS humans_political_eligibility_idx
  ON humans(life_status, political_eligibility_game_day);
