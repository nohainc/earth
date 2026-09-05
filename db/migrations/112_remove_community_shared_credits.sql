-- Drop obsolete community shared_credits column and communal credit accounts
ALTER TABLE communities DROP COLUMN IF EXISTS shared_credits;
DELETE FROM account_balances WHERE account_id LIKE 'account-community-%';
