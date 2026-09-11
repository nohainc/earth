import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

test('technology definitions are database-authoritative and versioned', () => {
  const migration = fs.readFileSync(path.resolve('db/migrations/255_technology_catalog.sql'), 'utf8');
  const source = fs.readFileSync(path.resolve('cloudflare/src/technology-postgres.ts'), 'utf8');
  assert.match(migration, /CREATE TABLE IF NOT EXISTS technology_catalog/);
  for (const field of ['category', 'patentable', 'patent_exclusivity_days', 'research_credit_cost_units', 'research_points_required', 'definition_version', 'effective_from_game_day', 'effective_to_game_day']) assert.match(migration, new RegExp(field));
  assert.match(migration, /INSERT INTO technology_catalog/);
  assert.doesNotMatch(source, /Automated Assembly/);
  assert.doesNotMatch(source, /researchCost:/);
  assert.doesNotMatch(source, /subscriptionCost:/);
  assert.match(source, /FROM technology_catalog/);
});

test('technology effects are normalized, typed, and basis-point based', () => {
  const migration = fs.readFileSync(path.resolve('db/migrations/256_technology_effects.sql'), 'utf8');
  for (const effectType of ['PRODUCTION_OUTPUT', 'RESOURCE_INPUT', 'CONSTRUCTION_TIME', 'CONSTRUCTION_RESOURCE_COST', 'BUILDING_WEAR', 'REPAIR_EFFICIENCY', 'RESEARCH_CAPACITY', 'SERVICE_CAPACITY', 'ENERGY_INPUT']) assert.match(migration, new RegExp(effectType));
  assert.match(migration, /technology_id TEXT NOT NULL REFERENCES technology_catalog/);
  assert.match(migration, /modifier_bps INTEGER NOT NULL/);
  assert.match(migration, /UNIQUE \(technology_id, effect_type, target_type, target_key\)/);
  assert.match(migration, /Predictive Maintenance|TECH-PREDICTIVE-MAINTENANCE-V1/);
});

test('technology modifiers stack additively and are capped by family rules', () => {
  const migration = fs.readFileSync(path.resolve('db/migrations/257_technology_modifier_rules.sql'), 'utf8');
  assert.match(migration, /stacking_mode TEXT NOT NULL DEFAULT 'ADDITIVE_BPS'/);
  assert.match(migration, /CHECK \(stacking_mode = 'ADDITIVE_BPS'\)/);
  assert.match(migration, /minimum_bps INTEGER NOT NULL/);
  assert.match(migration, /maximum_bps INTEGER NOT NULL/);
  assert.match(migration, /SUM\(e\.modifier_bps\)/);
  assert.match(migration, /LEAST\(r\.maximum_bps, GREATEST\(r\.minimum_bps/);
  assert.doesNotMatch(migration, /\*.*modifier|POWER\(|exp\(/i);
});

test('corporation research uses one typed project model for both target kinds', () => {
  const migration = fs.readFileSync(path.resolve('db/migrations/258_corporation_research_projects.sql'), 'utf8');
  const technologySource = fs.readFileSync(path.resolve('cloudflare/src/technology-postgres.ts'), 'utf8');
  const buildingSource = fs.readFileSync(path.resolve('cloudflare/src/corporation-building-research-postgres.ts'), 'utf8');
  assert.match(migration, /CREATE TABLE IF NOT EXISTS corporation_research_projects/);
  assert.match(migration, /target_type TEXT NOT NULL CHECK \(target_type IN \('TECHNOLOGY', 'BUILDING_BLUEPRINT'\)\)/);
  for (const field of ['corporation_economic_id', 'target_id', 'definition_version', 'required_research_points', 'progress_research_points', 'credit_cost_units', 'priority', 'correlation_id']) assert.match(migration, new RegExp(field));
  assert.match(migration, /INSERT INTO corporation_research_projects/);
  assert.match(technologySource, /target_type, target_id, definition_version/);
  assert.match(buildingSource, /'BUILDING_BLUEPRINT'/);
});

test('research progress is driven by condition- and utilization-adjusted capacity', () => {
  const migration = fs.readFileSync(path.resolve('db/migrations/259_research_capacity.sql'), 'utf8');
  assert.match(migration, /research_capacity_units_per_day BIGINT/);
  assert.match(migration, /research_points_generated BIGINT/);
  assert.match(migration, /COALESCE\(p\.utilization, 1\)/);
  assert.match(migration, /COALESCE\(p\.condition_efficiency, 1\)/);
  assert.match(migration, /earth_advance_corporation_research_v2/);
  assert.match(migration, /ROW_NUMBER\(\) OVER/);
  assert.match(migration, /p\.priority DESC/);
  assert.match(migration, /status = CASE WHEN p\.progress_research_points/);
  const scheduler = fs.readFileSync(path.resolve('cloudflare/src/scheduler-postgres.ts'), 'utf8');
  assert.match(scheduler, /earth_settle_research_and_progress_v2/);
  assert.doesNotMatch(scheduler, /progress = LEAST\(100, progress \+/);
});

test('research scheduler finalizes completion effects as next-day V2 state', () => {
  const migration = fs.readFileSync(path.resolve('db/migrations/289_research_scheduler_v2.sql'), 'utf8');
  const scheduler = fs.readFileSync(path.resolve('cloudflare/src/scheduler-postgres.ts'), 'utf8');
  const automation = fs.readFileSync(path.resolve('cloudflare/src/daily-automation.ts'), 'utf8');
  assert.match(migration, /earth_settle_research_and_progress_v2/);
  assert.match(migration, /earth_record_corporation_research_capacity/);
  assert.match(migration, /earth_advance_corporation_research_v2/);
  assert.match(migration, /p_game_day \+ 1/);
  assert.match(migration, /corporation_technology_access/);
  assert.match(migration, /technology_patents/);
  assert.match(migration, /corporation_building_unlocks/);
  assert.match(migration, /RESEARCH_COMPLETED/);
  assert.match(scheduler, /earth_settle_research_and_progress_v2/);
  assert.doesNotMatch(automation, /earth_advance_corporation_research_v2/);
  assert.doesNotMatch(automation, /UPDATE corporation_technology_projects/);
});

test('research capacity remains a non-tradable institutional projection', () => {
  const migration = fs.readFileSync(path.resolve('db/migrations/260_research_capacity_projection.sql'), 'utf8');
  const manifest = JSON.parse(fs.readFileSync(path.resolve('db/schema-manifest.json'), 'utf8'));
  assert.match(migration, /corporation_research_capacity_daily/);
  assert.match(migration, /earth_record_corporation_research_capacity/);
  assert.match(migration, /research points are not an economic asset or tradable inventory/i);
  assert.doesNotMatch(migration, /economic_assets|market_instruments|economic_accounts/);
  assert.ok(!manifest.requiredTables.corporation_research_capacity_daily.includes('asset_id'));
  assert.ok(!manifest.requiredTables.corporation_research_capacity_daily.includes('account_id'));
});

test('research allocation enforces one active project per corporation', () => {
  const migration = fs.readFileSync(path.resolve('db/migrations/261_research_project_priority.sql'), 'utf8');
  assert.match(migration, /ROW_NUMBER\(\) OVER/);
  assert.match(migration, /PARTITION BY corporation_economic_id/);
  assert.match(migration, /ORDER BY priority DESC, created_at, id/);
  assert.match(migration, /SET status = 'QUEUED'/);
  assert.match(migration, /CREATE UNIQUE INDEX IF NOT EXISTS corporation_research_one_active_idx/);
  assert.match(migration, /WHERE status = 'ACTIVE'/);
});

test('research funding is Economy V2-only and active projects must be funded', () => {
  const migration = fs.readFileSync(path.resolve('db/migrations/262_research_economy_funding.sql'), 'utf8');
  const technologySource = fs.readFileSync(path.resolve('cloudflare/src/technology-postgres.ts'), 'utf8');
  const buildingSource = fs.readFileSync(path.resolve('cloudflare/src/corporation-building-research-postgres.ts'), 'utf8');
  const researchSource = technologySource.slice(
    technologySource.indexOf('export async function createResearchProject'),
    technologySource.indexOf('export async function fundResearchProject'),
  );
  assert.match(migration, /funding_transaction_id BIGINT REFERENCES economic_transactions/);
  assert.match(migration, /status <> 'ACTIVE' OR funding_transaction_id IS NOT NULL/);
  assert.match(technologySource, /earth_post_transaction/);
  assert.match(technologySource, /funding_transaction_id/);
  assert.doesNotMatch(researchSource, /FROM account_balances/);
  assert.match(buildingSource, /earth_post_transaction/);
  assert.match(buildingSource, /funding_transaction_id/);
  assert.doesNotMatch(buildingSource, /FROM account_balances/);
});

test('building research unlocks authored tiers without generating catalog economics', () => {
  const migration = fs.readFileSync(path.resolve('db/migrations/263_predefined_building_tiers.sql'), 'utf8');
  const source = fs.readFileSync(path.resolve('cloudflare/src/corporation-building-research-postgres.ts'), 'utf8');
  const automation = fs.readFileSync(path.resolve('cloudflare/src/daily-automation.ts'), 'utf8');
  assert.match(migration, /tier BETWEEN 1 AND 5/);
  assert.match(migration, /building_catalog_type_tier_uq/);
  assert.match(source, /Predefined Tier/);
  assert.match(source, /FROM building_catalog WHERE id = \$1 AND building_type = \$2/);
  assert.doesNotMatch(source, /INSERT INTO building_catalog/);
  assert.doesNotMatch(automation, /UPDATE building_catalog SET is_active/);
});

test('corporation technology access is day-effective and research-backed', () => {
  const migration = fs.readFileSync(path.resolve('db/migrations/264_corporation_technology_access.sql'), 'utf8');
  const schedulerMigration = fs.readFileSync(path.resolve('db/migrations/289_research_scheduler_v2.sql'), 'utf8');
  const manifest = JSON.parse(fs.readFileSync(path.resolve('db/schema-manifest.json'), 'utf8'));
  assert.match(migration, /CREATE TABLE IF NOT EXISTS corporation_technology_access/);
  for (const source of ['RESEARCHED', 'LICENSED', 'GRANTED']) assert.match(migration, new RegExp(source));
  assert.match(migration, /effective_from_game_day/);
  assert.match(migration, /earth_sync_corporation_researched_technology_access/);
  assert.match(migration, /earth_corporation_has_technology_access/);
  assert.match(migration, /earth_grant_corporation_technology_access/);
  assert.match(migration, /target_type = 'TECHNOLOGY'/);
  assert.match(schedulerMigration, /earth_sync_corporation_researched_technology_access/);
  assert.ok(manifest.requiredTables.corporation_technology_access);
  assert.ok(manifest.requiredIndexes.includes('corporation_technology_access_lookup_idx'));
  assert.ok(manifest.requiredIndexes.includes('corporation_technology_access_expiry_idx'));
});

test('industrial technology does not use human adoption or subscription layers', () => {
  const migration = fs.readFileSync(path.resolve('db/migrations/265_remove_industrial_human_technology_access.sql'), 'utf8');
  const technologySource = fs.readFileSync(path.resolve('cloudflare/src/technology-postgres.ts'), 'utf8');
  const worldSource = fs.readFileSync(path.resolve('cloudflare/src/world-postgres.ts'), 'utf8');
  assert.match(migration, /DROP TABLE IF EXISTS human_technology_subscriptions/);
  assert.match(migration, /DROP TABLE IF EXISTS human_technology_adoptions/);
  assert.match(migration, /DROP TABLE IF EXISTS corporation_technology_shares/);
  for (const source of [technologySource, worldSource]) {
    assert.doesNotMatch(source, /human_technology_adoptions|human_technology_subscriptions|corporation_technology_shares/);
  }
});

test('private building technology follows current corporation membership', () => {
  const migration = fs.readFileSync(path.resolve('db/migrations/266_private_building_corporation_access.sql'), 'utf8');
  const source = fs.readFileSync(path.resolve('cloudflare/src/building-settlement-v2.ts'), 'utf8');
  assert.match(migration, /earth_building_corporation_economic_id/);
  assert.match(migration, /b\.ownership_class = 'private'/);
  assert.match(migration, /membership\.human_id = b\.owner_id/);
  assert.match(source, /earth_building_corporation_economic_id\(b\.id\)/);
  assert.match(source, /corporation_technology_modifier_cache/);
  assert.match(source, /cache\.game_day = \$1/);
});

test('technology modifiers are rebuilt in a corporation-day cache before building settlement', () => {
  const migration = fs.readFileSync(path.resolve('db/migrations/267_corporation_technology_modifier_cache.sql'), 'utf8');
  const buildingSource = fs.readFileSync(path.resolve('cloudflare/src/building-settlement-v2.ts'), 'utf8');
  const schedulerSource = fs.readFileSync(path.resolve('cloudflare/src/scheduler-postgres.ts'), 'utf8');
  const manifest = JSON.parse(fs.readFileSync(path.resolve('db/schema-manifest.json'), 'utf8'));
  assert.match(migration, /corporation_technology_modifier_cache/);
  assert.match(migration, /earth_rebuild_corporation_technology_modifier_cache/);
  assert.match(migration, /scoped_modifiers JSONB/);
  assert.match(migration, /LEAST\(rule\.maximum_bps, GREATEST\(rule\.minimum_bps/);
  assert.match(buildingSource, /LEFT JOIN corporation_technology_modifier_cache cache/);
  assert.doesNotMatch(buildingSource, /FROM technology_effects e/);
  assert.match(schedulerSource, /earth_rebuild_corporation_technology_modifier_cache/);
  assert.ok(manifest.requiredTables.corporation_technology_modifier_cache);
  assert.ok(manifest.requiredIndexes.includes('corporation_technology_modifier_cache_day_idx'));
});

test('Building V2 applies technology modifiers to every economic term', () => {
  const source = fs.readFileSync(path.resolve('cloudflare/src/building-settlement-v2.ts'), 'utf8');
  assert.match(source, /earth_condition_efficiency\(b\.condition/);
  assert.match(source, /conditionEfficiency/);
  assert.match(source, /inputMultiplier\('ENERGY'\)/);
  assert.match(source, /inputMultiplier\('MATERIAL'\)/);
  assert.match(source, /modifier\('PRODUCTION_OUTPUT'/);
  assert.match(source, /modifier\('SERVICE_CAPACITY'/);
  assert.match(source, /modifier\('BUILDING_WEAR'/);
  assert.match(source, /modifier\('REPAIR_EFFICIENCY'/);
  assert.match(source, /conditionDelta = -baseWear \* wearMultiplier/);
});

test('construction snapshots technology terms at project start', () => {
  const migration = fs.readFileSync(path.resolve('db/migrations/268_building_construction_technology_snapshots.sql'), 'utf8');
  const source = fs.readFileSync(path.resolve('cloudflare/src/real-estate-postgres.ts'), 'utf8');
  assert.match(migration, /construction_technology_modifiers JSONB/);
  assert.match(migration, /construction_duration_minutes BIGINT/);
  for (const field of ['construction_cost_credits_units', 'construction_cost_material_units', 'construction_cost_components_units', 'construction_cost_compute_units']) assert.match(migration, new RegExp(field));
  assert.match(source, /resolveConstructionTechnology\(tx, input\.ownerId, day\)/);
  assert.match(source, /CONSTRUCTION_TIME/);
  assert.match(source, /CONSTRUCTION_RESOURCE_COST/);
  assert.match(source, /construction_technology_modifiers/);
  assert.match(source, /construction_duration_minutes/);
  assert.match(source, /construction_cost_material_units/);
});

test('research capacity uses the day-effective technology cache', () => {
  const migration = fs.readFileSync(path.resolve('db/migrations/269_research_technology_modifier_cache.sql'), 'utf8');
  assert.match(migration, /corporation_technology_modifier_cache/);
  assert.match(migration, /m\.game_day = p_game_day/);
  assert.match(migration, /m\.research_capacity_bps/);
  assert.doesNotMatch(migration, /JOIN technology_effects e/);
  assert.match(migration, /completed on Day N/);
  assert.match(migration, /Day N \+ 1/);
  assert.match(fs.readFileSync(path.resolve('db/migrations/257_technology_modifier_rules.sql'), 'utf8'), /'RESEARCH_CAPACITY'.*0, 2500/);
});

test('patentability is explicit and enforced for licensing', () => {
  const migration = fs.readFileSync(path.resolve('db/migrations/270_selective_technology_patents.sql'), 'utf8');
  const source = fs.readFileSync(path.resolve('cloudflare/src/technology-postgres.ts'), 'utf8');
  assert.match(migration, /patentable = CASE/);
  assert.match(migration, /technology_catalog_patent_terms_ck/);
  assert.match(migration, /earth_technology_is_patentable/);
  assert.match(migration, /p_access_source = 'LICENSED'/);
  assert.match(migration, /not patentable and cannot be licensed/);
  assert.doesNotMatch(source, /grantPatent|FROM research_projects|INSERT INTO patents/);
});

test('patents are automatically granted to the discovering corporation', () => {
  const migration = fs.readFileSync(path.resolve('db/migrations/271_automatic_technology_patents.sql'), 'utf8');
  const schedulerMigration = fs.readFileSync(path.resolve('db/migrations/289_research_scheduler_v2.sql'), 'utf8');
  const manifest = JSON.parse(fs.readFileSync(path.resolve('db/schema-manifest.json'), 'utf8'));
  assert.match(migration, /CREATE TABLE IF NOT EXISTS technology_patents/);
  assert.match(migration, /owner_economic_id BIGINT/);
  assert.match(migration, /technology_patents_one_active_idx/);
  assert.match(migration, /ON CONFLICT DO NOTHING/);
  assert.match(migration, /AND t\.patentable/);
  assert.match(migration, /earth_grant_completed_technology_patents/);
  assert.match(schedulerMigration, /earth_grant_completed_technology_patents/);
  assert.ok(manifest.requiredTables.technology_patents);
});

test('legacy research and IP paths are removed after V2 cutover', () => {
  const migration = fs.readFileSync(path.resolve('db/migrations/290_remove_legacy_research_paths.sql'), 'utf8');
  const manifest = JSON.parse(fs.readFileSync(path.resolve('db/schema-manifest.json'), 'utf8'));
  for (const table of ['research_projects', 'technologies', 'corporation_technology_projects', 'corporation_building_research_projects', 'human_technology_adoptions', 'human_technology_subscriptions', 'corporation_technology_shares', 'technology_licenses', 'building_patent_licenses']) {
    assert.match(migration, new RegExp(`DROP TABLE IF EXISTS ${table}`));
    assert.equal(manifest.requiredTables[table], undefined);
  }
  assert.ok(manifest.requiredTables.corporation_research_projects);
  assert.ok(manifest.requiredTables.corporation_building_unlocks);
});

test('IP and research integrity checks cover V2 authorization and accounting', () => {
  const migration = fs.readFileSync(path.resolve('db/migrations/291_ip_rd_integrity_report.sql'), 'utf8');
  for (const check of [
    'completed_research_missing_effect', 'active_license_without_valid_patent',
    'paid_through_license_without_payment', 'licensed_access_after_contract_expiry',
    'multiple_exclusive_active_patents', 'patent_for_non_patentable_technology',
    'patent_owner_not_corporation', 'technology_modifier_cache_source_mismatch',
    'building_modifier_without_corporation_access',
  ]) assert.match(migration, new RegExp(check));
  assert.match(migration, /earth_ip_rd_integrity/);
  assert.match(migration, /earth_integrity_report/);
  assert.match(migration, /technology_license_payments/);
  assert.match(migration, /effective_from_game_day = p\.completed_game_day \+ 1/);
});

test('patent exclusivity grandfathers active research and blocks new starts', () => {
  const migration = fs.readFileSync(path.resolve('db/migrations/272_patent_research_race_rules.sql'), 'utf8');
  const source = fs.readFileSync(path.resolve('cloudflare/src/technology-postgres.ts'), 'utf8');
  assert.match(migration, /earth_assert_technology_research_allowed/);
  assert.match(migration, /FOR UPDATE/);
  assert.match(migration, /status = 'ACTIVE'/);
  assert.match(migration, /exclusive_through_game_day >= p_effective_game_day/);
  assert.match(migration, /already-started projects to finish/);
  assert.match(source, /earth_assert_technology_research_allowed\(\$1, \$2\)/);
  assert.match(source, /catalogEntry\.id, day \+ 1/);
});

test('patent expiry creates permanent next-day public-domain access', () => {
  const migration = fs.readFileSync(path.resolve('db/migrations/273_technology_public_domain.sql'), 'utf8');
  const scheduler = fs.readFileSync(path.resolve('cloudflare/src/scheduler-postgres.ts'), 'utf8');
  const manifest = JSON.parse(fs.readFileSync(path.resolve('db/schema-manifest.json'), 'utf8'));
  assert.match(migration, /CREATE TABLE IF NOT EXISTS technology_public_domain/);
  assert.match(migration, /exclusive_through_game_day \+ 1/);
  assert.match(migration, /technology_public_domain/);
  assert.match(migration, /d\.effective_from_game_day <= p_game_day/);
  assert.match(migration, /ON CONFLICT \(technology_id\) DO NOTHING/);
  assert.match(scheduler, /earth_finalize_technology_public_domain/);
  assert.ok(manifest.requiredTables.technology_public_domain);
});

test('IP licenses are corporation-to-corporation contracts', () => {
  const migration = fs.readFileSync(path.resolve('db/migrations/274_corporation_ip_license_contracts.sql'), 'utf8');
  const manifest = JSON.parse(fs.readFileSync(path.resolve('db/schema-manifest.json'), 'utf8'));
  assert.match(migration, /CREATE TABLE IF NOT EXISTS technology_license_contracts/);
  assert.match(migration, /licensor_economic_id BIGINT/);
  assert.match(migration, /licensee_economic_id BIGINT/);
  assert.match(migration, /Only corporations may be IP licensees/);
  assert.match(migration, /earth_post_transaction/);
  assert.match(migration, /earth_grant_corporation_technology_access/);
  assert.match(migration, /correlation_id TEXT NOT NULL UNIQUE/);
  assert.ok(manifest.requiredTables.technology_license_contracts);
});

test('subscriptions are represented by recurring license contract fees', () => {
  const migration = fs.readFileSync(path.resolve('db/migrations/275_remove_technology_subscriptions.sql'), 'utf8');
  const schema = fs.readFileSync(path.resolve('db/schema.sql'), 'utf8');
  assert.match(migration, /DROP TABLE IF EXISTS business_technology_subscriptions/);
  assert.match(migration, /DROP COLUMN IF EXISTS subscription_cost_credits/);
  assert.match(schema, /daily_fee_units BIGINT/);
  assert.doesNotMatch(schema, /subscription_cost_credits/);
});

test('initial IP V2 contracts do not support percentage royalties', () => {
  const migration = fs.readFileSync(path.resolve('db/migrations/276_remove_ip_percentage_royalties.sql'), 'utf8');
  const schema = fs.readFileSync(path.resolve('db/schema.sql'), 'utf8');
  const technologyPostgres = fs.readFileSync(path.resolve('cloudflare/src/technology-postgres.ts'), 'utf8');
  const scheduler = fs.readFileSync(path.resolve('cloudflare/src/scheduler-postgres.ts'), 'utf8');
  const server = fs.readFileSync(path.resolve('server.js'), 'utf8');
  assert.match(migration, /DROP COLUMN IF EXISTS royalty_rate/);
  assert.match(schema, /upfront_fee_units BIGINT/);
  assert.match(schema, /daily_fee_units BIGINT/);
  assert.doesNotMatch(technologyPostgres, /royaltyRate|royalty_rate/);
  assert.doesNotMatch(scheduler, /settleTechnologyRoyalties|technology_royalty|royalty_rate/);
  assert.doesNotMatch(server, /royalty_rate:\s*royaltyRate/);
  assert.match(server, /Percentage royalties are not supported/);
});

test('IP license fees are recorded and settled through Economy V2', () => {
  const migration = fs.readFileSync(path.resolve('db/migrations/277_economy_v2_ip_license_payments.sql'), 'utf8');
  const schema = fs.readFileSync(path.resolve('db/schema.sql'), 'utf8');
  const scheduler = fs.readFileSync(path.resolve('cloudflare/src/scheduler-postgres.ts'), 'utf8');
  assert.match(migration, /CREATE TABLE IF NOT EXISTS technology_license_payments/);
  assert.match(migration, /earth_post_transaction/);
  assert.match(migration, /IP_LICENSE_DAILY/);
  assert.match(migration, /ON CONFLICT \(contract_id, game_day\) DO NOTHING/);
  assert.match(migration, /upfront_transaction_id/);
  assert.match(schema, /upfront_transaction_id BIGINT/);
  assert.match(schema, /last_daily_transaction_id BIGINT/);
  assert.match(scheduler, /earth_settle_technology_license_fees/);
  assert.doesNotMatch(migration, /account_balances|ledger_entries/);
});

test('IP license access is prepaid before building settlement', () => {
  const migration = fs.readFileSync(path.resolve('db/migrations/278_prepay_ip_license_access.sql'), 'utf8');
  const scheduler = fs.readFileSync(path.resolve('cloudflare/src/scheduler-postgres.ts'), 'utf8');
  assert.match(migration, /status = 'SUSPENDED'/);
  assert.match(migration, /paid_through_game_day >= p_game_day/);
  assert.match(migration, /earth_settle_technology_license_fees_worker/);
  assert.match(scheduler, /ipLicenseBilling: \(\{ tx \}\) => tx\.query\('SELECT earth_settle_technology_license_fees\(\$1\)'/);
  assert.match(scheduler, /buildingSettlement: async/);
  assert.doesNotMatch(scheduler, /buildingSettlement: async[\s\S]*earth_settle_technology_license_fees/);
});

test('IP license billing resolves affordability and posts one daily batch', () => {
  const migration = fs.readFileSync(path.resolve('db/migrations/279_set_based_ip_license_billing.sql'), 'utf8');
  assert.match(migration, /CREATE TEMP TABLE ip_license_due/);
  assert.match(migration, /SUM\(daily_fee_units\)/);
  assert.match(migration, /earth_post_settlement_batch/);
  assert.match(migration, /'ip-license-daily:' \|\| p_game_day/);
  assert.doesNotMatch(migration, /FOR v_contract IN/);
  assert.doesNotMatch(migration, /earth_post_transaction/);
});

test('IP license payment failure suspends access without arrears', () => {
  const migration = fs.readFileSync(path.resolve('db/migrations/280_license_failure_policy.sql'), 'utf8');
  const billing = fs.readFileSync(path.resolve('db/migrations/279_set_based_ip_license_billing.sql'), 'utf8');
  assert.match(migration, /suspension_reason/);
  assert.match(migration, /IP_LICENSE_DAILY_PAYMENT_UNAVAILABLE/);
  assert.match(migration, /no automatic refund/);
  assert.match(billing, /status = 'SUSPENDED'/);
  assert.doesNotMatch(billing, /tax_obligations|ARREARS/);
});

test('patent expiry terminates V2 licenses before fee billing', () => {
  const migration = fs.readFileSync(path.resolve('db/migrations/281_patent_expiry_contract_termination.sql'), 'utf8');
  const phases = fs.readFileSync(path.resolve('cloudflare/src/daily-settlement-phases.ts'), 'utf8');
  const scheduler = fs.readFileSync(path.resolve('cloudflare/src/scheduler-postgres.ts'), 'utf8');
  assert.match(migration, /status = 'EXPIRED'/);
  assert.match(migration, /technology_license_contracts/);
  assert.match(phases, /patent_expirations', order: 45/);
  assert.match(phases, /ip_license_billing', order: 65/);
  assert.match(scheduler, /patentExpirations: \(\{ tx \}\) => tx\.query\('SELECT earth_finalize_technology_public_domain/);
  assert.match(scheduler, /buildingSettlement: async \(\{ tx \}\) => \{\s+await tx\.query\('SELECT earth_rebuild_corporation_technology_modifier_cache/);
});

test('dissolved corporate patents transfer to the OUC IP registry', () => {
  const migration = fs.readFileSync(path.resolve('db/migrations/282_transfer_dissolved_corporate_patents.sql'), 'utf8');
  const scheduler = fs.readFileSync(path.resolve('cloudflare/src/scheduler-postgres.ts'), 'utf8');
  assert.match(migration, /technology_patent_ownership_transfers/);
  assert.match(migration, /owner_registry WHERE id = 'OUC'/);
  assert.match(migration, /UPDATE technology_patents SET owner_economic_id/);
  assert.match(migration, /UPDATE technology_license_contracts/);
  assert.match(migration, /ON CONFLICT DO NOTHING/);
  assert.match(scheduler, /earth_transfer_dissolved_corporation_ip/);
});

test('all technology consumers use one access resolver with explicit reasons', () => {
  const migration = fs.readFileSync(path.resolve('db/migrations/283_canonical_technology_access_resolver.sql'), 'utf8');
  const source = fs.readFileSync(path.resolve('cloudflare/src/technology-postgres.ts'), 'utf8');
  assert.match(migration, /earth_resolve_corporation_technology_access/);
  for (const reason of ['RESEARCHED', 'LICENSED', 'PUBLIC_DOMAIN', 'GRANTED']) assert.match(migration, new RegExp(reason));
  assert.match(migration, /paid_through_game_day >= p_game_day/);
  assert.match(source, /resolveCorporationTechnologyAccess/);
  assert.match(source, /earth_resolve_corporation_technology_access/);
});

test('technology modifiers use a dirty-aware compact cache', () => {
  const migration = fs.readFileSync(path.resolve('db/migrations/284_dirty_technology_modifier_cache.sql'), 'utf8');
  const manifest = JSON.parse(fs.readFileSync(path.resolve('db/schema-manifest.json'), 'utf8'));
  assert.match(migration, /corporation_technology_modifier_invalidations/);
  assert.match(migration, /TECHNOLOGY_ACCESS_CHANGED/);
  assert.match(migration, /earth_rebuild_corporation_technology_modifier_cache_bulk/);
  assert.match(migration, /No economic state changed/);
  assert.ok(manifest.requiredTables.corporation_technology_modifier_invalidations);
});

test('technology effects are observable in cache and building journals', () => {
  const migration = fs.readFileSync(path.resolve('db/migrations/285_technology_effect_observability.sql'), 'utf8');
  const building = fs.readFileSync(path.resolve('cloudflare/src/building-settlement-v2.ts'), 'utf8');
  assert.match(migration, /technology_source_breakdown JSONB/);
  assert.match(migration, /technology_effects JSONB/);
  assert.match(migration, /technologyName/);
  assert.match(migration, /modifierBps/);
  assert.match(building, /technology_source_breakdown/);
  assert.match(building, /technology_effects/);
});

test('research and licensing freeze technology definitions at creation', () => {
  const migration = fs.readFileSync(path.resolve('db/migrations/286_technology_definition_snapshots.sql'), 'utf8');
  const schema = fs.readFileSync(path.resolve('db/schema.sql'), 'utf8');
  const source = fs.readFileSync(path.resolve('cloudflare/src/technology-postgres.ts'), 'utf8');
  assert.match(migration, /definition_snapshot JSONB/);
  assert.match(migration, /patent_terms_snapshot JSONB/);
  assert.match(migration, /researchPointsRequired/);
  assert.match(migration, /exclusiveThroughGameDay/);
  assert.match(schema, /definition_snapshot JSONB/);
  assert.match(source, /definition_snapshot/);
});

test('technology prerequisites are normalized and enforced as a shallow graph', () => {
  const migration = fs.readFileSync(path.resolve('db/migrations/287_technology_prerequisites.sql'), 'utf8');
  const source = fs.readFileSync(path.resolve('cloudflare/src/technology-postgres.ts'), 'utf8');
  assert.match(migration, /CREATE TABLE IF NOT EXISTS technology_prerequisites/);
  assert.match(migration, /Technology prerequisite cycle is not allowed/);
  assert.match(migration, /may not exceed three levels/);
  assert.match(migration, /earth_assert_technology_prerequisites_met/);
  assert.match(source, /earth_assert_technology_prerequisites_met/);
});

test('technology specialization is optional, bounded, and category-specific', () => {
  const migration = fs.readFileSync(path.resolve('db/migrations/288_technology_specialization.sql'), 'utf8');
  const schema = fs.readFileSync(path.resolve('db/schema.sql'), 'utf8');
  const manifest = JSON.parse(fs.readFileSync(path.resolve('db/schema-manifest.json'), 'utf8'));
  assert.match(migration, /corporation_technology_specializations/);
  assert.match(migration, /efficiency_bonus_bps INTEGER.*BETWEEN 0 AND 1500/);
  assert.match(migration, /earth_corporation_research_specialization_bonus/);
  assert.match(migration, /never grants access/);
  assert.match(schema, /specialization_bonus_bps INTEGER/);
  assert.ok(manifest.requiredTables.corporation_technology_specializations);
});
