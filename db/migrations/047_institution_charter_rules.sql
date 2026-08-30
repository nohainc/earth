-- Migration 047: add institution-level charter storage for existing databases.
-- City and corporation rules are stored on the shared institution record so
-- world snapshots, tax settlement, and market rules can read them uniformly.

ALTER TABLE institutions
  ADD COLUMN IF NOT EXISTS charter_rules TEXT;
