-- EARTH ACTIVE MIGRATION: dated repayment schedules for source-backed loans

CREATE TABLE IF NOT EXISTS bank_loan_schedules (
  id TEXT PRIMARY KEY,
  loan_id TEXT NOT NULL REFERENCES bank_loans(id),
  installment_no INTEGER NOT NULL CHECK (installment_no > 0),
  due_game_day BIGINT NOT NULL,
  principal_due_units BIGINT NOT NULL CHECK (principal_due_units >= 0),
  interest_due_units BIGINT NOT NULL CHECK (interest_due_units >= 0),
  paid_units BIGINT NOT NULL DEFAULT 0 CHECK (paid_units >= 0),
  status TEXT NOT NULL DEFAULT 'DUE' CHECK (status IN ('DUE','PARTIAL','PAID','ARREARS','CANCELLED')),
  payment_transaction_id BIGINT REFERENCES economic_transactions(id),
  correlation_id TEXT NOT NULL UNIQUE,
  UNIQUE (loan_id, installment_no),
  CHECK (paid_units <= principal_due_units + interest_due_units)
);
CREATE INDEX IF NOT EXISTS bank_loan_schedules_due_idx ON bank_loan_schedules (status, due_game_day, loan_id);
