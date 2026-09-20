-- V5 Community visibility is intentionally public and discoverable.
-- Admission remains governed by OPEN versus REQUEST.

UPDATE communities
SET visibility = 'PUBLIC'
WHERE visibility <> 'PUBLIC';

ALTER TABLE communities
  DROP CONSTRAINT IF EXISTS communities_visibility_check;

ALTER TABLE communities
  ADD CONSTRAINT communities_visibility_public_check
  CHECK (visibility = 'PUBLIC');
