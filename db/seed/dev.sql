-- Minimal local development profile. No demo economy is part of the baseline.
INSERT INTO auth_accounts (id, email, password_hash, password_salt, password_iterations)
VALUES ('DEV-ACCOUNT', 'dev@earth.local', 'development-only', 'development-only', 1)
ON CONFLICT (id) DO NOTHING;
INSERT INTO houses (id, account_id, house_name, motto)
VALUES ('DEV-HOUSE', 'DEV-ACCOUNT', 'Development House', 'Local development only')
ON CONFLICT (id) DO NOTHING;
UPDATE auth_accounts SET house_id = 'DEV-HOUSE' WHERE id = 'DEV-ACCOUNT';
INSERT INTO humans (id, account_id, house_id, display_name, birth_game_day, age_years)
VALUES ('DEV-HUMAN', 'DEV-ACCOUNT', 'DEV-HOUSE', 'Development Human', 1, 31)
ON CONFLICT (id) DO NOTHING;
UPDATE houses SET current_human_id = 'DEV-HUMAN' WHERE id = 'DEV-HOUSE';
INSERT INTO owner_registry (id, owner_type, economic_id)
VALUES ('OWNER-DEV-HOUSE', 'HOUSE', 'ECON-DEV-HOUSE')
ON CONFLICT (id) DO NOTHING;
INSERT INTO economic_accounts (owner_economic_id, asset_id, account_type)
SELECT 'ECON-DEV-HOUSE', asset_id, CASE WHEN asset_id = 1 THEN 'WALLET' ELSE 'INVENTORY' END
FROM economic_assets
ON CONFLICT (owner_economic_id, asset_id, account_type) DO NOTHING;
