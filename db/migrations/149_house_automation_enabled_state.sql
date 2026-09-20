-- EARTH ACTIVE MIGRATION: versioned House automation enabled state.
-- Automation activation is part of the versioned configuration. A disabled
-- version is still a real future-effective state and is never represented by
-- deleting rows or setting the spend cap to zero.

ALTER TABLE house_automation_versions
  ADD COLUMN IF NOT EXISTS enabled BOOLEAN NOT NULL DEFAULT TRUE;
