-- EARTH ACTIVE MIGRATION: explicit public News publication contract

CREATE TABLE news_publications (
  id TEXT PRIMARY KEY,
  publication_key TEXT NOT NULL UNIQUE,
  scope_type TEXT NOT NULL CHECK (scope_type IN ('EARTH', 'CORPORATION', 'COMMUNITY')),
  scope_id TEXT,
  scope_name TEXT,
  topic TEXT NOT NULL CHECK (topic IN ('GOVERNANCE', 'TECHNOLOGY', 'ECONOMY', 'INFRASTRUCTURE', 'SOCIETY', 'LIFECYCLE')),
  importance TEXT NOT NULL CHECK (importance IN ('MAJOR', 'NOTABLE', 'ROUTINE')),
  headline TEXT NOT NULL,
  summary TEXT NOT NULL,
  game_day BIGINT NOT NULL CHECK (game_day >= 0),
  game_minute INTEGER CHECK (game_minute IS NULL OR game_minute BETWEEN 0 AND 1439),
  related_entity_type TEXT,
  related_entity_id TEXT,
  related_entity_name TEXT,
  action_route TEXT,
  action_entity_id TEXT,
  action_label TEXT,
  published_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX news_publications_chronology_idx
  ON news_publications (game_day DESC, game_minute DESC NULLS LAST, published_at DESC, id DESC);

CREATE INDEX news_publications_scope_idx
  ON news_publications (scope_type, scope_id, game_day DESC, published_at DESC);
