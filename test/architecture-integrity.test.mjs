import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const read = (file) => fs.readFileSync(file, 'utf8');
const reference = read('db/baseline/03_reference_data.sql');
const schema = read('db/baseline/01_schema.sql');
const baselineFunctions = read('db/baseline/02_functions.sql');
const migration = read('db/migrations/005_architecture_integrity_report.sql');
const flowMigration = read('db/migrations/006_resource_flow_schema.sql');
const graphMigration = read('db/migrations/007_core_resource_graph_t1.sql');
const maintenanceMigration = read('db/migrations/008_house_food_maintenance.sql');
const construction = read('cloudflare/src/territory-capacity-postgres.ts');
const settlementMigration = read('db/migrations/009_private_building_settlement_journals.sql');
const marketMigration = read('db/migrations/010_market_state_completion.sql');
const analyticsMigration = read('db/migrations/011_resource_analytics_read_models.sql');
const integrityMigration = read('db/migrations/012_resource_economic_integrity.sql');
const settlement = read('cloudflare/src/building-settlement-v2.ts');

test('account capability matrix prevents institutions and actors from holding resources', () => {
  assert.match(reference, /\('HOUSE', 'INVENTORY', 'RESOURCE'/);
  for (const owner of ['CORPORATION', 'EARTH', 'BANK']) {
    assert.doesNotMatch(reference, new RegExp(`\\('${owner}', 'INVENTORY', 'RESOURCE'`));
  }
  for (const report of ['invalid_resource_inventory_owners', 'invalid_human_economic_accounts', 'invalid_territory_economic_accounts', 'invalid_building_economic_accounts']) {
    assert.match(migration, new RegExp(report));
  }
  assert.match(schema, /owner_economic_id TEXT NOT NULL REFERENCES owner_registry/);
});

test('building and market ownership rules are explicit', () => {
  assert.match(baselineFunctions, /Public infrastructure must be Corporation-owned/);
  assert.match(baselineFunctions, /Private buildings must be House-owned/);
  assert.match(baselineFunctions, /IF v_owner_type <> 'HOUSE'/);
  assert.match(migration, /invalid_private_building_owners/);
  assert.match(migration, /invalid_public_building_owners/);
  assert.match(migration, /invalid_public_catalog_resources/);
});

test('ledger semantics require balanced transfers and dedicated authorities', () => {
  assert.match(migration, /invalid_asset_transfer_balance/);
  assert.match(migration, /invalid_resource_production_authority/);
  assert.match(migration, /invalid_resource_consumption_authority/);
  assert.match(migration, /invalid_credit_issuance_authority/);
  assert.match(migration, /resource production requires SYSTEM_PRODUCTION authority/);
  assert.match(migration, /resource consumption requires SYSTEM_CONSUMPTION authority/);
  assert.match(migration, /CREDIT issuance requires SYSTEM_ISSUANCE authority/);
  assert.match(settlement, /'SYSTEM_PRODUCTION'/);
  assert.match(settlement, /'SYSTEM_CONSUMPTION'/);
});

test('public catalog cannot define persistent resource flows', () => {
  assert.match(migration, /resource_input_units <> '\{\}'::jsonb/);
  assert.match(migration, /resource_output_units <> '\{\}'::jsonb/);
  assert.match(migration, /service_type IS NULL/);
});

test('resource flows are normalized and resource-only', () => {
  assert.match(flowMigration, /CREATE TABLE building_catalog_resource_flows/);
  assert.match(flowMigration, /construction_units BIGINT NOT NULL DEFAULT 0 CHECK \(construction_units >= 0\)/);
  assert.match(flowMigration, /operating_input_units BIGINT NOT NULL DEFAULT 0 CHECK \(operating_input_units >= 0\)/);
  assert.match(flowMigration, /operating_output_units BIGINT NOT NULL DEFAULT 0 CHECK \(operating_output_units >= 0\)/);
  assert.match(flowMigration, /PRIMARY KEY \(catalog_id, asset_id\)/);
  assert.match(flowMigration, /v_asset_kind IS DISTINCT FROM 'RESOURCE'/);
  assert.match(flowMigration, /DROP COLUMN resource_input_units/);
  assert.match(flowMigration, /DROP COLUMN resource_output_units/);
});

test('T1 resource graph has one private producer for every resource', () => {
  for (const producer of ['MATERIAL-FAB-T1', 'ENERGY-PLANT-T1', 'COMPONENT-FAB-T1', 'COMPUTE-FAB-T1', 'FOOD-FARM-T1']) {
    assert.match(graphMigration, new RegExp(producer));
  }
  for (const resource of ['MATERIAL', 'ENERGY', 'COMPONENTS', 'COMPUTE', 'FOOD']) {
    assert.match(graphMigration, new RegExp(`\\"${resource}\\"`));
  }
  assert.match(graphMigration, /Core resource graph may only contain private buildings/);
  assert.doesNotMatch(graphMigration, /DISTRICT-MODULE-T1/);
  assert.doesNotMatch(graphMigration, /HOUSING-T1/);
  const settlement = read('cloudflare/src/building-settlement-v2.ts');
  assert.match(settlement, /building_catalog_resource_flows/);
  assert.doesNotMatch(settlement, /resource_input_units|resource_output_units/);
});

test('House FOOD maintenance has a persistent daily journal', () => {
  assert.match(maintenanceMigration, /CREATE TABLE personal_life_maintenance/);
  assert.match(maintenanceMigration, /food_required_units BIGINT/);
  assert.match(maintenanceMigration, /food_consumed_units BIGINT/);
  assert.match(maintenanceMigration, /food_shortfall_units BIGINT/);
  assert.match(maintenanceMigration, /UNIQUE \(human_id, game_day\)/);
  const source = read('cloudflare/src/life-maintenance-postgres.ts');
  assert.match(source, /RESOURCE_CONSUMPTION/);
  assert.match(source, /FOOD_REQUIRED_PER_HUMAN/);
  assert.match(source, /personal_life_maintenance/);
  const scheduler = read('cloudflare/src/scheduler-postgres.ts');
  assert.match(scheduler, /settleLifeMaintenanceInTransaction\(tx, day\)/);
});

test('private construction consumes construction resources atomically in Territory', () => {
  assert.match(construction, /construction_units/);
  assert.match(construction, /RESOURCE_CONSUMPTION/);
  assert.match(construction, /private_construction_resource_input/);
  assert.match(construction, /Insufficient \$\{missing\.code\} for construction/);
  assert.match(construction, /getConstructionQuote/);
  assert.match(construction, /missing_units/);
  assert.doesNotMatch(construction, /city_id|cities/);
});

test('private production is House-batched, proportional, and owner-sharded', () => {
  assert.match(settlementMigration, /CREATE TABLE building_settlement_journals/);
  const engine = read('cloudflare/src/building-settlement-v2.ts');
  assert.match(engine, /settlePrivateHouse/);
  assert.match(engine, /opening snapshot/);
  assert.match(engine, /utilizationFor/);
  assert.match(engine, /building-house:/);
  assert.match(engine, /building_settlement_journals/);
  assert.match(engine, /hashtextextended/);
  const phases = read('cloudflare/src/daily-settlement-phases.ts');
  assert.match(phases, /id: 'building_settlement', order: 75, shardMode: 'owner-shards'/);
});

test('market state exposes auction signals and a non-guaranteed genesis reference', () => {
  assert.match(marketMigration, /genesis_reference_price_units/);
  const state = read('cloudflare/src/market-state.ts');
  for (const field of ['last_clearing_price_units', 'best_bid_units', 'best_ask_units', 'open_buy_units', 'open_sell_units', 'rolling_volume_units']) assert.match(state, new RegExp(field));
  assert.match(state, /latest_fill/);
  const candles = read('cloudflare/src/market-candles.ts');
  assert.match(candles, /open_price_units/);
  assert.match(candles, /high_price_units/);
  assert.match(candles, /low_price_units/);
  assert.match(candles, /close_price_units/);
  const api = read('cloudflare/src/market-api.ts');
  assert.match(api, /genesisReferencePrice/);
});

test('starter economy is fixed, physical, and incomplete', () => {
  const starter = read('cloudflare/src/starter-package.ts');
  const auth = read('cloudflare/src/auth-postgres.ts');
  assert.match(starter, /STARTER_PACKAGE_V2/);
  assert.match(starter, /survivalDays: 14/);
  assert.match(starter, /immediatelySelfSufficient: false/);
  assert.doesNotMatch(starter, /economicStartIndex|marketPrice|livingCostIndex/);
  assert.match(auth, /unit_scale/);
  assert.doesNotMatch(auth, /calculateStarterPackage\(1, 1\)|marketPrice|economicStartIndex/);
});

test('resource analytics read models are guarded and player-readable', () => {
  assert.match(analyticsMigration, /CREATE TABLE global_resource_daily_state/);
  assert.match(analyticsMigration, /CREATE TABLE house_resource_daily_flow/);
  assert.match(analyticsMigration, /earth_validate_resource_analytics_owner/);
  const analytics = read('cloudflare/src/resource-analytics-postgres.ts');
  for (const field of ['production', 'consumption', 'net_flow', 'average_price_units', 'shortage_units']) assert.match(analytics, new RegExp(field));
  assert.match(analytics, /getHouseResourceAnalytics/);
  assert.match(analytics, /getGlobalResourceAnalytics/);
});

test('final physical economy integrity report covers the frozen invariants', () => {
  for (const check of ['every_tradable_resource_has_producer', 'every_resource_has_sink', 'compute_has_active_producer', 'food_maintenance_is_active', 'construction_and_operating_inputs_are_independent', 'private_producers_do_not_create_credit', 'public_infrastructure_does_not_produce_resources', 'daily_house_consumption_within_opening_balance', 'market_resource_transfers_balance', 'resource_production_consumption_reconcile_globally']) assert.match(integrityMigration, new RegExp(check));
  assert.match(integrityMigration, /earth_resource_economic_integrity_report/);
  const settlement = read('cloudflare/src/building-settlement-v2.ts');
  const flows = read('cloudflare/src/territory-capacity-postgres.ts');
  const mutation = read('cloudflare/src/resource-ledger-postgres.ts');
  assert.doesNotMatch(settlement, /all.?or.?nothing|resource_input_units|resource_output_units|output_credits/);
  assert.doesNotMatch(flows, /resource_input_units|resource_output_units|city_id|account_type\s*=\s*[123]/);
  assert.match(settlement, /utilizationFor/);
  assert.doesNotMatch(mutation, /legacy projection|mutateResourceBalanceInTransaction/);
});

test('resource economy simulator covers population, horizons, specialization, and stress scenarios', () => {
  const simulator = read('simulation/resource-economy-simulator.mjs');
  const runner = read('scripts/resource-economy-simulate.mjs');
  for (const metric of ['production', 'consumption', 'inventoryGrowth', 'shortageFrequency', 'averagePrices', 'averageUtilization', 'constructionStarted', 'wealth']) assert.match(simulator, new RegExp(metric));
  for (const scenario of ['energy-shortage', 'food-oversupply', 'compute-shortage', 'component-investment-boom', 'mass-new-player-arrival', 'generation-retrofit-boom']) assert.match(simulator, new RegExp(scenario));
  assert.match(runner, /100,1000,10000/);
  assert.match(runner, /1,10,30/);
});
