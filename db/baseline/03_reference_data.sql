INSERT INTO economic_assets(id, code, asset_kind) VALUES
  (1, 'CREDIT', 'CREDIT'),
  (2, 'MATERIAL', 'RESOURCE'),
  (3, 'COMPONENTS', 'RESOURCE'),
  (4, 'ENERGY', 'RESOURCE'),
  (5, 'COMPUTE', 'RESOURCE'),
  (6, 'FOOD', 'RESOURCE');

INSERT INTO economic_account_types(code, asset_kind, is_escrow) VALUES
  ('WALLET', 'CREDIT', FALSE), ('TREASURY', 'CREDIT', FALSE),
  ('OPERATIONS', 'CREDIT', FALSE), ('RESERVE', 'CREDIT', FALSE),
  ('ESCROW', 'CREDIT', TRUE), ('INVENTORY', 'RESOURCE', FALSE);

INSERT INTO budget_categories(id, institution_kind, category_code, spending_class, priority) VALUES
  ('BUDGET-DEBT', 'CITY', 'DEBT_SERVICE', 'MANDATORY', 1),
  ('BUDGET-ESSENTIAL', 'CITY', 'ESSENTIAL_SERVICES', 'MANDATORY', 2),
  ('BUDGET-OPS', 'CORPORATION', 'OPERATIONS', 'MANDATORY', 2),
  ('BUDGET-RESEARCH', 'CORPORATION', 'RESEARCH', 'DISCRETIONARY', 5),
  ('BUDGET-DIVIDENDS', 'CORPORATION', 'DIVIDENDS', 'DISCRETIONARY', 9);

INSERT INTO fiscal_periods(id, period_type, start_game_day, end_game_day, status)
VALUES ('FISCAL-YEAR-1', 'YEAR', 1, 365, 'ACTIVE');
