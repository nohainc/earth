-- EARTH ACTIVE MIGRATION: provisional private T1 resource graph

-- The five core producers are private House buildings. Housing and service
-- definitions intentionally remain outside this graph.
INSERT INTO building_catalog (
  id, code, tier, ownership_scope, construction_credit_units, construction_minutes,
  operating_credit_units, service_type, service_capacity_units, slot_footprint, definition_version
) VALUES (
  'COMPUTE-FAB-T1', 'compute_fab_t1', 1, 'PRIVATE', 90000, 2160,
  500, NULL, 0, 2, 'resource-graph-t1'
)
ON CONFLICT (id) DO UPDATE SET
  code = EXCLUDED.code,
  ownership_scope = EXCLUDED.ownership_scope,
  definition_version = EXCLUDED.definition_version;

WITH definitions(catalog_id, inputs, outputs) AS (
  VALUES
    ('MATERIAL-FAB-T1', '{}'::JSONB, '{"MATERIAL":100}'::JSONB),
    ('ENERGY-PLANT-T1', '{"MATERIAL":5}'::JSONB, '{"ENERGY":120}'::JSONB),
    ('COMPONENT-FAB-T1', '{"MATERIAL":25,"ENERGY":20}'::JSONB, '{"COMPONENTS":50}'::JSONB),
    ('COMPUTE-FAB-T1', '{"ENERGY":30,"COMPONENTS":5}'::JSONB, '{"COMPUTE":40}'::JSONB),
    ('FOOD-FARM-T1', '{"MATERIAL":10,"ENERGY":8}'::JSONB, '{"FOOD":80}'::JSONB)
), flow_rows AS (
  SELECT d.catalog_id, a.id AS asset_id,
         0::BIGINT AS construction_units,
         COALESCE((d.inputs ->> a.code)::BIGINT, 0) AS operating_input_units,
         COALESCE((d.outputs ->> a.code)::BIGINT, 0) AS operating_output_units
    FROM definitions d
    CROSS JOIN economic_assets a
   WHERE a.asset_kind = 'RESOURCE'
     AND (d.inputs ? a.code OR d.outputs ? a.code)
)
INSERT INTO building_catalog_resource_flows
  (catalog_id, asset_id, construction_units, operating_input_units, operating_output_units)
SELECT catalog_id, asset_id, construction_units, operating_input_units, operating_output_units
  FROM flow_rows
ON CONFLICT (catalog_id, asset_id) DO UPDATE
SET operating_input_units = EXCLUDED.operating_input_units,
    operating_output_units = EXCLUDED.operating_output_units;

UPDATE building_catalog
   SET definition_version = 'resource-graph-t1'
 WHERE id IN ('MATERIAL-FAB-T1', 'ENERGY-PLANT-T1', 'COMPONENT-FAB-T1', 'COMPUTE-FAB-T1', 'FOOD-FARM-T1');

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
      FROM building_catalog_resource_flows f
      JOIN building_catalog c ON c.id = f.catalog_id
     WHERE c.ownership_scope <> 'PRIVATE'
  ) THEN
    RAISE EXCEPTION 'Core resource graph may only contain private buildings';
  END IF;
END;
$$;
