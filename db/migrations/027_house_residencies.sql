-- EARTH ACTIVE MIGRATION: House residence independent from Organization membership

CREATE TABLE IF NOT EXISTS house_residencies (
  id TEXT PRIMARY KEY,
  house_id TEXT NOT NULL REFERENCES houses(id),
  territory_id TEXT NOT NULL REFERENCES territories(id),
  residency_class TEXT NOT NULL DEFAULT 'PRIMARY' CHECK (residency_class IN ('PRIMARY', 'SECONDARY')),
  status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'ENDED')),
  effective_from_game_day BIGINT NOT NULL CHECK (effective_from_game_day >= 1),
  effective_to_game_day BIGINT,
  correlation_id TEXT NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CHECK (effective_to_game_day IS NULL OR effective_to_game_day >= effective_from_game_day)
);
CREATE UNIQUE INDEX IF NOT EXISTS house_residencies_one_primary_idx
  ON house_residencies (house_id) WHERE status = 'ACTIVE' AND residency_class = 'PRIMARY';
CREATE INDEX IF NOT EXISTS house_residencies_territory_idx
  ON house_residencies (territory_id, status, residency_class);

INSERT INTO house_residencies (id, house_id, territory_id, residency_class, effective_from_game_day, correlation_id)
SELECT 'RES-BACKFILL-' || ha.house_id, ha.house_id, ha.primary_territory_id, 'PRIMARY',
       GREATEST(ha.joined_game_day, 1), 'residency-backfill:' || ha.house_id
FROM house_affiliations ha
WHERE ha.status = 'ACTIVE' AND ha.primary_territory_id IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM house_residencies r WHERE r.house_id = ha.house_id AND r.status = 'ACTIVE' AND r.residency_class = 'PRIMARY')
ON CONFLICT (id) DO NOTHING;
