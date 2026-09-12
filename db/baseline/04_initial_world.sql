INSERT INTO world_state(id, game_day, game_minute, world_seed, status)
VALUES ('WORLD', 1, 0, 'EARTH-GENESIS', 'ACTIVE');

INSERT INTO institutions(id, kind, name) VALUES
  ('OUC-001', 'OUC', 'Organization of United Corporations'),
  ('GLOBAL-BANK-001', 'BANK', 'Global Bank');

INSERT INTO owner_registry(id, owner_type, economic_id) VALUES
  ('OWNER-OUC-001', 'SYSTEM', 'ECON-OUC-001'),
  ('OWNER-BANK-001', 'SYSTEM', 'ECON-GLOBAL-BANK-001'),
  ('OWNER-MONETARY-ISSUANCE', 'SYSTEM', 'ECON-MONETARY-ISSUANCE'),
  ('OWNER-MONETARY-RETIREMENT', 'SYSTEM', 'ECON-MONETARY-RETIREMENT'),
  ('OWNER-MARKET-CLEARING', 'SYSTEM', 'ECON-MARKET-CLEARING');

INSERT INTO economic_accounts(owner_economic_id, asset_id, account_type) VALUES
  ('ECON-OUC-001', 1, 'TREASURY'),
  ('ECON-OUC-001', 1, 'OPERATIONS'),
  ('ECON-OUC-001', 1, 'RESERVE'),
  ('ECON-GLOBAL-BANK-001', 1, 'RESERVE'),
  ('ECON-GLOBAL-BANK-001', 1, 'OPERATIONS'),
  ('ECON-MONETARY-ISSUANCE', 1, 'TREASURY'),
  ('ECON-MONETARY-RETIREMENT', 1, 'TREASURY'),
  ('ECON-MARKET-CLEARING', 1, 'TREASURY');

INSERT INTO market_instruments(id, symbol, asset_id, quote_asset_id)
VALUES ('SPOT-MATERIAL', 'MATERIAL', 2, 1), ('SPOT-COMPONENTS', 'COMPONENTS', 3, 1),
       ('SPOT-ENERGY', 'ENERGY', 4, 1), ('SPOT-COMPUTE', 'COMPUTE', 5, 1),
       ('SPOT-FOOD', 'FOOD', 6, 1);
