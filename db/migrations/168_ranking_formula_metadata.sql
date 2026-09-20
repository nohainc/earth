-- Complete the rankings-v2 definition contract with explicit subject and formula fields.

ALTER TABLE ranking_metric_definitions
  ADD COLUMN IF NOT EXISTS subject_type TEXT,
  ADD COLUMN IF NOT EXISTS formula TEXT;

UPDATE ranking_metric_definitions
   SET subject_type = COALESCE(subject_type, category),
       formula = CASE metric_code
         WHEN 'LIQUID_CREDIT' THEN 'SUM(economic_accounts.balance_units) grouped by House where account is ACTIVE and economic_assets.code=CREDIT'
         WHEN 'PRODUCTIVE_CAPACITY' THEN 'SUM(building_catalog.slot_footprint) grouped by House where building.status=ACTIVE'
         WHEN 'LEGACY' THEN 'houses.dynasty_legacy for each active House'
         WHEN 'TECHNOLOGY' THEN 'COUNT(DISTINCT technology_patents.id) grouped by House where patent.status=ACTIVE and owner is the House'
         WHEN 'PUBLIC_GOODS' THEN 'SUM(initiative_contributions.amount_units) grouped by House where contribution.status=APPLIED and Initiative.status=COMPLETED'
         WHEN 'MARKET_VOLUME_30D' THEN 'SUM(market_fills.gross_quote_units) for House buyer or seller where batch.status=COMPLETED, quote asset=CREDIT, and game_day is snapshot_day-29 through snapshot_day'
         ELSE COALESCE(formula, methodology)
       END;

ALTER TABLE ranking_metric_definitions
  ALTER COLUMN subject_type SET NOT NULL,
  ALTER COLUMN formula SET NOT NULL;
