-- Migration 037: Add columns and tables required by continuous simulation engines
-- This migration adds schema elements that the server-side continuous engines
-- (production, technology, financial, institutions, lifecycle) require.

BEGIN;

-- 1. research_projects: add updated_at for tracking last engine settlement
ALTER TABLE research_projects
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();

-- 2. technologies: add status column for patent lifecycle tracking
ALTER TABLE technologies
  ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'available'
  CHECK (status IN ('available', 'researching', 'patented', 'obsolete'));

-- 3. machines: add focus column for production output/input modifiers
ALTER TABLE machines
  ADD COLUMN IF NOT EXISTS focus TEXT NOT NULL DEFAULT 'efficiency'
  CHECK (focus IN ('efficiency', 'durability', 'safety', 'cost'));

-- 4. cities: add status column for active/suspended/dissolved tracking
ALTER TABLE cities
  ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'active'
  CHECK (status IN ('active', 'suspended', 'dissolved'));

-- 5. proposals: add updated_at for tracking engine settlement timestamps
ALTER TABLE proposals
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();

-- 6. technology_events: audit trail for R&D milestones and royalty payments
CREATE TABLE IF NOT EXISTS technology_events (
  id          TEXT PRIMARY KEY,
  technology_id TEXT NOT NULL REFERENCES technologies(id),
  event_type  TEXT NOT NULL CHECK (event_type IN ('royalty_payment', 'patent_granted', 'research_started', 'research_completed', 'license_granted')),
  actor_id    TEXT NOT NULL REFERENCES humans(id),
  target_id   TEXT REFERENCES humans(id),
  details     TEXT NOT NULL DEFAULT '{}',
  game_day    BIGINT NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS technology_events_tech_idx ON technology_events(technology_id, game_day DESC);
CREATE INDEX IF NOT EXISTS technology_events_actor_idx ON technology_events(actor_id, game_day DESC);

COMMIT;
