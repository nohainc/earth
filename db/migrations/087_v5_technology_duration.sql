-- EARTH ACTIVE MIGRATION: make research duration an explicit catalog authority.
ALTER TABLE technology_catalog
  ADD COLUMN IF NOT EXISTS research_duration_game_days BIGINT NOT NULL DEFAULT 1
  CHECK (research_duration_game_days > 0);
