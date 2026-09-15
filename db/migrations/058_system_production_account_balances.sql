-- EARTH ACTIVE MIGRATION: allow resource issuance sinks to carry negative balances

ALTER TABLE economic_accounts
  DROP CONSTRAINT IF EXISTS economic_accounts_balance_units_check;

ALTER TABLE economic_accounts
  ADD CONSTRAINT economic_accounts_balance_units_check
  CHECK (balance_units >= 0 OR account_type = 'SYSTEM_ACCOUNT');
