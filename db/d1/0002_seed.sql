INSERT OR IGNORE INTO humans (id, account_id, display_name, age_years, standing, legacy) VALUES ('H-0044', 'account-amara', 'Amara Kline', 31, 742, 31);
INSERT OR IGNORE INTO institutions (id, kind, name) VALUES ('OUC-001', 'OUC', 'Organization of United Corporations'), ('CORP-001', 'CORPORATION', 'Helios Cooperative'), ('CITY-0084', 'CITY', 'New Carthage'), ('BUS-1048', 'BUSINESS', 'Kline Works');
INSERT OR IGNORE INTO technologies (id, name, owner_id, progress) VALUES ('TECH-001', 'Adaptive Maintenance AI', 'H-0044', 72);
INSERT OR IGNORE INTO world_state (id, game_day, game_minute, health, market_batch_seconds) VALUES ('WORLD', 184, 462, 68, 498);
INSERT OR IGNORE INTO businesses (id, owner_id, name, policy, condition) VALUES ('B-1048', 'H-0044', 'Kline Works', 'reliability', 96);
INSERT OR IGNORE INTO resource_balances (owner_id, resource, amount) VALUES ('H-0044', 'material', 420), ('H-0044', 'components', 86), ('H-0044', 'energy', 92), ('H-0044', 'compute', 64);
INSERT OR IGNORE INTO proposals (id, institution_id, title, body, status, opens_at, closes_at) VALUES ('042', 'OUC-001', 'Components maintenance levy', 'Fund resilient component maintenance across the shared economy.', 'open', CURRENT_TIMESTAMP, datetime('now', '+30 days'));
