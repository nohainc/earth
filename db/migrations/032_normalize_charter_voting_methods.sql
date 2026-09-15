-- EARTH ACTIVE MIGRATION: normalize legacy charter vote naming to V4 methods

UPDATE charter_templates
SET charter = jsonb_set(charter, '{votingMethod}', '"ONE_HOUSE_ONE_VOTE"'::jsonb)
WHERE charter->>'votingMethod' = 'HOUSE_ONE_VOTE';
UPDATE organization_charter_versions
SET charter = jsonb_set(charter, '{votingMethod}', '"ONE_HOUSE_ONE_VOTE"'::jsonb)
WHERE charter->>'votingMethod' = 'HOUSE_ONE_VOTE';
