ALTER TABLE proposals ADD COLUMN rule_version_id TEXT;

CREATE TABLE IF NOT EXISTS governance_rules (
  id TEXT PRIMARY KEY,
  institution_id TEXT NOT NULL REFERENCES institutions(id),
  name TEXT NOT NULL,
  category TEXT NOT NULL,
  value_json TEXT NOT NULL DEFAULT '{}',
  version INTEGER NOT NULL,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('draft','active','superseded','repealed')),
  created_by TEXT NOT NULL REFERENCES humans(id),
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (institution_id, category, version)
);

INSERT OR IGNORE INTO governance_rules (id, institution_id, name, category, value_json, version, status, created_by)
VALUES ('RULE-OUC-MARKET-1', 'OUC-001', 'Central Market principles', 'market', '{"uniformClearing":true,"fairAllocation":true}', 1, 'active', 'H-0044');

INSERT OR IGNORE INTO governance_rules (id, institution_id, name, category, value_json, version, status, created_by)
VALUES ('RULE-OUC-LEVY-1', 'OUC-001', 'Basic OUC levy', 'finance', '{"rate":0.01,"indexed":true}', 1, 'active', 'H-0044');
