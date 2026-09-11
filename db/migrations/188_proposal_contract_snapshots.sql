-- Proposal Engine V2: freeze the governance and action contract at creation.

ALTER TABLE proposals
  ADD COLUMN IF NOT EXISTS governance_snapshot JSONB NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS action_snapshot JSONB NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS proposal_schema_version INTEGER NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS action_handler_version INTEGER NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS snapshot_hash TEXT;
