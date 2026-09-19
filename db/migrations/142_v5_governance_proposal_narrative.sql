-- EARTH ACTIVE MIGRATION: Persist V5 proposal narrative as first-class data.

ALTER TABLE v5_governance_proposals
  ADD COLUMN title TEXT,
  ADD COLUMN body TEXT;

-- Proposal creation events are the only historical source for narrative text.
-- The event journal stores details as Nano Markup, so recover the body when it
-- is represented on one line. Proposals without a recoverable event body keep
-- a NULL body rather than inventing player-facing text.
UPDATE v5_governance_proposals p
SET title = e.title,
    body = NULLIF(substring(e.details FROM E'\n    body ([^\n]*)'), '')
FROM game_events e
WHERE p.title IS NULL
  AND e.event_type = 'V5_POLICY_PROPOSAL_CREATED'
  AND e.details LIKE '%proposalId ' || p.id || '%';

-- A small number of old rows may predate the event journal or have an event
-- that cannot be matched. Keep those rows usable with a deterministic,
-- human-readable title; do not expose action_type as the UI narrative.
UPDATE v5_governance_proposals
SET title = initcap(replace(lower(action_type), '_', ' '))
WHERE title IS NULL;

ALTER TABLE v5_governance_proposals
  ALTER COLUMN title SET NOT NULL;
