-- EARTH ACTIVE MIGRATION: shared Organization economy and budget authority

ALTER TABLE owner_registry DROP CONSTRAINT IF EXISTS owner_registry_owner_type_check;
ALTER TABLE owner_registry ADD CONSTRAINT owner_registry_owner_type_check
  CHECK (owner_type IN ('EARTH', 'CORPORATION', 'HOUSE', 'BANK', 'SYSTEM', 'ORGANIZATION'));

ALTER TABLE economic_account_policies DROP CONSTRAINT IF EXISTS economic_account_policies_owner_type_check;
ALTER TABLE economic_account_policies ADD CONSTRAINT economic_account_policies_owner_type_check
  CHECK (owner_type IN ('EARTH', 'CORPORATION', 'HOUSE', 'BANK', 'SYSTEM', 'ORGANIZATION'));

INSERT INTO economic_account_policies (owner_type, account_type, allowed_asset_kind, player_visible)
VALUES ('ORGANIZATION', 'TREASURY', 'CREDIT', TRUE),
       ('ORGANIZATION', 'OPERATIONS', 'CREDIT', TRUE),
       ('ORGANIZATION', 'RESERVE', 'CREDIT', TRUE)
ON CONFLICT (owner_type, account_type, allowed_asset_kind) DO NOTHING;

CREATE TABLE IF NOT EXISTS organization_economies (
  organization_id TEXT PRIMARY KEY REFERENCES organizations(id),
  economic_id TEXT NOT NULL UNIQUE REFERENCES owner_registry(economic_id),
  provisioned_game_day BIGINT NOT NULL CHECK (provisioned_game_day >= 1),
  rules_version TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS organization_budget_lines (
  id TEXT PRIMARY KEY,
  organization_id TEXT NOT NULL REFERENCES organizations(id),
  category_code TEXT NOT NULL,
  authorized_units BIGINT NOT NULL CHECK (authorized_units >= 0),
  committed_units BIGINT NOT NULL DEFAULT 0 CHECK (committed_units >= 0),
  spent_units BIGINT NOT NULL DEFAULT 0 CHECK (spent_units >= 0),
  status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'CLOSED')),
  rules_version TEXT NOT NULL,
  CHECK (authorized_units >= committed_units + spent_units),
  UNIQUE (organization_id, category_code)
);
CREATE INDEX IF NOT EXISTS organization_budget_lines_org_idx
  ON organization_budget_lines (organization_id, status, category_code);
