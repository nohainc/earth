-- EARTH PostgreSQL Migration 026: Automated Supply Contracts & Escrow Vaults

CREATE TABLE IF NOT EXISTS supply_contracts (
  contract_id TEXT PRIMARY KEY REFERENCES negotiated_contracts(id) ON DELETE CASCADE,
  resource_type TEXT NOT NULL CHECK (resource_type IN ('food', 'energy', 'material', 'compute')),
  daily_quantity NUMERIC(20, 2) NOT NULL CHECK (daily_quantity > 0),
  unit_price NUMERIC(20, 2) NOT NULL CHECK (unit_price > 0),
  total_days INTEGER NOT NULL CHECK (total_days > 0),
  delivered_days INTEGER NOT NULL DEFAULT 0,
  default_days INTEGER NOT NULL DEFAULT 0,
  max_consecutive_defaults INTEGER NOT NULL DEFAULT 3,
  consecutive_defaults INTEGER NOT NULL DEFAULT 0,
  escrow_total NUMERIC(20, 2) NOT NULL CHECK (escrow_total >= 0),
  escrow_remaining NUMERIC(20, 2) NOT NULL CHECK (escrow_remaining >= 0),
  penalty_per_default NUMERIC(20, 2) NOT NULL DEFAULT 0 CHECK (penalty_per_default >= 0),
  last_settled_game_day BIGINT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS contract_escrow_vaults (
  id TEXT PRIMARY KEY,
  contract_id TEXT NOT NULL REFERENCES negotiated_contracts(id) ON DELETE CASCADE,
  buyer_id TEXT NOT NULL REFERENCES humans(id),
  seller_id TEXT NOT NULL REFERENCES humans(id),
  locked_amount NUMERIC(20, 2) NOT NULL CHECK (locked_amount >= 0),
  released_amount NUMERIC(20, 2) NOT NULL DEFAULT 0,
  refunded_amount NUMERIC(20, 2) NOT NULL DEFAULT 0,
  penalty_paid NUMERIC(20, 2) NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'locked' CHECK (status IN ('locked', 'released', 'refunded', 'depleted')),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS contract_delivery_ticks (
  id TEXT PRIMARY KEY,
  contract_id TEXT NOT NULL REFERENCES negotiated_contracts(id) ON DELETE CASCADE,
  game_day BIGINT NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('delivered', 'defaulted', 'partial')),
  quantity_delivered NUMERIC(20, 2) NOT NULL DEFAULT 0,
  credits_transferred NUMERIC(20, 2) NOT NULL DEFAULT 0,
  penalty_charged NUMERIC(20, 2) NOT NULL DEFAULT 0,
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS supply_contracts_resource_idx ON supply_contracts(resource_type);
CREATE INDEX IF NOT EXISTS contract_escrow_vaults_contract_idx ON contract_escrow_vaults(contract_id);
CREATE INDEX IF NOT EXISTS contract_delivery_ticks_contract_day_idx ON contract_delivery_ticks(contract_id, game_day);
