-- EARTH ACTIVE MIGRATION: public projects and source-backed matching pools

CREATE TABLE IF NOT EXISTS public_projects (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  description TEXT NOT NULL,
  beneficiary_type TEXT NOT NULL CHECK (beneficiary_type IN ('ORGANIZATION','EARTH','TERRITORY')),
  beneficiary_id TEXT NOT NULL,
  recipient_account_id BIGINT NOT NULL REFERENCES economic_accounts(id),
  target_units BIGINT NOT NULL CHECK (target_units > 0),
  deadline_game_day BIGINT NOT NULL CHECK (deadline_game_day >= 1),
  matching_pool_authorized_units BIGINT NOT NULL CHECK (matching_pool_authorized_units >= 0),
  matching_pool_funded_units BIGINT NOT NULL DEFAULT 0 CHECK (matching_pool_funded_units >= 0 AND matching_pool_funded_units <= matching_pool_authorized_units),
  matching_pool_spent_units BIGINT NOT NULL DEFAULT 0 CHECK (matching_pool_spent_units >= 0 AND matching_pool_spent_units <= matching_pool_funded_units),
  contribution_units BIGINT NOT NULL DEFAULT 0 CHECK (contribution_units >= 0),
  matched_units BIGINT NOT NULL DEFAULT 0 CHECK (matched_units >= 0),
  status TEXT NOT NULL DEFAULT 'OPEN' CHECK (status IN ('OPEN','FUNDED','FAILED','SETTLED','CANCELLED')),
  proposal_id TEXT NOT NULL REFERENCES governance_proposals_v4(id),
  created_by_human_id TEXT NOT NULL REFERENCES humans(id),
  correlation_id TEXT NOT NULL UNIQUE,
  created_game_day BIGINT NOT NULL
);
CREATE TABLE IF NOT EXISTS public_project_contributions (
  id TEXT PRIMARY KEY,
  project_id TEXT NOT NULL REFERENCES public_projects(id),
  house_id TEXT NOT NULL REFERENCES houses(id),
  amount_units BIGINT NOT NULL CHECK (amount_units > 0),
  escrow_account_id BIGINT NOT NULL REFERENCES economic_accounts(id),
  contribution_transaction_id BIGINT NOT NULL REFERENCES economic_transactions(id),
  status TEXT NOT NULL DEFAULT 'ESCROWED' CHECK (status IN ('ESCROWED','RELEASED','REFUNDED')),
  correlation_id TEXT NOT NULL UNIQUE,
  created_game_day BIGINT NOT NULL
);
CREATE TABLE IF NOT EXISTS public_project_settlements (
  id TEXT PRIMARY KEY,
  project_id TEXT NOT NULL UNIQUE REFERENCES public_projects(id),
  contributed_units BIGINT NOT NULL CHECK (contributed_units >= 0),
  matched_units BIGINT NOT NULL CHECK (matched_units >= 0),
  supporter_count INTEGER NOT NULL CHECK (supporter_count >= 0),
  settlement_transaction_id BIGINT REFERENCES economic_transactions(id),
  settled_game_day BIGINT NOT NULL,
  correlation_id TEXT NOT NULL UNIQUE
);
CREATE INDEX IF NOT EXISTS public_projects_deadline_idx ON public_projects (status, deadline_game_day);
CREATE INDEX IF NOT EXISTS public_project_contributions_project_idx ON public_project_contributions (project_id, status, house_id);
