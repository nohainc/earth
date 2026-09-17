-- EARTH ACTIVE MIGRATION: auditable, side-effect-free tax cutover evidence.

CREATE TABLE v5_tax_reconciliation_runs (
  id TEXT PRIMARY KEY,
  assessed_game_day BIGINT NOT NULL UNIQUE CHECK (assessed_game_day >= 1),
  status TEXT NOT NULL DEFAULT 'COMPLETED' CHECK (status IN ('COMPLETED','FAILED')),
  rules_compared INTEGER NOT NULL DEFAULT 0 CHECK (rules_compared >= 0),
  matches INTEGER NOT NULL DEFAULT 0 CHECK (matches >= 0),
  mismatches INTEGER NOT NULL DEFAULT 0 CHECK (mismatches >= 0),
  missing_canonical INTEGER NOT NULL DEFAULT 0 CHECK (missing_canonical >= 0),
  error_message TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  completed_at TIMESTAMPTZ
);

CREATE TABLE v5_tax_reconciliation_items (
  id TEXT PRIMARY KEY,
  run_id TEXT NOT NULL REFERENCES v5_tax_reconciliation_runs(id),
  assessed_game_day BIGINT NOT NULL CHECK (assessed_game_day >= 1),
  authority_type TEXT NOT NULL CHECK (authority_type IN ('EARTH','CORPORATION')),
  authority_id TEXT NOT NULL,
  legacy_rule_id TEXT NOT NULL,
  canonical_rule_code TEXT NOT NULL,
  legacy_rate_bps INTEGER NOT NULL CHECK (legacy_rate_bps >= 0),
  canonical_rate_bps INTEGER,
  legacy_version_id TEXT,
  canonical_version_id TEXT,
  result TEXT NOT NULL CHECK (result IN ('MATCH','MISMATCH','MISSING_CANONICAL')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (run_id, legacy_rule_id, authority_id)
);

CREATE INDEX v5_tax_reconciliation_items_result_idx
  ON v5_tax_reconciliation_items (assessed_game_day, result);
