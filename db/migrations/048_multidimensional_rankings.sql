-- EARTH ACTIVE MIGRATION: versioned multidimensional rankings
CREATE TABLE IF NOT EXISTS ranking_metric_definitions (
  metric_code TEXT PRIMARY KEY,
  category TEXT NOT NULL CHECK (category IN ('HOUSE','ORGANIZATION','TERRITORY')),
  title TEXT NOT NULL,
  methodology TEXT NOT NULL,
  rules_version TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','RETIRED'))
);
CREATE TABLE IF NOT EXISTS ranking_snapshots (
  id TEXT PRIMARY KEY,
  metric_code TEXT NOT NULL REFERENCES ranking_metric_definitions(metric_code),
  scope TEXT NOT NULL,
  game_day BIGINT NOT NULL,
  rules_version TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (metric_code, scope, game_day)
);
CREATE TABLE IF NOT EXISTS ranking_snapshot_entries (
  snapshot_id TEXT NOT NULL REFERENCES ranking_snapshots(id) ON DELETE CASCADE,
  rank INTEGER NOT NULL CHECK (rank > 0),
  subject_type TEXT NOT NULL CHECK (subject_type IN ('HOUSE','ORGANIZATION','TERRITORY')),
  subject_id TEXT NOT NULL,
  subject_name TEXT NOT NULL,
  metric_value NUMERIC NOT NULL CHECK (metric_value >= 0),
  PRIMARY KEY (snapshot_id, rank),
  UNIQUE (snapshot_id, subject_id)
);
CREATE INDEX IF NOT EXISTS ranking_snapshots_metric_day_idx
  ON ranking_snapshots (metric_code, scope, game_day DESC);
CREATE INDEX IF NOT EXISTS ranking_snapshot_entries_subject_idx
  ON ranking_snapshot_entries (subject_type, subject_id, snapshot_id);

INSERT INTO ranking_metric_definitions (metric_code, category, title, methodology, rules_version) VALUES
 ('WEALTH','HOUSE','Wealth','Active House economic account balances across all assets; no composite weighting.','rankings-v1'),
 ('PRODUCTIVE_CAPACITY','HOUSE','Productive capacity','Active and under-construction buildings owned by the House.','rankings-v1'),
 ('LEGACY','HOUSE','Legacy','Dynasty legacy preserved through House succession.','rankings-v1'),
 ('TECHNOLOGY','HOUSE','Technology','Discovered patents and organization technology access available to the House.','rankings-v1'),
 ('PUBLIC_GOODS','HOUSE','Public-goods contribution','Escrowed contributions to public projects.','rankings-v1'),
 ('ORGANIZATION_SCALE','HOUSE','Organization scale','Active Organization memberships held by the House.','rankings-v1'),
 ('TERRITORY_QUALITY','HOUSE','Territory quality','Capacity and essential-service capacity at the House primary residence.','rankings-v1'),
 ('MARKET_ROLE','HOUSE','Market role','Settled market fills involving the House.','rankings-v1')
ON CONFLICT (metric_code) DO NOTHING;
