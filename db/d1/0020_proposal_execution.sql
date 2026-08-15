ALTER TABLE proposals ADD COLUMN target_category TEXT;
ALTER TABLE proposals ADD COLUMN target_value_json TEXT;
ALTER TABLE proposals ADD COLUMN executed_at TEXT;
ALTER TABLE proposals ADD COLUMN execution_status TEXT NOT NULL DEFAULT 'not_ready' CHECK (execution_status IN ('not_ready','ready','executed','skipped'));
