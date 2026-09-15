-- EARTH ACTIVE MIGRATION: persisted Corporation tax charters for V4 settlement.

ALTER TABLE corporations
  ADD COLUMN IF NOT EXISTS tax_charter JSONB NOT NULL DEFAULT '{}'::JSONB
    CHECK (jsonb_typeof(tax_charter) = 'object'),
  ADD COLUMN IF NOT EXISTS tax_charter_version INTEGER NOT NULL DEFAULT 0
    CHECK (tax_charter_version >= 0),
  ADD COLUMN IF NOT EXISTS tax_charter_updated_game_day BIGINT,
  ADD COLUMN IF NOT EXISTS tax_charter_correlation_id TEXT;

CREATE INDEX IF NOT EXISTS corporations_tax_charter_version_idx
  ON corporations (tax_charter_version, tax_charter_updated_game_day);
