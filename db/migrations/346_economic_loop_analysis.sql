-- Plan 8: read-only production graph and source/sink coverage diagnostics.
-- This analyzes catalog recipes; it never participates in settlement.

CREATE OR REPLACE VIEW economic_recipe_edges AS
SELECT bc.id AS catalog_id, bc.building_type, bc.tier,
  inputs.asset_code AS input_asset, outputs.asset_code AS output_asset,
  inputs.amount AS input_units, outputs.amount AS output_units,
  ROUND(inputs.amount * COALESCE(ip.reference_price_credit_units, 0)) AS input_reference_value,
  ROUND(outputs.amount * COALESCE(op.reference_price_credit_units, 0)) AS output_reference_value,
  ROUND((outputs.amount * COALESCE(op.reference_price_credit_units, 0)) /
    NULLIF(inputs.amount * COALESCE(ip.reference_price_credit_units, 0), 0), 8) AS value_multiplier
FROM building_catalog bc
CROSS JOIN LATERAL (VALUES
  ('MATERIAL', COALESCE(bc.upkeep_materials, 0)),
  ('COMPONENTS', COALESCE(bc.upkeep_components, 0)),
  ('ENERGY', COALESCE(bc.upkeep_energy, 0)),
  ('COMPUTE', COALESCE(bc.upkeep_compute, 0)),
  ('FOOD', COALESCE(bc.upkeep_food, 0))
) inputs(asset_code, amount)
CROSS JOIN LATERAL (VALUES
  ('MATERIAL', COALESCE(bc.output_materials, 0)),
  ('COMPONENTS', COALESCE(bc.output_components, 0)),
  ('ENERGY', COALESCE(bc.output_energy, 0)),
  ('COMPUTE', COALESCE(bc.output_compute, 0)),
  ('FOOD', COALESCE(bc.output_food, 0))
) outputs(asset_code, amount)
LEFT JOIN economic_assets ia ON ia.code = inputs.asset_code
LEFT JOIN economic_assets oa ON oa.code = outputs.asset_code
LEFT JOIN LATERAL (SELECT reference_price_credit_units FROM economic_reference_prices WHERE asset_id = ia.id ORDER BY effective_from_game_day DESC LIMIT 1) ip ON TRUE
LEFT JOIN LATERAL (SELECT reference_price_credit_units FROM economic_reference_prices WHERE asset_id = oa.id ORDER BY effective_from_game_day DESC LIMIT 1) op ON TRUE
WHERE inputs.amount > 0 AND outputs.amount > 0 AND inputs.asset_code <> outputs.asset_code;

CREATE OR REPLACE VIEW economic_recipe_cycles AS
WITH RECURSIVE walk(start_asset, current_asset, asset_path, value_multiplier, depth) AS (
  SELECT input_asset, output_asset, ARRAY[input_asset, output_asset], value_multiplier, 1
  FROM economic_recipe_edges
  UNION ALL
  SELECT w.start_asset, e.output_asset, w.asset_path || e.output_asset,
    w.value_multiplier * e.value_multiplier, w.depth + 1
  FROM walk w
  JOIN economic_recipe_edges e ON e.input_asset = w.current_asset
  WHERE w.depth < 6
    AND (e.output_asset = w.start_asset OR NOT e.output_asset = ANY(w.asset_path))
)
SELECT start_asset, asset_path, depth, value_multiplier,
  value_multiplier > 1 AS exceeds_reference_value,
  CASE WHEN value_multiplier > 1 THEN 'REVIEW_POSSIBLE_ARBITRAGE' ELSE 'NO_REFERENCE_VALUE_GROWTH' END AS assessment
FROM walk
WHERE current_asset = start_asset AND depth >= 2;

CREATE OR REPLACE VIEW economic_resource_flow_coverage AS
SELECT a.code AS asset,
  COALESCE((SELECT COUNT(*) FROM building_catalog b WHERE CASE a.code
    WHEN 'MATERIAL' THEN b.output_materials > 0 WHEN 'COMPONENTS' THEN b.output_components > 0
    WHEN 'ENERGY' THEN b.output_energy > 0 WHEN 'COMPUTE' THEN b.output_compute > 0 WHEN 'FOOD' THEN b.output_food > 0 ELSE FALSE END), 0) AS source_buildings,
  COALESCE((SELECT COUNT(*) FROM building_catalog b WHERE CASE a.code
    WHEN 'MATERIAL' THEN b.upkeep_materials > 0 OR b.cost_materials > 0 WHEN 'COMPONENTS' THEN b.upkeep_components > 0 OR b.cost_components > 0
    WHEN 'ENERGY' THEN b.upkeep_energy > 0 OR b.cost_energy > 0 WHEN 'COMPUTE' THEN b.upkeep_compute > 0 OR b.cost_compute > 0 WHEN 'FOOD' THEN b.upkeep_food > 0 OR b.cost_food > 0 ELSE FALSE END), 0) AS sink_buildings,
  CASE WHEN a.code = 'CREDIT' THEN 0 ELSE 1 END AS explicit_system_sources,
  CASE WHEN a.code = 'CREDIT' THEN 0 ELSE 1 END AS explicit_system_sinks,
  (a.code <> 'CREDIT') AS has_source_and_sink_model
FROM economic_assets a;
