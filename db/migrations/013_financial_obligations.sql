-- EARTH ACTIVE MIGRATION: generic financial obligations

CREATE TABLE IF NOT EXISTS financial_obligations (
  id TEXT PRIMARY KEY,
  debtor_economic_id TEXT NOT NULL REFERENCES owner_registry(economic_id),
  creditor_economic_id TEXT NOT NULL REFERENCES owner_registry(economic_id),
  obligation_type TEXT NOT NULL CHECK (obligation_type IN ('TAX','ROYALTY','LICENSE_PAYMENT','LOAN_PAYMENT','SERVICE_INVOICE','FINE_FEE')),
  source_id TEXT,
  principal_due_units BIGINT NOT NULL CHECK (principal_due_units >= 0),
  interest_due_units BIGINT NOT NULL DEFAULT 0 CHECK (interest_due_units >= 0),
  paid_units BIGINT NOT NULL DEFAULT 0 CHECK (paid_units >= 0),
  debtor_account_purpose TEXT NOT NULL DEFAULT 'WALLET',
  creditor_account_purpose TEXT NOT NULL DEFAULT 'TREASURY',
  due_game_day BIGINT NOT NULL,
  priority_class INTEGER NOT NULL DEFAULT 100,
  rule_version TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'DUE' CHECK (status IN ('DUE','PARTIAL','PAID','ARREARS','CANCELLED')),
  created_game_day BIGINT NOT NULL,
  payment_transaction_id BIGINT REFERENCES economic_transactions(id),
  correlation_id TEXT NOT NULL UNIQUE,
  cancelled_game_day BIGINT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (paid_units <= principal_due_units + interest_due_units),
  CHECK ((status = 'PAID' AND paid_units = principal_due_units + interest_due_units) OR status <> 'PAID')
);

CREATE INDEX IF NOT EXISTS financial_obligations_debtor_status_idx ON financial_obligations(debtor_economic_id, status, due_game_day);
CREATE INDEX IF NOT EXISTS financial_obligations_creditor_idx ON financial_obligations(creditor_economic_id, status, due_game_day);
