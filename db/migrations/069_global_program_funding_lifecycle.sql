-- EARTH ACTIVE MIGRATION: bounded program funding, refunds, and benefit attribution

ALTER TABLE global_programs ADD COLUMN IF NOT EXISTS funding_deadline_game_day BIGINT;
UPDATE global_programs SET funding_deadline_game_day = GREATEST(created_game_day, created_game_day + 365) WHERE funding_deadline_game_day IS NULL;
ALTER TABLE global_programs ALTER COLUMN funding_deadline_game_day SET NOT NULL;
ALTER TABLE global_programs ADD CONSTRAINT global_programs_funding_deadline_check CHECK (funding_deadline_game_day >= created_game_day);
ALTER TABLE global_program_contributions ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'ESCROWED' CHECK (status IN ('ESCROWED','APPLIED','REFUNDED'));
ALTER TABLE global_program_contributions ADD COLUMN IF NOT EXISTS refunded_game_day BIGINT;
ALTER TABLE global_program_contributions ADD COLUMN IF NOT EXISTS refund_transaction_id BIGINT REFERENCES economic_transactions(id);
CREATE INDEX IF NOT EXISTS global_program_contributions_house_day_idx ON global_program_contributions (house_id, game_day DESC, status);

CREATE TABLE IF NOT EXISTS global_program_benefit_attributions (
  id TEXT PRIMARY KEY,
  program_id TEXT NOT NULL REFERENCES global_programs(id),
  beneficiary_type TEXT NOT NULL CHECK (beneficiary_type IN ('HOUSE','ORGANIZATION','TERRITORY','EARTH')),
  beneficiary_id TEXT NOT NULL,
  benefit_type TEXT NOT NULL,
  amount_units BIGINT NOT NULL CHECK (amount_units >= 0),
  effective_game_day BIGINT NOT NULL,
  rules_version TEXT NOT NULL,
  correlation_id TEXT NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS global_program_benefits_program_idx ON global_program_benefit_attributions (program_id, effective_game_day);
