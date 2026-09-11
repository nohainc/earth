-- Market V2 Plan 17: remove the duplicate decimal reservation projection.
ALTER TABLE market_orders DROP COLUMN IF EXISTS reserved_credits;
