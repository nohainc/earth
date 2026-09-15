-- EARTH ACTIVE MIGRATION: map legacy Corporation and Community identities into Organizations

CREATE TABLE IF NOT EXISTS organization_legacy_map (
  legacy_type TEXT NOT NULL CHECK (legacy_type IN ('CORPORATION', 'COMMUNITY')),
  legacy_id TEXT NOT NULL,
  organization_id TEXT NOT NULL UNIQUE REFERENCES organizations(id),
  migrated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (legacy_type, legacy_id)
);

INSERT INTO organizations (id, name, archetype, join_policy, status, founder_house_id, created_game_day, metadata)
SELECT 'ORG-CORP-' || c.id, i.name, 'CORPORATION', CASE WHEN c.admission_policy = 'OPEN' THEN 'OPEN' ELSE 'REQUEST' END,
       CASE WHEN c.status = 'DISSOLVED' THEN 'DISSOLVED' ELSE 'ACTIVE' END,
       COALESCE((SELECT ha.house_id FROM house_affiliations ha WHERE ha.corporation_id = c.id ORDER BY ha.joined_game_day, ha.id LIMIT 1), (SELECT id FROM houses ORDER BY id LIMIT 1)),
       c.created_game_day, jsonb_build_object('legacy_type', 'CORPORATION', 'legacy_id', c.id)
FROM corporations c JOIN institutions i ON i.id = c.id
WHERE EXISTS (SELECT 1 FROM houses)
ON CONFLICT (id) DO NOTHING;
INSERT INTO organization_legacy_map (legacy_type, legacy_id, organization_id)
SELECT 'CORPORATION', c.id, 'ORG-CORP-' || c.id FROM corporations c
ON CONFLICT (legacy_type, legacy_id) DO NOTHING;

INSERT INTO organizations (id, name, archetype, join_policy, status, founder_house_id, created_game_day, metadata)
SELECT 'ORG-COMM-' || c.id, c.name, 'COMMUNITY', c.join_policy,
       CASE WHEN c.status = 'DISBANDED' THEN 'DISSOLVED' ELSE 'ACTIVE' END,
       c.founder_house_id, GREATEST(c.created_game_day, 1), jsonb_build_object('legacy_type', 'COMMUNITY', 'legacy_id', c.id)
FROM communities c
ON CONFLICT (id) DO NOTHING;
INSERT INTO organization_legacy_map (legacy_type, legacy_id, organization_id)
SELECT 'COMMUNITY', c.id, 'ORG-COMM-' || c.id FROM communities c
ON CONFLICT (legacy_type, legacy_id) DO NOTHING;

INSERT INTO organization_memberships (organization_id, house_id, role_code, status, joined_game_day, left_game_day, correlation_id)
SELECT 'ORG-CORP-' || ha.corporation_id, ha.house_id, 'MEMBER', ha.status, GREATEST(ha.joined_game_day, 1), ha.left_game_day,
       'organization-legacy:CORPORATION:' || ha.corporation_id || ':' || ha.house_id
FROM house_affiliations ha
ON CONFLICT (correlation_id) DO NOTHING;
INSERT INTO organization_memberships (organization_id, house_id, role_code, status, joined_game_day, correlation_id)
SELECT 'ORG-COMM-' || cm.community_id, cm.house_id,
       CASE cm.role WHEN 'OWNER' THEN 'FOUNDER' WHEN 'MODERATOR' THEN 'ADMIN' ELSE 'MEMBER' END,
       cm.status, GREATEST(cm.joined_game_day, 1), 'organization-legacy:COMMUNITY:' || cm.community_id || ':' || cm.house_id
FROM community_memberships cm
ON CONFLICT (correlation_id) DO NOTHING;

INSERT INTO organization_capabilities (organization_id, capability_code, effective_from_game_day, rules_version)
SELECT 'ORG-CORP-' || c.id, capability, GREATEST(c.created_game_day, 1), 'organization-legacy-v1'
FROM corporations c CROSS JOIN unnest(ARRAY['ECONOMIC_OWNER', 'GOVERNANCE', 'TERRITORY_GOVERNOR']::TEXT[]) capability
ON CONFLICT (organization_id, capability_code) DO NOTHING;
INSERT INTO organization_capabilities (organization_id, capability_code, effective_from_game_day, rules_version)
SELECT 'ORG-COMM-' || c.id, 'GOVERNANCE', GREATEST(c.created_game_day, 1), 'organization-legacy-v1'
FROM communities c ON CONFLICT (organization_id, capability_code) DO NOTHING;

INSERT INTO organization_membership_requests (id, organization_id, house_id, status, requested_game_day, decided_game_day, correlation_id)
SELECT 'ORGREQ-LEGACY-' || r.id, 'ORG-COMM-' || r.community_id, r.house_id,
       r.status, GREATEST(r.requested_game_day, 1),
       CASE WHEN r.decided_at IS NULL THEN NULL ELSE GREATEST(r.requested_game_day, 1) END,
       'organization-legacy-request:' || r.id
FROM community_membership_requests r
ON CONFLICT (id) DO NOTHING;
