-- EARTH ACTIVE MIGRATION: V5 Corporation lifecycle, dissolution, and name reuse authority.
-- Migration 092: V5 Corporation Lifecycle, Dissolution, and Name Reuse Authority

-- Allow dead / dissolved institutions to release their name for new active institutions
ALTER TABLE institutions DROP CONSTRAINT IF EXISTS institutions_name_key;
DROP INDEX IF EXISTS institutions_active_name_idx;
CREATE UNIQUE INDEX institutions_active_name_idx ON institutions (lower(name)) WHERE status = 'ACTIVE';

-- Corporation Dissolution Schedules with transition grace period
CREATE TABLE IF NOT EXISTS v5_corporation_dissolution_schedules (
  id TEXT PRIMARY KEY,
  corporation_id TEXT NOT NULL REFERENCES corporations(id),
  initiated_by_human_id TEXT NOT NULL REFERENCES humans(id),
  initiated_game_day BIGINT NOT NULL,
  effective_game_day BIGINT NOT NULL,
  reason TEXT,
  status TEXT NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'EXECUTED', 'CANCELLED')),
  correlation_id TEXT NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_v5_corp_dissolution_pending
  ON v5_corporation_dissolution_schedules (effective_game_day, status)
  WHERE status = 'PENDING';
