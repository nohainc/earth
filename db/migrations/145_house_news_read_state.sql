-- EARTH ACTIVE MIGRATION: News read state is independent from Notifications

CREATE TABLE house_news_read_state (
  house_id TEXT PRIMARY KEY,
  last_seen_game_day BIGINT NOT NULL CHECK (last_seen_game_day >= 0),
  last_seen_game_minute INTEGER NOT NULL CHECK (last_seen_game_minute BETWEEN -1 AND 1439),
  last_seen_published_at TIMESTAMPTZ NOT NULL,
  last_seen_publication_id TEXT NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

