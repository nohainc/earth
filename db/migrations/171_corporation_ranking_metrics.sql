-- Independent Corporation measures. These remain separate metrics; there is
-- intentionally no composite Corporation power score.

INSERT INTO ranking_metric_definitions
  (metric_code, category, title, methodology, rules_version, status,
   description, value_type, unit, calculation_source, time_window, tie_behavior,
   subject_type, formula)
VALUES
  ('CORPORATION_TREASURY', 'CORPORATION', 'Corporation treasury', 'Current CREDIT held in the Corporation treasury account.', 'rankings-v2', 'ACTIVE', 'Current CREDIT held in the Corporation treasury account.', 'CREDIT_UNITS', 'CREDIT', 'economic_accounts treasury balance joined to Corporation owner and economic_assets.code=CREDIT', 'CURRENT', 'VALUE_DESC_SUBJECT_ID_ASC', 'CORPORATION', 'SUM(economic_accounts.balance_units) grouped by Corporation where account_type=TREASURY, account.status=ACTIVE, and economic_assets.code=CREDIT'),
  ('CORPORATION_OCCUPIED_CAPACITY', 'CORPORATION', 'Occupied capacity', 'Latest canonical occupied capacity across member Houses and Corporation public assets.', 'rankings-v2', 'ACTIVE', 'Latest canonical occupied capacity across member Houses and Corporation public assets.', 'CAPACITY_UNITS', 'CAPACITY', 'corporation_capacity_state_v5.total_occupied_units at the latest finalized game day', 'CURRENT', 'VALUE_DESC_SUBJECT_ID_ASC', 'CORPORATION', 'Latest corporation_capacity_state_v5.total_occupied_units per Corporation'),
  ('CORPORATION_SERVICE_CAPACITY', 'CORPORATION', 'Public service capacity', 'Latest authoritative capacity delivered by Corporation public infrastructure.', 'rankings-v2', 'ACTIVE', 'Latest authoritative capacity delivered by Corporation public infrastructure.', 'CAPACITY_UNITS', 'CAPACITY', 'corporation_operating_snapshots.service_capacity_units at the latest finalized game day', 'CURRENT', 'VALUE_DESC_SUBJECT_ID_ASC', 'CORPORATION', 'Latest corporation_operating_snapshots.service_capacity_units per Corporation'),
  ('CORPORATION_FISCAL_HEADROOM', 'CORPORATION', 'Fiscal budget headroom', 'Uncommitted and unspent budget authority in the latest Corporation financial snapshot.', 'rankings-v2', 'ACTIVE', 'Uncommitted and unspent budget authority in the latest Corporation financial snapshot.', 'CREDIT_UNITS', 'CREDIT', 'institution_financial_snapshots budget authority and commitments for Corporation institution', 'CURRENT', 'VALUE_DESC_SUBJECT_ID_ASC', 'CORPORATION', 'MAX(0, budget_authorized_units - budget_committed_units - budget_spent_units) from latest institution_financial_snapshots row'),
  ('CORPORATION_MARKET_VOLUME_30D', 'CORPORATION', 'Corporation market volume · 30d', 'Gross CREDIT quote value of finalized market fills involving the Corporation during the trailing 30 game days.', 'rankings-v2', 'ACTIVE', 'Gross CREDIT quote value of finalized market fills involving the Corporation during the trailing 30 game days.', 'CREDIT_UNITS', 'CREDIT', 'market_fills.gross_quote_units joined to Corporation owner, COMPLETED market_batches, and CREDIT-quoted instruments', 'TRAILING_30_GAME_DAYS', 'VALUE_DESC_SUBJECT_ID_ASC', 'CORPORATION', 'SUM(market_fills.gross_quote_units) for Corporation buyer or seller where batch.status=COMPLETED, quote asset=CREDIT, and game_day is snapshot_day-29 through snapshot_day')
ON CONFLICT (metric_code) DO UPDATE SET
  category = EXCLUDED.category, title = EXCLUDED.title, methodology = EXCLUDED.methodology,
  rules_version = EXCLUDED.rules_version, status = EXCLUDED.status,
  description = EXCLUDED.description, value_type = EXCLUDED.value_type, unit = EXCLUDED.unit,
  calculation_source = EXCLUDED.calculation_source, time_window = EXCLUDED.time_window,
  tie_behavior = EXCLUDED.tie_behavior, subject_type = EXCLUDED.subject_type,
  formula = EXCLUDED.formula;
