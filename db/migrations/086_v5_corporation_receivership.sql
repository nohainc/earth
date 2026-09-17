-- EARTH ACTIVE MIGRATION: Corporation EARTH-rent receivership and restructuring.

CREATE TABLE v5_corporation_receivership_cases (
  id TEXT PRIMARY KEY,
  corporation_id TEXT NOT NULL REFERENCES corporations(id),
  trigger_status TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'OPEN' CHECK (status IN ('OPEN','RESTRUCTURING','RESOLVED','DISSOLVED')),
  opened_game_day BIGINT NOT NULL CHECK (opened_game_day >= 1),
  closed_game_day BIGINT,
  arrears_units BIGINT NOT NULL DEFAULT 0 CHECK (arrears_units >= 0),
  resolution_reason TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE UNIQUE INDEX v5_corporation_receivership_open_uq ON v5_corporation_receivership_cases(corporation_id) WHERE status IN ('OPEN','RESTRUCTURING');

CREATE TABLE v5_corporation_restructuring_plans (
  id TEXT PRIMARY KEY,
  case_id TEXT NOT NULL REFERENCES v5_corporation_receivership_cases(id),
  corporation_id TEXT NOT NULL REFERENCES corporations(id),
  proposed_by_human_id TEXT NOT NULL REFERENCES humans(id),
  plan_text TEXT NOT NULL CHECK (length(plan_text) BETWEEN 20 AND 4000),
  proposed_game_day BIGINT NOT NULL CHECK (proposed_game_day >= 1),
  status TEXT NOT NULL DEFAULT 'SUBMITTED' CHECK (status IN ('SUBMITTED','ACCEPTED','REJECTED','COMPLETED')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX v5_corporation_receivership_history_idx ON v5_corporation_receivership_cases(corporation_id, opened_game_day DESC);
