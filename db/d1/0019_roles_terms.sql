CREATE TABLE IF NOT EXISTS institution_roles (
  id TEXT PRIMARY KEY,
  institution_id TEXT NOT NULL REFERENCES institutions(id),
  name TEXT NOT NULL,
  authority_json TEXT NOT NULL DEFAULT '{}',
  term_days INTEGER NOT NULL DEFAULT 30,
  eligibility TEXT NOT NULL DEFAULT 'member',
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','retired')),
  UNIQUE (institution_id, name)
);
CREATE TABLE IF NOT EXISTS role_assignments (
  id TEXT PRIMARY KEY,
  role_id TEXT NOT NULL REFERENCES institution_roles(id),
  institution_id TEXT NOT NULL REFERENCES institutions(id),
  human_id TEXT NOT NULL REFERENCES humans(id),
  started_game_day INTEGER NOT NULL,
  ends_game_day INTEGER NOT NULL,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','expired','resigned')),
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE UNIQUE INDEX IF NOT EXISTS active_role_assignment_idx ON role_assignments(role_id) WHERE status = 'active';
INSERT OR IGNORE INTO institution_roles (id, institution_id, name, authority_json, term_days, eligibility) VALUES
  ('ROLE-OUC-DELEGATE', 'OUC-001', 'OUC Delegate', '{"propose":true,"vote":true}', 60, 'representative'),
  ('ROLE-CORP-EXECUTIVE', 'CORP-001', 'Corporation Executive', '{"budget":true,"appoint":true}', 30, 'member'),
  ('ROLE-CORP-TREASURER', 'CORP-001', 'Corporation Treasurer', '{"treasury":true}', 30, 'member'),
  ('ROLE-CITY-MAYOR', 'CITY-0084', 'City Mayor', '{"budget":true,"propose":true}', 30, 'resident'),
  ('ROLE-CITY-PLANNER', 'CITY-0084', 'Infrastructure Planner', '{"budget":true}', 30, 'resident');
