-- EARTH ACTIVE MIGRATION: exact daily loan interest and bounded delinquency state

ALTER TABLE bank_loans ADD COLUMN IF NOT EXISTS interest_accrual_remainder BIGINT NOT NULL DEFAULT 0 CHECK (interest_accrual_remainder >= 0 AND interest_accrual_remainder < 36500);
CREATE INDEX IF NOT EXISTS bank_loans_risk_settlement_idx ON bank_loans (status, maturity_game_day, delinquent_since_game_day, id);
