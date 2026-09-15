-- EARTH ACTIVE MIGRATION: V4 House onboarding progress

CREATE TABLE IF NOT EXISTS house_onboarding_progress (
  house_id TEXT PRIMARY KEY REFERENCES houses(id),
  onboarding_version TEXT NOT NULL DEFAULT 'onboarding-v4-1',
  status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'COMPLETED', 'SKIPPED')),
  completed_milestones JSONB NOT NULL DEFAULT '[]'::jsonb CHECK (jsonb_typeof(completed_milestones) = 'array'),
  completed_game_day BIGINT,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS house_onboarding_status_idx
  ON house_onboarding_progress (status, updated_at DESC);

INSERT INTO house_onboarding_progress (house_id)
SELECT id FROM houses
ON CONFLICT (house_id) DO NOTHING;
