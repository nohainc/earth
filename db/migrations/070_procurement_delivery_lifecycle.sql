-- EARTH ACTIVE MIGRATION: typed procurement delivery, acceptance, and resolution evidence

ALTER TABLE contract_performance_events DROP CONSTRAINT IF EXISTS contract_performance_events_status_check;
ALTER TABLE contract_performance_events ADD CONSTRAINT contract_performance_events_status_check CHECK (status IN ('DUE','DELIVERED','ACCEPTED','PERFORMED','FAILED','DISPUTED','WAIVED'));
ALTER TABLE contract_performance_events ADD COLUMN IF NOT EXISTS delivered_game_day BIGINT;
ALTER TABLE contract_performance_events ADD COLUMN IF NOT EXISTS delivery_note TEXT;
ALTER TABLE contract_performance_events ADD COLUMN IF NOT EXISTS delivered_units BIGINT CHECK (delivered_units IS NULL OR delivered_units >= 0);
ALTER TABLE contract_performance_events ADD COLUMN IF NOT EXISTS quality_score_bps INTEGER CHECK (quality_score_bps IS NULL OR quality_score_bps BETWEEN 0 AND 10000);
ALTER TABLE contract_performance_events ADD COLUMN IF NOT EXISTS accepted_game_day BIGINT;
ALTER TABLE contract_performance_events ADD COLUMN IF NOT EXISTS resolution_action TEXT CHECK (resolution_action IS NULL OR resolution_action IN ('ACCEPTED','FAILED','WAIVED'));
ALTER TABLE contract_performance_events ADD COLUMN IF NOT EXISTS resolution_reason TEXT;
