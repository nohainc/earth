-- EARTH ACTIVE MIGRATION: versioned Organization charters and validated presets

CREATE TABLE IF NOT EXISTS charter_templates (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  archetype TEXT NOT NULL,
  schema_version INTEGER NOT NULL CHECK (schema_version > 0),
  charter JSONB NOT NULL CHECK (jsonb_typeof(charter) = 'object'),
  status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'RETIRED'))
);
CREATE TABLE IF NOT EXISTS organization_charter_versions (
  id TEXT PRIMARY KEY,
  organization_id TEXT NOT NULL REFERENCES organizations(id),
  version INTEGER NOT NULL CHECK (version > 0),
  template_id TEXT REFERENCES charter_templates(id),
  charter JSONB NOT NULL CHECK (jsonb_typeof(charter) = 'object'),
  schema_version INTEGER NOT NULL CHECK (schema_version > 0),
  effective_from_game_day BIGINT NOT NULL CHECK (effective_from_game_day >= 1),
  effective_to_game_day BIGINT,
  status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'SUPERSEDED')),
  correlation_id TEXT NOT NULL UNIQUE,
  created_by_human_id TEXT NOT NULL REFERENCES humans(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (organization_id, version),
  CHECK (effective_to_game_day IS NULL OR effective_to_game_day >= effective_from_game_day)
);
CREATE UNIQUE INDEX IF NOT EXISTS organization_charters_one_current_idx
  ON organization_charter_versions (organization_id) WHERE status = 'ACTIVE' AND effective_to_game_day IS NULL;
CREATE INDEX IF NOT EXISTS organization_charters_history_idx
  ON organization_charter_versions (organization_id, effective_from_game_day DESC, version DESC);

INSERT INTO charter_templates (id, name, archetype, schema_version, charter)
VALUES
 ('CHARTER-COMPANY-V1', 'Company', 'CORPORATION', 1, '{"membershipModel":"OPEN","ownershipModel":"ORGANIZATION","votingMethod":"HOUSE_ONE_VOTE","authorityLimits":{"canOwnAssets":true,"canGovernTerritory":true},"surplusPolicy":"RETAIN_AND_DISTRIBUTE","capabilities":["ECONOMIC_OWNER","GOVERNANCE","TERRITORY_GOVERNOR"],"dissolutionPolicy":"GOVERNANCE_VOTE"}'::jsonb),
 ('CHARTER-COOPERATIVE-V1', 'Cooperative', 'COOPERATIVE', 1, '{"membershipModel":"REQUEST","ownershipModel":"HOUSE_COLLECTIVE","votingMethod":"HOUSE_ONE_VOTE","authorityLimits":{"canOwnAssets":true,"canGovernTerritory":false},"surplusPolicy":"MEMBER_DIVIDEND","capabilities":["ECONOMIC_OWNER","GOVERNANCE"],"dissolutionPolicy":"UNANIMOUS_MEMBER_VOTE"}'::jsonb),
 ('CHARTER-RESEARCH-V1', 'Research Guild', 'RESEARCH', 1, '{"membershipModel":"INVITE_ONLY","ownershipModel":"ORGANIZATION","votingMethod":"HOUSE_ONE_VOTE","authorityLimits":{"canOwnAssets":true,"canGovernTerritory":false},"surplusPolicy":"REINVEST_RESEARCH","capabilities":["ECONOMIC_OWNER","GOVERNANCE","RESEARCH"],"dissolutionPolicy":"GOVERNANCE_VOTE"}'::jsonb),
 ('CHARTER-TERRITORIAL-V1', 'Territorial Council', 'PUBLIC_BODY', 1, '{"membershipModel":"OPEN","ownershipModel":"PUBLIC","votingMethod":"HOUSE_ONE_VOTE","authorityLimits":{"canOwnAssets":true,"canGovernTerritory":true},"surplusPolicy":"PUBLIC_SERVICES","capabilities":["GOVERNANCE","TERRITORY_GOVERNOR","PUBLIC_PROJECTS"],"dissolutionPolicy":"EARTH_REVIEW"}'::jsonb)
ON CONFLICT (id) DO NOTHING;

-- Existing organizations enter V4 with an explicit constitutional source of truth.
INSERT INTO organization_charter_versions
  (id, organization_id, version, template_id, charter, schema_version,
   effective_from_game_day, status, correlation_id, created_by_human_id)
SELECT 'CHARTER-' || o.id || '-V1', o.id, 1, t.id, t.charter, t.schema_version,
       GREATEST(o.created_game_day, 1), 'ACTIVE', 'charter-backfill:' || o.id || ':v1',
       h.id
FROM organizations o
JOIN charter_templates t ON t.archetype = CASE
  WHEN o.archetype IN ('CORPORATION', 'COOPERATIVE', 'RESEARCH', 'PUBLIC_BODY') THEN o.archetype
  WHEN o.archetype = 'COMMUNITY' THEN 'COOPERATIVE'
  ELSE 'CORPORATION'
END
JOIN humans h ON h.house_id = o.founder_house_id AND h.status = 'ACTIVE'
WHERE NOT EXISTS (SELECT 1 FROM organization_charter_versions v WHERE v.organization_id = o.id);
