import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

const root = path.resolve('.');
const read = (file) => fs.readFileSync(path.resolve(root, file), 'utf8');

test('Building V2 authority audit is installed and integrity reporting preserves existing domains', () => {
  const migration = read('db/migrations/233_building_v2_authority_audit.sql');
  assert.match(migration, /CREATE OR REPLACE FUNCTION earth_building_v2_integrity/);
  for (const check of [
    'active_building_missing_economic_owner',
    'building_effect_without_journal',
    'building_journal_without_v2_effect',
    'building_profile_overlap_risk',
  ]) assert.match(migration, new RegExp(check));
  assert.match(migration, /earth_market_integrity_report/);
  assert.match(migration, /earth_finance_v2_integrity/);
});

test('Building V2 boundary documents the transitional overlap explicitly', () => {
  const docs = read('docs/BUILDING_ECONOMY_V2.md');
  assert.match(docs, /must not both apply the same building effect/);
  assert.match(docs, /`output_credits` must not be treated as money/);
  assert.match(docs, /only Economy V2 posting primitives may mutate economic balances/);
});

test('Building V2 planner is set-based and mutation-free', () => {
  const planner = read('db/migrations/234_building_settlement_planner.sql');
  assert.match(planner, /CREATE UNLOGGED TABLE IF NOT EXISTS building_settlement_plans/);
  assert.match(planner, /CREATE OR REPLACE FUNCTION earth_prepare_building_settlement/);
  assert.match(planner, /INSERT INTO building_settlement_plans/);
  assert.match(planner, /ON CONFLICT \(building_id, game_day\) DO UPDATE/);
  assert.doesNotMatch(planner, /UPDATE economic_accounts/);
  assert.doesNotMatch(planner, /UPDATE buildings/);
  assert.doesNotMatch(planner, /INSERT INTO economic_entries/);
});

test('Building V2 planning snapshots inputs by economic owner shard', () => {
  const migration = read('db/migrations/235_building_owner_shard_snapshots.sql');
  assert.match(migration, /CREATE UNLOGGED TABLE IF NOT EXISTS building_settlement_owner_inputs/);
  assert.match(migration, /CREATE OR REPLACE FUNCTION earth_prepare_building_owner_shard/);
  assert.match(migration, /earth_prepare_building_settlement\(p_game_day, p_shard\)/);
  assert.match(migration, /GROUP BY owner_economic_id/);
  assert.match(migration, /building_settlement_owner_inputs_shard_idx/);
});

test('Building V2 allocation is priority-aware and deterministic', () => {
  const migration = read('db/migrations/236_building_resource_allocation_policies.sql');
  assert.match(migration, /settlement_priority INTEGER NOT NULL DEFAULT 100/);
  assert.match(migration, /CREATE UNLOGGED TABLE IF NOT EXISTS building_settlement_allocations/);
  assert.match(migration, /earth_allocate_building_inputs/);
  assert.match(migration, /ORDER BY b\.remainder DESC, b\.building_id/);
  assert.match(migration, /settlement_priority DESC/);
  assert.doesNotMatch(migration, /UPDATE economic_accounts/);
  assert.doesNotMatch(migration, /UPDATE resource_balances/);
});

test('Building V2 utilization supports scalable, binary, and threshold operation', () => {
  const migration = read('db/migrations/237_building_utilization_modes.sql');
  assert.match(migration, /operation_mode TEXT NOT NULL DEFAULT 'SCALABLE'/);
  assert.match(migration, /minimum_operating_ratio/);
  assert.match(migration, /earth_finalize_building_utilization/);
  assert.match(migration, /WHEN 'BINARY'/);
  assert.match(migration, /WHEN 'THRESHOLD'/);
  assert.match(migration, /service_capacity/);
  assert.doesNotMatch(migration, /UPDATE economic_accounts/);
  assert.doesNotMatch(migration, /UPDATE resource_balances/);
});

test('Building V2 physical effects preserve exact debit and counterpart quantities', () => {
  const migration = read('db/migrations/238_building_exact_physical_effects.sql');
  assert.match(migration, /building_settlement_physical_effects/);
  assert.match(migration, /earth_compile_building_physical_effects/);
  assert.match(migration, /effect_kind IN \('CONSUMPTION', 'PRODUCTION'\)/);
  assert.match(migration, /counterparty_account_id/);
  assert.match(migration, /ROUND\(\(amounts\.amount\)::NUMERIC \* a\.scale\)/);
  assert.match(migration, /consumed_units = v\.consumed/);
  assert.match(migration, /produced_units = v\.produced/);
  assert.doesNotMatch(migration, /UPDATE economic_accounts/);
  assert.doesNotMatch(migration, /UPDATE resource_balances/);
});

test('Building V2 condition efficiency is versioned and affects output capacity', () => {
  const migration = read('db/migrations/239_building_condition_efficiency_curves.sql');
  assert.match(migration, /building_condition_efficiency_curves/);
  assert.match(migration, /condition_value NUMERIC/);
  assert.match(migration, /earth_condition_efficiency/);
  assert.match(migration, /earth_apply_building_condition_efficiency/);
  assert.match(migration, /WHEN lower_condition = upper_condition/);
  assert.match(migration, /p\.condition_efficiency/);
  assert.match(migration, /service_capacity = ROUND/);
  assert.doesNotMatch(migration, /UPDATE economic_accounts/);
  assert.doesNotMatch(migration, /UPDATE resource_balances/);
});

test('Building V2 separates wear, maintenance fulfillment, and repair points', () => {
  const migration = read('db/migrations/240_building_wear_maintenance_repair.sql');
  assert.match(migration, /base_condition_decay/);
  assert.match(migration, /maintenance_wear_multiplier/);
  assert.match(migration, /repair_target_condition/);
  assert.match(migration, /earth_finalize_building_condition/);
  assert.match(migration, /calculated_wear/);
  assert.match(migration, /calculated_repair/);
  assert.match(migration, /condition_before - c\.calculated_wear \+ c\.calculated_repair/);
  assert.doesNotMatch(migration, /UPDATE economic_accounts/);
  assert.doesNotMatch(migration, /UPDATE resource_balances/);
});

test('Building V2 exposes explicit repair targets and priorities', () => {
  const migration = read('db/migrations/241_building_repair_targets.sql');
  assert.match(migration, /auto_repair_target_condition/);
  assert.match(migration, /repair_priority/);
  assert.match(migration, /earth_apply_building_repair_policy/);
  assert.match(migration, /target_condition - s\.condition_before/);
  assert.match(migration, /condition_before - c\.wear \+ c\.repair_points/);
  assert.doesNotMatch(migration, /UPDATE economic_accounts/);
  assert.doesNotMatch(migration, /UPDATE resource_balances/);
});

test('Building V2 applies repair after today\'s efficiency and wear calculations', () => {
  const migration = read('db/migrations/242_building_daily_ordering.sql');
  assert.match(migration, /earth_finalize_building_utilization\(p_game_day, p_shard\)/);
  assert.match(migration, /earth_apply_building_condition_efficiency\(p_game_day, p_shard\)/);
  assert.match(migration, /earth_finalize_building_condition\(p_game_day, p_shard\)/);
  assert.match(migration, /earth_apply_building_repair_policy\(p_game_day, p_shard\)/);
  assert.match(migration, /repairs affect the next day/);
  assert.doesNotMatch(migration, /UPDATE economic_accounts/);
  assert.doesNotMatch(migration, /UPDATE resource_balances/);
});

test('Building V2 uses recoverable operational states', () => {
  const migration = read('db/migrations/243_building_operational_states.sql');
  assert.match(migration, /operational_state TEXT NOT NULL DEFAULT 'ACTIVE'/);
  assert.match(migration, /ACTIVE', 'DEGRADED', 'OFFLINE', 'DESTROYED/);
  assert.match(migration, /earth_finalize_building_operational_state/);
  assert.match(migration, /condition_after <= 0 THEN 'OFFLINE'/);
  assert.match(migration, /b\.status IN \('derelict', 'decommissioned'\).*'DESTROYED'/s);
  assert.match(migration, /OFFLINE buildings remain eligible for repair/);
});

test('Building V2 models services as capacity rather than monetary output', () => {
  const migration = read('db/migrations/244_building_service_economy.sql');
  assert.match(migration, /service_type TEXT/);
  assert.match(migration, /base_service_capacity_units BIGINT/);
  assert.match(migration, /default_price_credit_units BIGINT/);
  assert.match(migration, /service_mode TEXT/);
  assert.match(migration, /earth_finalize_building_service_economics/);
  assert.match(migration, /customer payments are separate funded transfers/);
  assert.match(migration, /Deprecated V1 field/);
});

test('Building V2 records explicit daily service demand before matching', () => {
  const migration = read('db/migrations/245_service_demand.sql');
  assert.match(migration, /CREATE TABLE IF NOT EXISTS service_demand/);
  assert.match(migration, /payer_economic_id BIGINT/);
  assert.match(migration, /requested_units BIGINT/);
  assert.match(migration, /max_price_units BIGINT/);
  assert.match(migration, /earth_prepare_service_demand/);
  assert.match(migration, /ON CONFLICT \(game_day, city_id, payer_economic_id, service_type\)/);
  assert.doesNotMatch(migration, /UPDATE economic_accounts/);
  assert.doesNotMatch(migration, /resource_balances/);
});

test('Building V2 distinguishes private, public-contract, and free services', () => {
  const migration = read('db/migrations/246_private_public_service_modes.sql');
  assert.match(migration, /PUBLIC_CONTRACT/);
  assert.match(migration, /service_mode = 'PRIVATE'/);
  assert.match(migration, /earth_prepare_public_service_funding/);
  assert.match(migration, /public_funding_units/);
  assert.match(migration, /funding_source_account_type/);
  assert.doesNotMatch(migration, /UPDATE economic_accounts/);
  assert.doesNotMatch(migration, /resource_balances/);
});

test('Building V2 matches service supply and demand set-wise by city and type', () => {
  const migration = read('db/migrations/247_setwise_service_matching.sql');
  assert.match(migration, /CREATE TABLE IF NOT EXISTS service_allocations/);
  assert.match(migration, /earth_match_service_demand/);
  assert.match(migration, /PARTITION BY d\.city_id, d\.service_type/);
  assert.match(migration, /PARTITION BY p\.city_id, p\.service_type/);
  assert.match(migration, /d\.priority DESC, d\.payer_economic_id/);
  assert.match(migration, /p\.default_price_credit_units, p\.condition_efficiency DESC, p\.building_id/);
  assert.doesNotMatch(migration, /UPDATE economic_accounts/);
  assert.doesNotMatch(migration, /resource_balances/);
});

test('Building V2 service payments are balanced and idempotent Economy V2 batches', () => {
  const migration = read('db/migrations/248_atomic_service_payments.sql');
  assert.match(migration, /CREATE TABLE IF NOT EXISTS service_payment_batches/);
  assert.match(migration, /CREATE TABLE IF NOT EXISTS service_payment_effects/);
  assert.match(migration, /earth_post_service_payment_batch/);
  assert.match(migration, /earth_post_settlement_batch/);
  assert.match(migration, /SUM\(delta\).*<> 0/);
  assert.match(migration, /service-settlement:%s:%s:%s/);
  assert.match(migration, /status = 'POSTED'/);
  assert.doesNotMatch(migration, /UPDATE account_balances/);
  assert.doesNotMatch(migration, /UPDATE resource_balances/);
});

test('Building V2 operating costs require explicit counterparties', () => {
  const migration = read('db/migrations/249_building_operating_cost_counterparties.sql');
  assert.match(migration, /operating_service_cost_units/);
  assert.match(migration, /operating_cost_recipient_type/);
  assert.match(migration, /operating_cost_recipient_account_id/);
  assert.match(migration, /earth_finalize_building_operating_costs/);
  assert.match(migration, /recipient_account_id IS NOT NULL/);
  assert.match(migration, /Deprecated V1 field/);
  assert.doesNotMatch(migration, /UPDATE account_balances/);
  assert.doesNotMatch(migration, /UPDATE resource_balances/);
});

test('Building V2 compiles auditable effects into one idempotent posting batch', () => {
  const migration = read('db/migrations/250_building_economic_effect_batch.sql');
  assert.match(migration, /CREATE TABLE IF NOT EXISTS building_economic_batches/);
  assert.match(migration, /CREATE TABLE IF NOT EXISTS building_economic_effects/);
  assert.match(migration, /earth_post_building_economic_batch/);
  assert.match(migration, /earth_post_settlement_batch/);
  assert.match(migration, /BUILDING_SERVICE_PAYMENT/);
  assert.match(migration, /BUILDING_OPERATING_COST/);
  assert.match(migration, /BUILDING_REPAIR_COST/);
  assert.match(migration, /building-settlement:%s:%s/);
  assert.match(migration, /is unbalanced/);
});

test('Building V2 settlement journal is a reproducible audit model', () => {
  const migration = read('db/migrations/251_building_settlement_journal_v2.sql');
  assert.match(migration, /ALTER TABLE building_settlement_journals/);
  assert.match(migration, /CREATE OR REPLACE FUNCTION earth_write_building_settlement_journal/);
  for (const field of [
    'condition_efficiency_ppm', 'requested_inputs', 'allocated_inputs', 'shortages',
    'utilization_ppm', 'base_output_units', 'actual_output_units',
    'service_capacity_units', 'service_units_sold', 'gross_service_revenue_units',
    'operating_expense_units', 'wear_points', 'repair_requested_points',
    'repair_applied_points', 'repair_resources', 'status_before', 'status_after',
    'economic_batch_id', 'correlation_id',
  ]) assert.match(migration, new RegExp(field));
  assert.match(migration, /FROM building_settlement_plans/);
  assert.match(migration, /ON CONFLICT \(building_id, day\) DO UPDATE/);
  assert.match(migration, /audit\/read model/);
  assert.doesNotMatch(migration, /UPDATE economic_accounts/);
  assert.doesNotMatch(migration, /UPDATE resource_balances/);
});

test('Building V2 exposes canonical fixed-point settlement values', () => {
  const migration = read('db/migrations/252_building_fixed_point_economics.sql');
  assert.match(migration, /CREATE OR REPLACE FUNCTION earth_ratio_to_ppm/);
  assert.match(migration, /CREATE OR REPLACE FUNCTION earth_condition_to_bp/);
  assert.match(migration, /CREATE OR REPLACE FUNCTION earth_multiplier_to_ppm/);
  assert.match(migration, /CREATE OR REPLACE FUNCTION earth_fixed_point_multiply_ppm/);
  for (const field of [
    'utilization_ppm', 'condition_efficiency_ppm', 'condition_before_bp',
    'condition_after_bp', 'wear_points_bp', 'repair_points_bp',
    'maintenance_fulfillment_ppm', 'repair_target_condition_bp',
  ]) assert.match(migration, new RegExp(`${field}[\\s\\S]*?GENERATED ALWAYS`));
  assert.match(migration, /ROUND\(\(p_left::NUMERIC \* p_right::NUMERIC\)/);
  assert.match(migration, /fixed-point columns are authoritative/);
  assert.doesNotMatch(migration, /double precision|real|float/i);
});

test('Building V2 pins economics to immutable game-day-effective rule versions', () => {
  const migration = read('db/migrations/253_building_economic_rule_versions.sql');
  assert.match(migration, /CREATE TABLE IF NOT EXISTS building_economic_rule_versions/);
  for (const field of [
    'rules_version', 'effective_from_game_day', 'effective_to_game_day',
    'production_recipes', 'upkeep', 'condition_curve_version',
    'condition_decay_ppm', 'repair_costs', 'service_capacity_units',
    'service_matching_rules',
  ]) assert.match(migration, new RegExp(field));
  assert.match(migration, /CREATE OR REPLACE FUNCTION earth_building_rules_version/);
  assert.match(migration, /effective_from_game_day <= p_game_day/);
  assert.match(migration, /CREATE OR REPLACE FUNCTION earth_pin_building_rules_for_day/);
  assert.match(migration, /PERFORM earth_pin_building_rules_for_day/);
  assert.match(migration, /Immutable building economics snapshots/);
});

test('Building V2 excludes building economics from generic daily profiles', () => {
  const migration = read('db/migrations/254_exclude_buildings_from_generic_profiles.sql');
  assert.match(migration, /includes_building_economics BOOLEAN NOT NULL DEFAULT FALSE/);
  assert.match(migration, /CREATE OR REPLACE FUNCTION earth_rebuild_dirty_profiles/);
  assert.match(migration, /includes_building_economics = FALSE/);
  assert.match(migration, /non-building-profile-v2/);
  assert.match(migration, /CREATE OR REPLACE FUNCTION earth_building_profile_overlap_integrity/);
  assert.match(migration, /building_effect_posted_by_both_paths/);
  assert.match(migration, /e\.phase = 'profile_settlement'/);
  assert.match(migration, /building_economic_effects/);
  assert.match(migration, /earth_building_profile_overlap_integrity/);
  assert.doesNotMatch(migration, /FROM building_catalog/);
  assert.doesNotMatch(migration, /UPDATE economic_accounts/);
});

test('Building V2 is the only production scheduler settlement implementation', () => {
  for (const sourcePath of ['cloudflare/src/scheduler.ts', 'cloudflare/src/scheduler-postgres.ts']) {
    const source = read(sourcePath);
    assert.doesNotMatch(source, /building-settlement-engine/);
  }
  assert.match(read('cloudflare/src/scheduler-postgres.ts'), /settleBuildingUpkeepAndRevenueV2/);
  const legacy = read('cloudflare/src/building-settlement-engine.ts');
  assert.match(legacy, /Legacy compatibility fixture only/);
});

test('Building V2 exposes one canonical ordered settlement pipeline', () => {
  const pipeline = read('cloudflare/src/building-settlement-pipeline.ts');
  const expected = [
    'select_eligible_buildings', 'resolve_rules_and_catalog_versions', 'snapshot_owner_inputs',
    'calculate_requirements', 'allocate_owner_resources', 'calculate_utilization',
    'calculate_start_of_day_condition_efficiency', 'calculate_physical_consumption',
    'calculate_physical_production', 'calculate_service_capacity', 'match_service_demand',
    'calculate_customer_funded_revenue', 'resolve_operating_expenses', 'calculate_operational_wear',
    'allocate_repair_resources', 'calculate_repair_points', 'calculate_end_of_day_condition_and_status',
    'compile_economic_effects', 'validate_conservation_and_non_negative_results', 'post_settlement_batch',
    'update_building_condition_and_status', 'insert_settlement_journals', 'complete_settlement_idempotency',
  ];
  const actual = [...pipeline.matchAll(/'([^']+)'/g)].map((match) => match[1]).slice(0, expected.length);
  assert.deepEqual(actual, expected);
  assert.ok(actual.indexOf('post_settlement_batch') < actual.indexOf('update_building_condition_and_status'));
  assert.ok(actual.indexOf('post_settlement_batch') < actual.indexOf('insert_settlement_journals'));
});
