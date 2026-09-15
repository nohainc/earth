-- EARTH ACTIVE MIGRATION: V4-020 public infrastructure counterparty.
-- This system owner receives the expense; it is not a corporation internal
-- Treasury -> Operations transfer that would leave economic semantics unclear.

INSERT INTO owner_registry (id, owner_type, economic_id)
VALUES ('OWNER-PUBLIC-INFRASTRUCTURE', 'SYSTEM', 'ECON-PUBLIC-INFRASTRUCTURE')
ON CONFLICT (id) DO NOTHING;

INSERT INTO economic_accounts (owner_economic_id, asset_id, account_type, balance_units, status)
VALUES ('ECON-PUBLIC-INFRASTRUCTURE', 1, 'SYSTEM_ACCOUNT', 0, 'ACTIVE')
ON CONFLICT (owner_economic_id, asset_id, account_type) DO NOTHING;
