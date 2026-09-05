-- Retire the human-to-human negotiated and scheduled supply contract system.
-- Market futures are a separate feature and remain intact.
DROP TABLE IF EXISTS contract_delivery_ticks CASCADE;
DROP TABLE IF EXISTS contract_escrow_vaults CASCADE;
DROP TABLE IF EXISTS contract_disputes CASCADE;
DROP TABLE IF EXISTS supply_contracts CASCADE;
DROP TABLE IF EXISTS negotiated_contracts CASCADE;
DROP TABLE IF EXISTS merger_contracts CASCADE;
