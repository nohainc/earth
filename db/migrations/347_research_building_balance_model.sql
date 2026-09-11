-- Plan 9: balance research against a configurable benchmark corporation.
-- This is a read model only; it never advances projects or changes balances.

CREATE TABLE IF NOT EXISTS economic_research_balance_benchmarks (
  benchmark_id TEXT PRIMARY KEY,
  baseline_daily_research_capacity_units BIGINT NOT NULL CHECK (baseline_daily_research_capacity_units > 0),
  benchmark_daily_output_units JSONB NOT NULL DEFAULT '{}'::JSONB,
  effective_from_game_day BIGINT NOT NULL DEFAULT 0 CHECK (effective_from_game_day >= 0),
  effective_to_game_day BIGINT,
  balance_version TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CHECK (effective_to_game_day IS NULL OR effective_to_game_day >= effective_from_game_day)
);

INSERT INTO economic_research_balance_benchmarks
  (benchmark_id, baseline_daily_research_capacity_units, benchmark_daily_output_units, balance_version)
VALUES
  ('default', 250, '{"MATERIAL":5000,"COMPONENTS":5000,"ENERGY":5000,"COMPUTE":5000,"FOOD":5000}', 'balance-v1')
ON CONFLICT (benchmark_id) DO NOTHING;

CREATE OR REPLACE VIEW technology_economic_balance_model AS
WITH benchmark AS (
  SELECT DISTINCT ON (benchmark_id) *
  FROM economic_research_balance_benchmarks
  ORDER BY benchmark_id, effective_from_game_day DESC
), effects AS (
  SELECT technology_id, target_key AS asset, SUM(modifier_bps)::INTEGER AS modifier_bps
  FROM technology_effects
  WHERE effect_type = 'PRODUCTION_OUTPUT' AND target_type = 'ASSET'
  GROUP BY technology_id, target_key
), impact AS (
  SELECT t.id AS technology_id,
    COALESCE(SUM(ROUND((output.value::NUMERIC * COALESCE(e.modifier_bps, 0) / 10000)
      * COALESCE(r.reference_price_credit_units, 0))), 0) AS expected_daily_impact_value
  FROM technology_catalog t
  CROSS JOIN benchmark
  CROSS JOIN LATERAL jsonb_each_text(benchmark.benchmark_daily_output_units) output
  LEFT JOIN effects e ON e.technology_id = t.id AND e.asset = output.key
  LEFT JOIN economic_assets a ON a.code = output.key
  LEFT JOIN LATERAL (SELECT reference_price_credit_units FROM economic_reference_prices
    WHERE asset_id = a.id ORDER BY effective_from_game_day DESC LIMIT 1) r ON TRUE
  GROUP BY t.id
), prerequisites AS (
  SELECT technology_id, COUNT(*)::INTEGER AS prerequisite_count
  FROM technology_prerequisites GROUP BY technology_id
)
SELECT t.id AS technology_id, t.code, t.name, t.category, t.definition_version,
  t.research_credit_cost_units, t.research_points_required,
  benchmark.baseline_daily_research_capacity_units,
  CEIL(t.research_points_required::NUMERIC / benchmark.baseline_daily_research_capacity_units)::BIGINT AS expected_research_completion_days,
  ROUND(CEIL(t.research_points_required::NUMERIC / benchmark.baseline_daily_research_capacity_units) * 0.4, 2) AS expected_real_completion_hours,
  COALESCE(prerequisites.prerequisite_count, 0) AS prerequisite_count,
  impact.expected_daily_impact_value,
  CASE WHEN impact.expected_daily_impact_value > 0
    THEN ROUND(t.research_credit_cost_units::NUMERIC / impact.expected_daily_impact_value, 2) END AS economic_payback_game_days,
  CASE WHEN impact.expected_daily_impact_value > 0
    THEN ROUND(t.research_credit_cost_units::NUMERIC / impact.expected_daily_impact_value * 0.4, 2) END AS economic_payback_real_hours,
  CASE WHEN impact.expected_daily_impact_value > 0 THEN 'REVIEW_POSITIVE_IMPACT' ELSE 'NO_MODELED_OUTPUT_IMPACT' END AS balance_assessment,
  benchmark.balance_version
FROM technology_catalog t CROSS JOIN benchmark
LEFT JOIN impact ON impact.technology_id = t.id
LEFT JOIN prerequisites ON prerequisites.technology_id = t.id;
