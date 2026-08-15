CREATE TABLE IF NOT EXISTS world_events (
  id TEXT PRIMARY KEY,
  game_day INTEGER NOT NULL,
  event_type TEXT NOT NULL,
  title TEXT NOT NULL,
  details TEXT NOT NULL DEFAULT '{}',
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS rankings_snapshots (
  id TEXT PRIMARY KEY,
  game_day INTEGER NOT NULL,
  ranking_type TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  rank INTEGER NOT NULL,
  score NUMERIC NOT NULL,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (game_day, ranking_type, entity_id)
);
CREATE TABLE IF NOT EXISTS deceased_profiles (
  human_id TEXT PRIMARY KEY REFERENCES humans(id),
  display_name TEXT NOT NULL,
  death_game_day INTEGER NOT NULL,
  final_standing INTEGER NOT NULL,
  final_legacy INTEGER NOT NULL,
  successor_name TEXT,
  archived_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS world_events_day_idx ON world_events(game_day DESC);
CREATE INDEX IF NOT EXISTS rankings_snapshots_type_idx ON rankings_snapshots(ranking_type, game_day DESC, rank);
