-- Proposal Engine V2: generic, explicit six-asset funding requirements.

CREATE TABLE IF NOT EXISTS proposal_action_requirements (
  id TEXT PRIMARY KEY,
  proposal_action_id TEXT NOT NULL REFERENCES proposal_actions(id) ON DELETE CASCADE,
  asset_id SMALLINT NOT NULL REFERENCES economic_assets(id),
  required_units BIGINT NOT NULL CHECK (required_units > 0),
  source_owner_economic_id BIGINT NOT NULL REFERENCES owner_registry(economic_id),
  source_account_type SMALLINT NOT NULL,
  requirement_kind TEXT NOT NULL DEFAULT 'funding',
  UNIQUE (proposal_action_id, asset_id)
);
