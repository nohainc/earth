-- Plan 7: explain daily building operating cost without reintroducing repair,
-- depreciation, or maintenance-inventory mechanics.

CREATE OR REPLACE VIEW building_operating_cost_model AS
SELECT
  b.id AS catalog_id,
  b.building_type,
  b.tier,
  b.daily_credit_operating_cost,
  b.daily_resource_input_value,
  b.total_daily_cost,
  b.daily_output_reference_value,
  b.service_revenue_reference_value,
  b.expected_daily_revenue,
  b.operating_margin,
  CASE WHEN b.expected_daily_revenue > b.total_daily_cost THEN 'BASELINE_PROFITABLE'
       WHEN b.expected_daily_revenue = b.total_daily_cost THEN 'BASELINE_BREAK_EVEN'
       ELSE 'BASELINE_LOSS_MAKER' END AS baseline_status,
  jsonb_build_object(
    'credit_operating_expense', b.daily_credit_operating_cost,
    'resource_inputs_reference_value', b.daily_resource_input_value,
    'resource_output_reference_value', b.daily_output_reference_value,
    'service_revenue_reference_value', b.service_revenue_reference_value,
    'maintenance_model', 'included_in_credit_operating_expense'
  ) AS cost_explanation,
  CASE WHEN b.construction_reference_value > 0
    THEN ROUND(b.operating_margin::NUMERIC / b.construction_reference_value, 8)
    ELSE NULL END AS return_on_capital_per_day
FROM building_economic_balance_model b;
