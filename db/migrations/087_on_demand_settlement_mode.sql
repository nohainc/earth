-- Migration 087: Add 'on_demand' to daily_settlement_mode in world_state
--
-- Enables pure on-demand / lazy client-triggered settlement mode.

ALTER TABLE world_state
  DROP CONSTRAINT IF EXISTS world_state_daily_settlement_mode_check;

ALTER TABLE world_state
  ADD CONSTRAINT world_state_daily_settlement_mode_check
  CHECK (daily_settlement_mode IN ('legacy', 'profile_resources', 'on_demand'));

UPDATE world_state
  SET daily_settlement_mode = 'on_demand'
  WHERE id = 'WORLD';
