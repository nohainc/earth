-- EARTH ACTIVE MIGRATION: make Territory governance explicit and replaceable

CREATE TABLE IF NOT EXISTS territory_governance (
  territory_id TEXT PRIMARY KEY REFERENCES territories(id),
  governing_institution_id TEXT NOT NULL REFERENCES institutions(id),
  effective_from_game_day BIGINT NOT NULL CHECK (effective_from_game_day >= 1),
  effective_to_game_day BIGINT,
  status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'ENDED')),
  correlation_id TEXT NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CHECK (effective_to_game_day IS NULL OR effective_to_game_day >= effective_from_game_day)
);

INSERT INTO territory_governance (territory_id, governing_institution_id, effective_from_game_day, correlation_id)
SELECT t.id, t.corporation_id, t.created_game_day, 'territory-governance-backfill:' || t.id
FROM territories t
WHERE NOT EXISTS (SELECT 1 FROM territory_governance g WHERE g.territory_id = t.id);

CREATE INDEX IF NOT EXISTS territory_governance_institution_idx
  ON territory_governance (governing_institution_id, status, effective_from_game_day);
