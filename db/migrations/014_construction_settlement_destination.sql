-- EARTH ACTIVE MIGRATION: explicit construction/operation CREDIT destination

INSERT INTO owner_registry (id, owner_type, economic_id)
VALUES ('OWNER-CONSTRUCTION-SETTLEMENT', 'SYSTEM', 'ECON-CONSTRUCTION-SETTLEMENT')
ON CONFLICT (id) DO NOTHING;

INSERT INTO economic_accounts (owner_economic_id, asset_id, account_type, balance_units, status)
SELECT 'ECON-CONSTRUCTION-SETTLEMENT', id, 'SYSTEM_ACCOUNT', 0, 'ACTIVE'
FROM economic_assets WHERE code = 'CREDIT'
ON CONFLICT (owner_economic_id, asset_id, account_type) DO NOTHING;
