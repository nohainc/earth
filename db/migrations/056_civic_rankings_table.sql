-- Migration 056: Civic Rankings Table for Periodic Relative Data-Driven Rankings
CREATE TABLE IF NOT EXISTS civic_rankings (
    id TEXT PRIMARY KEY,
    category TEXT NOT NULL,
    entity_id TEXT NOT NULL,
    entity_name TEXT NOT NULL,
    rank INTEGER NOT NULL,
    rank_delta INTEGER NOT NULL DEFAULT 0,
    final_score INTEGER NOT NULL,
    metrics_line TEXT NOT NULL,
    sub_indexes JSONB NOT NULL DEFAULT '{}',
    raw_metrics JSONB NOT NULL DEFAULT '{}',
    affiliation TEXT,
    game_day INTEGER NOT NULL DEFAULT 1,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_civic_rankings_entity UNIQUE (category, entity_id)
);

CREATE INDEX IF NOT EXISTS idx_civic_rankings_cat_score ON civic_rankings(category, final_score DESC, rank ASC);
