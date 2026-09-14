-- EARTH ACTIVE MIGRATION: Community V2 name lifecycle hardening
-- Temporary reconciliation migration; fold into the next final baseline before production freeze.

ALTER TABLE communities
  DROP CONSTRAINT IF EXISTS communities_normalized_name_key;

CREATE UNIQUE INDEX communities_active_normalized_name_uq
  ON communities (normalized_name)
  WHERE status = 'ACTIVE';
