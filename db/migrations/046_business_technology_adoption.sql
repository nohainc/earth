-- A completed capability is researched globally, but each business chooses
-- when to deploy it at its workplace.
CREATE TABLE IF NOT EXISTS business_technology_adoptions (
  business_id TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  technology_id TEXT NOT NULL REFERENCES technologies(id) ON DELETE CASCADE,
  adopted_by TEXT NOT NULL REFERENCES humans(id),
  adopted_game_day BIGINT NOT NULL,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'withdrawn')),
  PRIMARY KEY (business_id, technology_id)
);

CREATE INDEX IF NOT EXISTS business_technology_adoptions_technology_idx
  ON business_technology_adoptions(technology_id, status);
