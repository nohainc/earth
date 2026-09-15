-- EARTH ACTIVE MIGRATION: isolated, optional mutual-credit networks
-- These units are network claims only. They never post to global CREDIT accounts.
CREATE TABLE mutual_credit_networks (
  id TEXT PRIMARY KEY,
  organization_id TEXT NOT NULL REFERENCES organizations(id),
  name TEXT NOT NULL,
  unit_code TEXT NOT NULL UNIQUE,
  status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','PAUSED','DEFAULTED','CLOSED')),
  credit_enabled BOOLEAN NOT NULL DEFAULT TRUE,
  max_member_limit_units BIGINT NOT NULL CHECK (max_member_limit_units > 0),
  reserve_target_units BIGINT NOT NULL DEFAULT 0 CHECK (reserve_target_units >= 0),
  created_game_day BIGINT NOT NULL CHECK (created_game_day >= 1),
  rules_version TEXT NOT NULL DEFAULT 'mutual-credit-v1',
  correlation_id TEXT NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE mutual_credit_members (
  network_id TEXT NOT NULL REFERENCES mutual_credit_networks(id),
  house_id TEXT NOT NULL REFERENCES houses(id),
  credit_limit_units BIGINT NOT NULL CHECK (credit_limit_units > 0),
  position_units BIGINT NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','SUSPENDED','DEFAULTED','LEFT')),
  joined_game_day BIGINT NOT NULL CHECK (joined_game_day >= 1),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (network_id, house_id)
);

CREATE TABLE mutual_credit_transfers (
  id TEXT PRIMARY KEY,
  network_id TEXT NOT NULL REFERENCES mutual_credit_networks(id),
  from_house_id TEXT NOT NULL REFERENCES houses(id),
  to_house_id TEXT NOT NULL REFERENCES houses(id),
  amount_units BIGINT NOT NULL CHECK (amount_units > 0),
  game_day BIGINT NOT NULL CHECK (game_day >= 1),
  status TEXT NOT NULL DEFAULT 'SETTLED' CHECK (status IN ('SETTLED','REVERSED')),
  rules_version TEXT NOT NULL DEFAULT 'mutual-credit-v1',
  correlation_id TEXT NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CHECK (from_house_id <> to_house_id)
);

CREATE TABLE mutual_credit_guarantees (
  id TEXT PRIMARY KEY,
  network_id TEXT NOT NULL REFERENCES mutual_credit_networks(id),
  guarantor_house_id TEXT NOT NULL REFERENCES houses(id),
  member_house_id TEXT NOT NULL REFERENCES houses(id),
  guaranteed_units BIGINT NOT NULL CHECK (guaranteed_units > 0),
  status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','CALLED','RELEASED')),
  created_game_day BIGINT NOT NULL CHECK (created_game_day >= 1),
  correlation_id TEXT NOT NULL UNIQUE,
  CHECK (guarantor_house_id <> member_house_id)
);

CREATE TABLE mutual_credit_defaults (
  id TEXT PRIMARY KEY,
  network_id TEXT NOT NULL REFERENCES mutual_credit_networks(id),
  member_house_id TEXT NOT NULL REFERENCES houses(id),
  claim_units BIGINT NOT NULL CHECK (claim_units > 0),
  recovered_units BIGINT NOT NULL DEFAULT 0 CHECK (recovered_units >= 0 AND recovered_units <= claim_units),
  game_day BIGINT NOT NULL CHECK (game_day >= 1),
  resolution TEXT NOT NULL CHECK (resolution IN ('OPEN','RESOLVED','NETWORK_LOSS')),
  correlation_id TEXT NOT NULL UNIQUE
);

CREATE INDEX mutual_credit_members_house_idx ON mutual_credit_members (house_id, status);
CREATE INDEX mutual_credit_transfers_network_day_idx ON mutual_credit_transfers (network_id, game_day DESC, id DESC);
CREATE INDEX mutual_credit_guarantees_member_idx ON mutual_credit_guarantees (network_id, member_house_id, status);
CREATE INDEX mutual_credit_defaults_network_idx ON mutual_credit_defaults (network_id, resolution, game_day DESC);
