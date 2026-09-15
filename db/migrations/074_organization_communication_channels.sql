-- EARTH ACTIVE MIGRATION: organization-scoped communication channels

ALTER TABLE comm_channels
  DROP CONSTRAINT IF EXISTS comm_channels_scope_check;

ALTER TABLE comm_channels
  ADD CONSTRAINT comm_channels_scope_check
  CHECK (scope IN ('global', 'city', 'corporation', 'community', 'organization', 'direct'));

CREATE INDEX IF NOT EXISTS comm_channels_organization_scope_idx
  ON comm_channels (scope_id, created_at)
  WHERE scope = 'organization';

INSERT INTO comm_channels (id, scope, scope_id, name, description)
SELECT 'channel-organization-' || o.id, 'organization', o.id, o.name || ' Commons',
       'Shared channel for members of ' || o.name
  FROM organizations o
 WHERE o.status = 'ACTIVE'
ON CONFLICT (id) DO NOTHING;
