ALTER TABLE succession_plans ADD COLUMN successor_human_id TEXT REFERENCES humans(id);
CREATE INDEX IF NOT EXISTS succession_successor_idx ON succession_plans(successor_human_id);
