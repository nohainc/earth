INSERT INTO world_state(id, game_day, game_minute, world_seed, status)
VALUES ('WORLD', 1, 0, 'EARTH-GENESIS', 'ACTIVE');

INSERT INTO institutions(id, kind, name) VALUES
  ('EARTH', 'EARTH', 'EARTH UC'),
  ('GLOBAL-BANK', 'BANK', 'Global Bank');

INSERT INTO governance_rules (id, institution_id, name, category, value_json, quorum_threshold, approval_threshold, voting_period_days, implementation_delay_days, version, status, effective_from_game_day)
VALUES ('GOV-EARTH-BASELINE-V1', 'EARTH', 'EARTH governance baseline', 'governance', '{"proposal_execution":"governed"}'::jsonb, 0.25, 0.50, 30, 1, 1, 'active', 1)
ON CONFLICT (id) DO NOTHING;

INSERT INTO owner_registry(id, owner_type, economic_id) VALUES
  ('EARTH', 'EARTH', 'ECON-EARTH-001'),
  ('GLOBAL-BANK', 'BANK', 'ECON-GLOBAL-BANK-001'),
  ('OWNER-MONETARY-ISSUANCE', 'SYSTEM', 'ECON-MONETARY-ISSUANCE'),
  ('OWNER-MONETARY-RETIREMENT', 'SYSTEM', 'ECON-MONETARY-RETIREMENT'),
  ('OWNER-MARKET-CLEARING', 'SYSTEM', 'ECON-MARKET-CLEARING');

INSERT INTO economic_accounts(owner_economic_id, asset_id, account_type) VALUES
  ('ECON-EARTH-001', 1, 'TREASURY'),
  ('ECON-EARTH-001', 1, 'OPERATIONS'),
  ('ECON-EARTH-001', 1, 'RESERVE'),
  ('ECON-GLOBAL-BANK-001', 1, 'RESERVE'),
  ('ECON-GLOBAL-BANK-001', 1, 'OPERATIONS'),
  ('ECON-MONETARY-ISSUANCE', 1, 'TREASURY'),
  ('ECON-MONETARY-RETIREMENT', 1, 'TREASURY'),
  ('ECON-MARKET-CLEARING', 1, 'TREASURY');

-- Resource consumption and production are recorded against a canonical system
-- inventory owner; these accounts are not player wallets and never represent
-- a second resource authority.
INSERT INTO economic_accounts(owner_economic_id, asset_id, account_type)
SELECT 'ECON-MONETARY-RETIREMENT', id, 'INVENTORY'
FROM economic_assets
WHERE asset_kind = 'RESOURCE'
ON CONFLICT (owner_economic_id, asset_id, account_type) DO NOTHING;

INSERT INTO market_instruments(id, symbol, asset_id, quote_asset_id)
VALUES ('SPOT-MATERIAL', 'MATERIAL', 2, 1), ('SPOT-COMPONENTS', 'COMPONENTS', 3, 1),
       ('SPOT-ENERGY', 'ENERGY', 4, 1), ('SPOT-COMPUTE', 'COMPUTE', 5, 1),
       ('SPOT-FOOD', 'FOOD', 6, 1);

INSERT INTO tax_rule_versions (id, tax_rule_id, scope, category, version, effective_from_game_day, rate_bps, tax_base_definition, beneficiary_economic_id)
VALUES
  ('TAX-BASIC-LEVY-V1', 'TAX-BASIC-LEVY', 'EARTH', 'basic_levy', 1, 1, 0, 'fixed_daily_obligation', 'ECON-EARTH-001'),
  ('TAX-MARKET-TRANSACTION-V1', 'TAX-MARKET-TRANSACTION', 'EARTH', 'market_transaction', 1, 1, 0, 'external_market_trade', 'ECON-EARTH-001');

INSERT INTO daily_settlement_control (id, status)
VALUES ('WORLD', 'awaiting_baseline')
ON CONFLICT (id) DO NOTHING;
