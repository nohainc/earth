-- EARTH ACTIVE MIGRATION: explicit jurisdiction/nexus basis for recurring rules

ALTER TABLE tax_rule_versions ADD COLUMN IF NOT EXISTS nexus_type TEXT NOT NULL DEFAULT 'RESIDENCE' CHECK (nexus_type IN ('RESIDENCE','ASSET_LOCATION','MEMBERSHIP','TRANSACTION','EARTH'));
ALTER TABLE financial_obligations ADD COLUMN IF NOT EXISTS nexus_type TEXT NOT NULL DEFAULT 'RESIDENCE' CHECK (nexus_type IN ('RESIDENCE','ASSET_LOCATION','MEMBERSHIP','TRANSACTION','EARTH'));
ALTER TABLE organization_contracts ADD COLUMN IF NOT EXISTS nexus_type TEXT NOT NULL DEFAULT 'TRANSACTION' CHECK (nexus_type IN ('RESIDENCE','ASSET_LOCATION','MEMBERSHIP','TRANSACTION','EARTH'));

CREATE TABLE IF NOT EXISTS asset_jurisdictions (
  id TEXT PRIMARY KEY,
  asset_type TEXT NOT NULL CHECK (asset_type IN ('BUILDING','CONSTRUCTION_PROJECT','ORGANIZATION_CONTRACT','OWNERSHIP_POSITION')),
  asset_id TEXT NOT NULL,
  territory_id TEXT NOT NULL REFERENCES territories(id),
  effective_from_game_day BIGINT NOT NULL,
  effective_to_game_day BIGINT,
  status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','ENDED')),
  correlation_id TEXT NOT NULL UNIQUE,
  CHECK (effective_to_game_day IS NULL OR effective_to_game_day >= effective_from_game_day)
);
CREATE UNIQUE INDEX IF NOT EXISTS asset_jurisdictions_current_idx ON asset_jurisdictions (asset_type, asset_id) WHERE status = 'ACTIVE' AND effective_to_game_day IS NULL;
