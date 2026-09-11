/** Canonical ordered Building Economy V2 settlement stages. */
export const BUILDING_SETTLEMENT_PIPELINE = Object.freeze([
  'select_eligible_buildings',
  'resolve_rules_and_catalog_versions',
  'snapshot_owner_inputs',
  'calculate_requirements',
  'allocate_owner_resources',
  'calculate_utilization',
  'calculate_physical_consumption',
  'calculate_physical_production',
  'calculate_service_capacity',
  'match_service_demand',
  'calculate_customer_funded_revenue',
  'resolve_operating_expenses',
  'compile_economic_effects',
  'validate_conservation_and_non_negative_results',
  'post_settlement_batch',
  'insert_settlement_journals',
  'complete_settlement_idempotency',
]);

export type BuildingSettlementPipelineStage = typeof BUILDING_SETTLEMENT_PIPELINE[number];
