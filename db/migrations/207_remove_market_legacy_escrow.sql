-- Market V2 Plan 16: remove transitional market escrow accounts.
DELETE FROM account_balances
 WHERE account_id LIKE 'market-order-%';
