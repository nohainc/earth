-- The profile engine is authoritative only for normal physical-resource flows.
-- Credit revenue, dividends, taxes, life maintenance, and shortage handling
-- remain in their specialised settlement stages.
ALTER TABLE world_state
  ADD COLUMN IF NOT EXISTS daily_settlement_mode TEXT NOT NULL DEFAULT 'profile_resources'
  CHECK (daily_settlement_mode IN ('legacy', 'profile_resources'));
