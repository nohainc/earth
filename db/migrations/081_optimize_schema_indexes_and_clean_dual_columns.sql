-- Migration 081: Optimize schema indexes and clean dual columns
--
-- 1. Add missing foreign key & query performance indexes
CREATE INDEX IF NOT EXISTS idx_market_trades_order ON market_trades(order_id);
CREATE INDEX IF NOT EXISTS idx_building_invest_building ON building_investment_shares(building_id);
CREATE INDEX IF NOT EXISTS idx_contract_disputes_parties ON contract_disputes(claimant_id, respondent_id, status);
CREATE INDEX IF NOT EXISTS idx_corp_research_corp_tech ON corporate_research_pools(corporation_id, technology_key);
CREATE INDEX IF NOT EXISTS idx_futures_settlement ON commodity_futures_contracts(commodity, status, expiry_game_day);
CREATE INDEX IF NOT EXISTS idx_dispatch_recipient_status ON diplomatic_dispatches(recipient_human_id, status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_business_shares_biz ON business_shares(business_id);
CREATE INDEX IF NOT EXISTS idx_proposals_institution_status ON proposals(institution_id, status);
CREATE INDEX IF NOT EXISTS idx_gov_rules_inst_cat ON governance_rules(institution_id, category, status);
CREATE INDEX IF NOT EXISTS idx_notifications_unread ON notifications(human_id, created_at DESC) WHERE read_at IS NULL;

-- 2. Drop redundant terms_json column (superseded by terms_text nano-markup in migration 079)
ALTER TABLE negotiated_contracts DROP COLUMN IF EXISTS terms_json;
