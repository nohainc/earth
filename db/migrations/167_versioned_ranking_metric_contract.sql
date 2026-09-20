-- Make rankings-v2 metric definitions explicit and machine-readable.

ALTER TABLE ranking_metric_definitions
  ADD COLUMN IF NOT EXISTS description TEXT,
  ADD COLUMN IF NOT EXISTS value_type TEXT,
  ADD COLUMN IF NOT EXISTS unit TEXT,
  ADD COLUMN IF NOT EXISTS calculation_source TEXT,
  ADD COLUMN IF NOT EXISTS time_window TEXT,
  ADD COLUMN IF NOT EXISTS tie_behavior TEXT;

UPDATE ranking_metric_definitions
   SET description = CASE metric_code
         WHEN 'LIQUID_CREDIT' THEN 'Current CREDIT account balance owned by the House; unlike resource inventories are excluded.'
         WHEN 'PRODUCTIVE_CAPACITY' THEN 'Sum of active building capacity footprints owned by the House.'
         WHEN 'LEGACY' THEN 'The House legacy value recorded in the canonical House state.'
         WHEN 'TECHNOLOGY' THEN 'Active technology patents owned by the House; Corporation-wide access is excluded.'
         WHEN 'PUBLIC_GOODS' THEN 'House CREDIT contributions applied to Initiatives that completed successfully.'
         WHEN 'MARKET_VOLUME_30D' THEN 'Gross CREDIT quote value of finalized market fills involving the House during the trailing 30 game days.'
         ELSE COALESCE(description, methodology)
       END,
       value_type = CASE metric_code
         WHEN 'LIQUID_CREDIT' THEN 'CREDIT_UNITS'
         WHEN 'PUBLIC_GOODS' THEN 'CREDIT_UNITS'
         WHEN 'MARKET_VOLUME_30D' THEN 'CREDIT_UNITS'
         WHEN 'PRODUCTIVE_CAPACITY' THEN 'CAPACITY_UNITS'
         WHEN 'LEGACY' THEN 'POINTS'
         WHEN 'TECHNOLOGY' THEN 'COUNT'
         ELSE COALESCE(value_type, 'COUNT')
       END,
       unit = CASE metric_code
         WHEN 'LIQUID_CREDIT' THEN 'CREDIT'
         WHEN 'PUBLIC_GOODS' THEN 'CREDIT'
         WHEN 'MARKET_VOLUME_30D' THEN 'CREDIT'
         WHEN 'PRODUCTIVE_CAPACITY' THEN 'CAPACITY'
         WHEN 'LEGACY' THEN 'LEGACY_POINTS'
         WHEN 'TECHNOLOGY' THEN 'COUNT'
         ELSE COALESCE(unit, 'COUNT')
       END,
       calculation_source = CASE metric_code
         WHEN 'LIQUID_CREDIT' THEN 'economic_accounts.balance_units joined to economic_assets.code=CREDIT'
         WHEN 'PRODUCTIVE_CAPACITY' THEN 'buildings.slot_footprint via building_catalog.slot_footprint where building.status=ACTIVE'
         WHEN 'LEGACY' THEN 'houses.dynasty_legacy'
         WHEN 'TECHNOLOGY' THEN 'technology_patents.id where owner is the House and status=ACTIVE'
         WHEN 'PUBLIC_GOODS' THEN 'initiative_contributions.amount_units where status=APPLIED and v5_initiatives.status=COMPLETED'
         WHEN 'MARKET_VOLUME_30D' THEN 'market_fills.gross_quote_units joined to COMPLETED market_batches and CREDIT-quoted instruments'
         ELSE COALESCE(calculation_source, 'retired metric')
       END,
       time_window = CASE metric_code
         WHEN 'PUBLIC_GOODS' THEN 'ALL_TIME'
         WHEN 'MARKET_VOLUME_30D' THEN 'TRAILING_30_GAME_DAYS'
         ELSE 'CURRENT'
       END,
       tie_behavior = 'VALUE_DESC_SUBJECT_ID_ASC'
;

ALTER TABLE ranking_metric_definitions
  ALTER COLUMN description SET NOT NULL,
  ALTER COLUMN value_type SET NOT NULL,
  ALTER COLUMN unit SET NOT NULL,
  ALTER COLUMN calculation_source SET NOT NULL,
  ALTER COLUMN time_window SET NOT NULL,
  ALTER COLUMN tie_behavior SET NOT NULL;
