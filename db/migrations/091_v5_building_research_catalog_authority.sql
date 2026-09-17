-- EARTH ACTIVE MIGRATION: V5 building research economics are authored catalog facts, not runtime formulas.
ALTER TABLE building_catalog
  ADD COLUMN IF NOT EXISTS research_credit_units BIGINT,
  ADD COLUMN IF NOT EXISTS research_duration_game_days INTEGER;

UPDATE building_catalog
SET research_credit_units = GREATEST(construction_credit_units * 2, 100000),
    research_duration_game_days = GREATEST(5, CEIL(construction_minutes / 1440.0)::INTEGER + 4)
WHERE research_credit_units IS NULL OR research_duration_game_days IS NULL;

ALTER TABLE building_catalog
  ALTER COLUMN research_credit_units SET NOT NULL,
  ALTER COLUMN research_duration_game_days SET NOT NULL;

ALTER TABLE building_catalog
  ADD CONSTRAINT building_catalog_research_cost_nonnegative
    CHECK (research_credit_units >= 0),
  ADD CONSTRAINT building_catalog_research_duration_positive
    CHECK (research_duration_game_days > 0);
