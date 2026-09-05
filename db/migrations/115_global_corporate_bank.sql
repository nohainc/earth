-- Global Corporate Bank: deposits and corporation lending, without building shares.

BEGIN;

CREATE TABLE IF NOT EXISTS global_bank_deposits (
  id TEXT PRIMARY KEY,
  human_id TEXT NOT NULL REFERENCES humans(id),
  principal NUMERIC(20,2) NOT NULL CHECK (principal > 0),
  daily_rate NUMERIC(12,8) NOT NULL DEFAULT 0 CHECK (daily_rate >= 0),
  accrued_interest NUMERIC(20,2) NOT NULL DEFAULT 0 CHECK (accrued_interest >= 0),
  start_game_day BIGINT NOT NULL,
  maturity_game_day BIGINT NOT NULL CHECK (maturity_game_day >= start_game_day),
  last_settled_game_day BIGINT NOT NULL,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','matured','withdrawn','cancelled')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS global_bank_deposits_human_idx ON global_bank_deposits(human_id, status, created_at DESC);

CREATE TABLE IF NOT EXISTS global_bank_loans (
  id TEXT PRIMARY KEY,
  corporation_id TEXT NOT NULL REFERENCES corporations(id),
  principal NUMERIC(20,2) NOT NULL CHECK (principal > 0),
  outstanding_principal NUMERIC(20,2) NOT NULL CHECK (outstanding_principal >= 0),
  daily_rate NUMERIC(12,8) NOT NULL DEFAULT 0 CHECK (daily_rate >= 0),
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','repaid','defaulted','cancelled')),
  started_game_day BIGINT NOT NULL,
  due_game_day BIGINT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS global_bank_loans_corporation_idx ON global_bank_loans(corporation_id, status, created_at DESC);

CREATE TABLE IF NOT EXISTS global_bank_settlement_journals (
  id UUID PRIMARY KEY,
  game_day BIGINT NOT NULL UNIQUE,
  loan_income NUMERIC(20,2) NOT NULL DEFAULT 0,
  operating_costs NUMERIC(20,2) NOT NULL DEFAULT 0,
  reserve_contribution NUMERIC(20,2) NOT NULL DEFAULT 0,
  interest_pool NUMERIC(20,2) NOT NULL DEFAULT 0,
  interest_paid NUMERIC(20,2) NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- The bank is a system owner, so register it before creating its account.
-- `account_balances.owner_id` is validated against `owner_registry.id`.
INSERT INTO owner_registry (id, owner_type, source_id, status)
VALUES ('GLOBAL-CORPORATE-BANK', 'system', 'GLOBAL-CORPORATE-BANK', 'active')
ON CONFLICT (source_id) DO NOTHING;

INSERT INTO account_balances (account_id, owner_id, balance, currency)
VALUES ('account-global-corporate-bank', 'GLOBAL-CORPORATE-BANK', 0, 'CREDIT')
ON CONFLICT (account_id) DO NOTHING;

COMMIT;
