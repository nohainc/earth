-- EARTH ACTIVE MIGRATION: publish effective Human authority summaries

ALTER TABLE institution_governance_roles
  ADD COLUMN IF NOT EXISTS effective_from_game_day BIGINT NOT NULL DEFAULT 1;

CREATE INDEX IF NOT EXISTS institution_governance_roles_human_active_idx
  ON institution_governance_roles (human_id, status, effective_from_game_day);
