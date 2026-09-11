-- Plan 4: canonical, read-only economic balance model.
-- Reference prices are development/balance inputs, never market prices and
-- never an authority for live account balances.

CREATE TABLE IF NOT EXISTS economic_reference_prices (
  asset_id SMALLINT NOT NULL REFERENCES economic_assets(id),
  reference_price_credit_units BIGINT NOT NULL CHECK (reference_price_credit_units >= 0),
  effective_from_game_day BIGINT NOT NULL DEFAULT 0 CHECK (effective_from_game_day >= 0),
  effective_to_game_day BIGINT,
  balance_version TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (asset_id, effective_from_game_day),
  CHECK (effective_to_game_day IS NULL OR effective_to_game_day >= effective_from_game_day)
);

INSERT INTO economic_reference_prices
  (asset_id, reference_price_credit_units, effective_from_game_day, balance_version)
VALUES
  (1, 100, 0, 'balance-v1'), (2, 40000, 0, 'balance-v1'),
  (3, 80000, 0, 'balance-v1'), (4, 10000, 0, 'balance-v1'),
  (5, 20000, 0, 'balance-v1'), (6, 5000, 0, 'balance-v1')
ON CONFLICT (asset_id, effective_from_game_day) DO NOTHING;

CREATE INDEX IF NOT EXISTS economic_reference_prices_effective_idx
  ON economic_reference_prices (asset_id, effective_from_game_day DESC);

CREATE OR REPLACE VIEW building_economic_balance_model AS
WITH reference_prices AS (
  SELECT DISTINCT ON (asset_id)
    asset_id, reference_price_credit_units, balance_version
  FROM economic_reference_prices
  ORDER BY asset_id, effective_from_game_day DESC
), metrics AS (
  SELECT
    bc.*,
    ROUND(COALESCE(bc.cost_credits, 0) * 100)
      + ROUND(COALESCE(bc.cost_materials, 0) * COALESCE(material.reference_price_credit_units, 0))
      + ROUND(COALESCE(bc.cost_components, 0) * COALESCE(components.reference_price_credit_units, 0))
      + ROUND(COALESCE(bc.cost_energy, 0) * COALESCE(energy.reference_price_credit_units, 0))
      + ROUND(COALESCE(bc.cost_compute, 0) * COALESCE(compute.reference_price_credit_units, 0))
      + ROUND(COALESCE(bc.cost_food, 0) * COALESCE(food.reference_price_credit_units, 0)) AS construction_reference_value,
    ROUND(COALESCE(bc.upkeep_materials, 0) * COALESCE(material.reference_price_credit_units, 0))
      + ROUND(COALESCE(bc.upkeep_components, 0) * COALESCE(components.reference_price_credit_units, 0))
      + ROUND(COALESCE(bc.upkeep_energy, 0) * COALESCE(energy.reference_price_credit_units, 0))
      + ROUND(COALESCE(bc.upkeep_compute, 0) * COALESCE(compute.reference_price_credit_units, 0))
      + ROUND(COALESCE(bc.upkeep_food, 0) * COALESCE(food.reference_price_credit_units, 0)) AS daily_resource_input_value,
    COALESCE(NULLIF(bc.operating_service_cost_units, 0), ROUND(COALESCE(bc.operating_credits, 0) * 100)) AS daily_credit_operating_cost,
    ROUND(COALESCE(bc.output_materials, 0) * COALESCE(material.reference_price_credit_units, 0))
      + ROUND(COALESCE(bc.output_components, 0) * COALESCE(components.reference_price_credit_units, 0))
      + ROUND(COALESCE(bc.output_energy, 0) * COALESCE(energy.reference_price_credit_units, 0))
      + ROUND(COALESCE(bc.output_compute, 0) * COALESCE(compute.reference_price_credit_units, 0))
      + ROUND(COALESCE(bc.output_food, 0) * COALESCE(food.reference_price_credit_units, 0)) AS daily_output_reference_value,
    COALESCE(bc.base_service_capacity_units, 0) * COALESCE(bc.default_price_credit_units, 0) AS service_revenue_reference_value,
    COALESCE(material.balance_version, components.balance_version, energy.balance_version, compute.balance_version, food.balance_version, 'balance-v1') AS balance_version
  FROM building_catalog bc
  LEFT JOIN reference_prices material ON material.asset_id = 2
  LEFT JOIN reference_prices components ON components.asset_id = 3
  LEFT JOIN reference_prices energy ON energy.asset_id = 4
  LEFT JOIN reference_prices compute ON compute.asset_id = 5
  LEFT JOIN reference_prices food ON food.asset_id = 6
)
SELECT metrics.*,
  daily_resource_input_value + daily_credit_operating_cost AS total_daily_cost,
  daily_output_reference_value + service_revenue_reference_value AS expected_daily_revenue,
  daily_output_reference_value - daily_resource_input_value AS gross_margin,
  daily_output_reference_value + service_revenue_reference_value - daily_resource_input_value - daily_credit_operating_cost AS operating_margin,
  CASE WHEN daily_output_reference_value + service_revenue_reference_value - daily_resource_input_value - daily_credit_operating_cost > 0
    THEN ROUND(construction_reference_value::NUMERIC / (daily_output_reference_value + service_revenue_reference_value - daily_resource_input_value - daily_credit_operating_cost)) END AS payback_game_days,
  CASE WHEN daily_output_reference_value + service_revenue_reference_value - daily_resource_input_value - daily_credit_operating_cost > 0
    THEN ROUND((construction_reference_value::NUMERIC / (daily_output_reference_value + service_revenue_reference_value - daily_resource_input_value - daily_credit_operating_cost)) * 0.4, 2) END AS payback_real_hours,
  CASE WHEN construction_reference_value > 0 THEN ROUND((daily_output_reference_value + service_revenue_reference_value - daily_resource_input_value - daily_credit_operating_cost)::NUMERIC / construction_reference_value, 8) END AS return_on_capital_per_day,
  CASE WHEN slot_footprint > 0 THEN ROUND((daily_output_reference_value + service_revenue_reference_value)::NUMERIC / slot_footprint, 2) END AS output_per_slot,
  CASE WHEN slot_footprint > 0 THEN ROUND((daily_output_reference_value + service_revenue_reference_value - daily_resource_input_value - daily_credit_operating_cost)::NUMERIC / slot_footprint, 2) END AS profit_per_slot
FROM metrics;

-- A later tier is flagged when it is strictly superior on every core balance
-- axis while being no more expensive, slower, or input-intensive. This is a
-- diagnostic, not an automatic balance change: intentional dominance remains
-- a design decision that must be reviewed.
CREATE OR REPLACE VIEW building_tier_balance_flags AS
SELECT
  lower_tier.building_type AS building_family,
  lower_tier.tier AS lower_tier,
  higher_tier.tier AS higher_tier,
  higher_tier.construction_reference_value < lower_tier.construction_reference_value AS costs_less,
  higher_tier.construction_days <= lower_tier.construction_days AS builds_no_slower,
  higher_tier.daily_resource_input_value <= lower_tier.daily_resource_input_value AS consumes_no_more,
  higher_tier.expected_daily_revenue >= lower_tier.expected_daily_revenue AS produces_no_less,
  (higher_tier.construction_reference_value < lower_tier.construction_reference_value
   AND higher_tier.construction_days <= lower_tier.construction_days
   AND higher_tier.daily_resource_input_value <= lower_tier.daily_resource_input_value
   AND higher_tier.expected_daily_revenue >= lower_tier.expected_daily_revenue
   AND (higher_tier.construction_reference_value < lower_tier.construction_reference_value
     OR higher_tier.construction_days < lower_tier.construction_days
     OR higher_tier.daily_resource_input_value < lower_tier.daily_resource_input_value
     OR higher_tier.expected_daily_revenue > lower_tier.expected_daily_revenue)) AS unintended_dominance
FROM building_economic_balance_model lower_tier
JOIN building_economic_balance_model higher_tier
  ON higher_tier.building_type = lower_tier.building_type
 AND higher_tier.tier > lower_tier.tier;
