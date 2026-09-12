-- Building Economy V2: remove condition, wear and repair gameplay.
-- Historical migrations remain append-only; fresh installs use schema.sql.
DROP TABLE IF EXISTS building_condition_efficiency_curves;

ALTER TABLE buildings
  DROP COLUMN IF EXISTS condition,
  DROP COLUMN IF EXISTS auto_repair_enabled,
  DROP COLUMN IF EXISTS auto_repair_target_condition,
  DROP COLUMN IF EXISTS repair_priority;

ALTER TABLE building_settlement_journals
  DROP COLUMN IF EXISTS condition_start,
  DROP COLUMN IF EXISTS condition_end,
  DROP COLUMN IF EXISTS auto_repaired,
  DROP COLUMN IF EXISTS condition_efficiency_ppm,
  DROP COLUMN IF EXISTS wear_points,
  DROP COLUMN IF EXISTS repair_requested_points,
  DROP COLUMN IF EXISTS repair_applied_points,
  DROP COLUMN IF EXISTS repair_resources;

-- Drop generated fixed-point projections before their condition/repair source
-- columns; PostgreSQL otherwise rejects the dependency change.
ALTER TABLE building_settlement_plans
  DROP COLUMN IF EXISTS condition_efficiency_ppm,
  DROP COLUMN IF EXISTS condition_before_bp,
  DROP COLUMN IF EXISTS condition_after_bp,
  DROP COLUMN IF EXISTS wear_points_bp,
  DROP COLUMN IF EXISTS repair_points_bp,
  DROP COLUMN IF EXISTS maintenance_fulfillment_ppm,
  DROP COLUMN IF EXISTS repair_target_condition_bp;

ALTER TABLE building_settlement_plans
  DROP COLUMN IF EXISTS condition_efficiency,
  DROP COLUMN IF EXISTS condition_before,
  DROP COLUMN IF EXISTS condition_after,
  DROP COLUMN IF EXISTS wear,
  DROP COLUMN IF EXISTS repair_points,
  DROP COLUMN IF EXISTS condition_curve_version,
  DROP COLUMN IF EXISTS maintenance_fulfillment,
  DROP COLUMN IF EXISTS auto_repair_enabled,
  DROP COLUMN IF EXISTS repair_target_condition,
  DROP COLUMN IF EXISTS repair_priority;

ALTER TABLE building_catalog
  DROP COLUMN IF EXISTS base_condition_decay_ppm,
  DROP COLUMN IF EXISTS maintenance_wear_multiplier_ppm,
  DROP COLUMN IF EXISTS repair_materials_per_point_ppm,
  DROP COLUMN IF EXISTS repair_components_per_point_ppm;

ALTER TABLE building_catalog
  DROP COLUMN IF EXISTS condition_curve_version,
  DROP COLUMN IF EXISTS base_condition_decay,
  DROP COLUMN IF EXISTS base_condition_decay_ppm,
  DROP COLUMN IF EXISTS maintenance_wear_multiplier,
  DROP COLUMN IF EXISTS maintenance_wear_multiplier_ppm,
  DROP COLUMN IF EXISTS repair_target_condition,
  DROP COLUMN IF EXISTS repair_materials_per_point,
  DROP COLUMN IF EXISTS repair_components_per_point,
  DROP COLUMN IF EXISTS repair_materials_per_point_ppm;

ALTER TABLE building_economic_rule_versions
  DROP COLUMN IF EXISTS condition_curve_version,
  DROP COLUMN IF EXISTS condition_decay_ppm,
  DROP COLUMN IF EXISTS repair_costs;

ALTER TABLE corporation_technology_modifier_cache DROP COLUMN IF EXISTS wear_bps;
DELETE FROM technology_effects
WHERE effect_type IN ('BUILDING_WEAR', 'REPAIR_EFFICIENCY');
ALTER TABLE technology_effects DROP CONSTRAINT IF EXISTS technology_effects_effect_type_check;
ALTER TABLE technology_effects ADD CONSTRAINT technology_effects_effect_type_check CHECK (effect_type IN ('PRODUCTION_OUTPUT','RESOURCE_INPUT','CONSTRUCTION_TIME','CONSTRUCTION_RESOURCE_COST','RESEARCH_CAPACITY','SERVICE_CAPACITY','ENERGY_INPUT'));
