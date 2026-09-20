-- Full latest ranking population. Top-100 snapshots remain a cache/history projection.

CREATE TABLE IF NOT EXISTS latest_ranking_metric_values (
  metric_code TEXT NOT NULL REFERENCES ranking_metric_definitions(metric_code),
  subject_type TEXT NOT NULL CHECK (subject_type = 'HOUSE'),
  subject_id TEXT NOT NULL,
  subject_name TEXT NOT NULL,
  metric_value NUMERIC NOT NULL CHECK (metric_value >= 0),
  game_day BIGINT NOT NULL,
  rules_version TEXT NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (metric_code, subject_type, subject_id)
);

CREATE INDEX IF NOT EXISTS latest_ranking_metric_values_order_idx
  ON latest_ranking_metric_values (metric_code, game_day DESC, metric_value DESC, subject_id);

CREATE INDEX IF NOT EXISTS latest_ranking_metric_values_name_idx
  ON latest_ranking_metric_values (metric_code, subject_name, subject_id);
