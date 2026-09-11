-- Market V2 Plan 13: explicit instrument states for expiry processing.
ALTER TABLE market_instruments
  DROP CONSTRAINT IF EXISTS market_instruments_status_check;

ALTER TABLE market_instruments
  ADD CONSTRAINT market_instruments_status_check
  CHECK (status IN ('draft', 'active', 'halted', 'closed', 'expired', 'settled'));
