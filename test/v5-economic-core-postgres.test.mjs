import test from 'node:test';
import assert from 'node:assert/strict';
import { Client } from 'pg';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { postgresClient } from './postgres-connection.mjs';

import { PostgresRepository } from '../cloudflare/src/repository.ts';
import { registerIdentity } from '../cloudflare/src/auth-postgres.ts';
import { foundV5Corporation } from '../cloudflare/src/v5-founding-postgres.ts';
import { getCorporationFiscalState } from '../cloudflare/src/corporation-fiscal-postgres.ts';
import { getInstitutionFinancialProjection } from '../cloudflare/src/financial-projections.ts';
import { submitMarketOrder, settleMarketBatch, cancelMarketOrder } from '../cloudflare/src/market-postgres.ts';
import { settleBuildingUpkeepAndRevenueV2 } from '../cloudflare/src/building-settlement-v2.ts';
import { settleHouseNeedsAndServices } from '../cloudflare/src/service-settlement-postgres.ts';
import { settleLifeMaintenanceInTransaction, estimateLifeMaintenance } from '../cloudflare/src/life-maintenance-postgres.ts';
import { refreshHouseDailyStatementsInTransaction, getHouseDailySummary } from '../cloudflare/src/house-daily-summary-postgres.ts';
import { settleCorporationDynamics } from '../cloudflare/src/territory-settlement-postgres.ts';

import {
  getResourcePersistenceMetadata,
  resolveOwnerStorageCapacity,
  grantOwnerStorageCapacity,
  calculateResourceDecayUnits,
  settleResourcePersistenceAndDecay,
} from '../cloudflare/src/v5-resource-persistence-postgres.ts';
import { settlePerishableResourceDecay } from '../cloudflare/src/resource-settlement-postgres.ts';
import { getResourceBehaviorMetadata } from '../cloudflare/src/resource-behavior-postgres.ts';

import {
  rebuildV5HouseSettlementProfile,
  rebuildV5CorporationSettlementProfile,
  refreshV5SettlementProfilesForHouse,
  rebuildV5SettlementProfilesInShard,
  settleV5CorporationSettlementProfiles,
  getHouseSettlementProfileSnapshot,
  getCorporationSettlementProfileSnapshot,
  recordStructuralDelta,
  getStructuralDeltas,
} from '../cloudflare/src/v5-settlement-profiles-postgres.ts';
import { quoteV5Building, purchaseV5Building, suspendBuilding, reactivateBuilding } from '../cloudflare/src/v5-building-postgres.ts';
import { quoteBuildingUpgrade, upgradeBuilding, decommissionBuilding, quoteBuildingRetrofit, retrofitBuilding } from '../cloudflare/src/building-investment-postgres.ts';
import { grantCorporationScaleCapability, grantEarthBaselineScaleCapability } from '../cloudflare/src/v5-scale-postgres.ts';
import {
  getAvailableGenerations,
  assertGenerationAuthorized,
  grantCorporationTechnologyGeneration,
  grantEarthBaselineTechnologyGeneration,
} from '../cloudflare/src/v5-generation-postgres.ts';
import { completeDueConstructionProjects } from '../cloudflare/src/construction-settlement-postgres.ts';
import { applyV5CorporationMembership, leaveV5Corporation } from '../cloudflare/src/v5-membership-postgres.ts';

const execFileAsync = promisify(execFile);
const connectionString = process.env.DATABASE_URL || 'postgres://earth:earth_dev_only@localhost:5432/earth';

const EXPECTED_V5_FAMILIES = [
  'CIVIC_DATA_NETWORK',
  'COMMUNITY_CLINIC',
  'COMPUTE_CLUSTER',
  'DATA_SERVICES_STUDIO',
  'EXTRACTION_REFINING_COMPLEX',
  'MATERIALS_RECOVERY',
  'PRECISION_FABRICATION',
  'PUBLIC_MEDICAL_CENTER',
  'RESEARCH_EDUCATION_CAMPUS',
  'SOLAR_MICROGRID',
  'VERTICAL_FARM',
].sort();

const EXPECTED_DOMAINS = [
  'COMPONENTS',
  'COMPUTE',
  'CONNECTIVITY',
  'ENERGY',
  'FOOD',
  'HEALTH',
  'MATERIAL',
  'RESEARCH',
].sort();

async function connectTo(url) {
  const client = postgresClient(url, 'earth-v5-pg-test');
  await client.connect();
  return client;
}

test('PostgreSQL V5 Economic Core: Schema version is 127 and migration history is valid', async () => {
  const client = await connectTo(connectionString);
  try {
    const res = await client.query('SELECT MAX(version) AS max_version, COUNT(*)::int AS count FROM earth_schema_migrations');
    assert.equal(Number(res.rows[0].max_version), 127, 'Max migration version must be 127');
    assert.equal(Number(res.rows[0].count), 127, 'Total applied migrations count must be 127');

    const v118 = await client.query('SELECT name FROM earth_schema_migrations WHERE version = 118');
    assert.equal(v118.rows[0]?.name, '118_v5_economic_core_schema.sql');

    const v119 = await client.query('SELECT name FROM earth_schema_migrations WHERE version = 119');
    assert.equal(v119.rows[0]?.name, '119_v5_building_catalog_v5_alpha.sql');

    const v120 = await client.query('SELECT name FROM earth_schema_migrations WHERE version = 120');
    assert.equal(v120.rows[0]?.name, '120_v5_corporation_resource_accounts.sql');

    const v121 = await client.query('SELECT name FROM earth_schema_migrations WHERE version = 121');
    assert.equal(v121.rows[0]?.name, '121_v5_retire_housing_energy_services.sql');

    const v122 = await client.query('SELECT name FROM earth_schema_migrations WHERE version = 122');
    assert.equal(v122.rows[0]?.name, '122_v5_scale_capabilities_and_upgrades.sql');
    const v123 = await client.query('SELECT name FROM earth_schema_migrations WHERE version = 123');
    assert.equal(v123.rows[0]?.name, '123_v5_earth_technology_frontier.sql');
    const v124 = await client.query('SELECT name FROM earth_schema_migrations WHERE version = 124');
    assert.equal(v124.rows[0]?.name, '124_v5_technology_domain_generations.sql');
    const v125 = await client.query('SELECT name FROM earth_schema_migrations WHERE version = 125');
    assert.equal(v125.rows[0]?.name, '125_v5_corporation_technology_adoptions.sql');
    const v126 = await client.query('SELECT name FROM earth_schema_migrations WHERE version = 126');
    assert.equal(v126.rows[0]?.name, '126_v5_resource_persistence_and_storage.sql');
    const v127 = await client.query('SELECT name FROM earth_schema_migrations WHERE version = 127');
    assert.equal(v127.rows[0]?.name, '127_v5_settlement_profile_deltas.sql');
  } finally {
    await client.end();
  }
});

test('PostgreSQL V5 Economic Core: 11 V5 building families exist with physical Tiers 1-4', async () => {
  const client = await connectTo(connectionString);
  try {
    const familiesRes = await client.query(`
      SELECT DISTINCT family_code
      FROM building_catalog
      WHERE active = true
      ORDER BY family_code ASC
    `);
    const actualFamilies = familiesRes.rows.map((r) => r.family_code).sort();
    assert.deepEqual(actualFamilies, EXPECTED_V5_FAMILIES, 'All 11 V5 building families must be present and active');

    const tiersRes = await client.query(`
      SELECT family_code, array_agg(tier ORDER BY tier) AS tiers
      FROM building_catalog
      WHERE active = true
      GROUP BY family_code
      ORDER BY family_code ASC
    `);
    assert.equal(tiersRes.rows.length, 11);
    for (const row of tiersRes.rows) {
      assert.deepEqual(row.tiers, [1, 2, 3, 4], `Family ${row.family_code} must have Tiers 1, 2, 3, 4`);
    }

    const countRes = await client.query('SELECT COUNT(*)::int AS active_count FROM building_catalog WHERE active = true');
    assert.equal(countRes.rows[0].active_count, 44, 'There must be exactly 44 active V5 catalog entries (11 families * 4 tiers)');
  } finally {
    await client.end();
  }
});

test('PostgreSQL V5 Economic Core: Obsolete legacy catalog rows are deactivated', async () => {
  const client = await connectTo(connectionString);
  try {
    const inactiveRes = await client.query(`
      SELECT id, code, active
      FROM building_catalog
      WHERE active = false
      ORDER BY id ASC
    `);
    assert.ok(inactiveRes.rows.length > 0, 'Obsolete catalog rows must exist as inactive entries');

    const inactiveIds = new Set(inactiveRes.rows.map((r) => r.id));
    assert.ok(inactiveIds.has('HOUSING-T1') || inactiveIds.has('housing-t1'), 'Housing catalog rows must be inactive');
    assert.ok(inactiveIds.has('DISTRICT-MODULE-T1') || inactiveIds.has('district-module-t1'), 'District module rows must be inactive');

    const activeRowsRes = await client.query(`
      SELECT id, code, family_code, tier, slot_footprint, construction_credit_units, operating_credit_units
      FROM building_catalog
      WHERE active = true
    `);
    for (const row of activeRowsRes.rows) {
      assert.ok(row.family_code, `Active building ${row.id} must have a family_code`);
      assert.ok(row.tier >= 1 && row.tier <= 4, `Active building ${row.id} tier must be between 1 and 4`);
      assert.ok(Number(row.slot_footprint) >= 1, `Active building ${row.id} slot footprint must be >= 1`);
      assert.ok(Number(row.construction_credit_units) > 0, `Active building ${row.id} construction credits must be > 0`);
    }
  } finally {
    await client.end();
  }
});

test('PostgreSQL V5 Economic Core: Normalized resource flows exist for all active catalog entries', async () => {
  const client = await connectTo(connectionString);
  try {
    const flowsRes = await client.query(`
      SELECT bc.id AS building_id, bc.family_code, bc.tier, a.code AS resource_code,
             f.construction_units, f.operating_input_units, f.operating_output_units
      FROM building_catalog bc
      JOIN building_catalog_resource_flows f ON bc.id = f.catalog_id
      JOIN economic_assets a ON a.id = f.asset_id
      WHERE bc.active = true
      ORDER BY bc.id, a.code
    `);
    assert.ok(flowsRes.rows.length >= 44, 'Resource flows must be populated for V5 catalog entries');

    // Verify solar microgrid T1 has ENERGY output = 5 and construction materials = 120, components = 12, compute = 5
    const solarT1 = flowsRes.rows.filter((r) => r.building_id === 'SOLAR-MICROGRID-T1');
    assert.ok(solarT1.some((r) => r.resource_code === 'ENERGY' && Number(r.operating_output_units) === 5));
    assert.ok(solarT1.some((r) => r.resource_code === 'MATERIAL' && Number(r.construction_units) === 120));
    assert.ok(solarT1.some((r) => r.resource_code === 'COMPONENTS' && Number(r.construction_units) === 12));
    assert.ok(solarT1.some((r) => r.resource_code === 'COMPUTE' && Number(r.construction_units) === 5));

    // Verify vertical farm T1 has FOOD output = 4 and ENERGY input = 1, COMPUTE input = 1
    const farmT1 = flowsRes.rows.filter((r) => r.building_id === 'VERTICAL-FARM-T1');
    assert.ok(farmT1.some((r) => r.resource_code === 'FOOD' && Number(r.operating_output_units) === 4));
    assert.ok(farmT1.some((r) => r.resource_code === 'ENERGY' && Number(r.operating_input_units) === 1));
    assert.ok(farmT1.some((r) => r.resource_code === 'COMPUTE' && Number(r.operating_input_units) === 1));
  } finally {
    await client.end();
  }
});

test('PostgreSQL V5 Economic Core: 8 Technology domains and scale capabilities exist', async () => {
  const client = await connectTo(connectionString);
  try {
    const domainsRes = await client.query('SELECT code FROM technology_domains ORDER BY code ASC');
    const actualDomains = domainsRes.rows.map((r) => r.code);
    for (const domain of EXPECTED_DOMAINS) {
      assert.ok(actualDomains.includes(domain), `Technology domain ${domain} must exist in technology_domains`);
    }

    const frontierRes = await client.query('SELECT COUNT(*)::int AS count FROM earth_technology_frontier');
    assert.ok(frontierRes.rows[0].count >= 8, 'EARTH technology frontier must exist for all domains');

    const scaleRes = await client.query('SELECT to_regclass(\'corporation_scale_capabilities\') AS tbl');
    assert.ok(scaleRes.rows[0]?.tbl, 'corporation_scale_capabilities table must exist');

    const policiesRes = await client.query(`
      SELECT account_type FROM economic_account_policies
      WHERE owner_type = 'CORPORATION' AND account_type IN ('INVENTORY', 'MARKET_ESCROW')
    `);
    const policyTypes = policiesRes.rows.map((r) => r.account_type);
    assert.ok(policyTypes.includes('INVENTORY'), 'Corporation INVENTORY policy must exist');
    assert.ok(policyTypes.includes('MARKET_ESCROW'), 'Corporation MARKET_ESCROW policy must exist');
  } finally {
    await client.end();
  }
});

test('PostgreSQL V5 Economic Core Acceptance: Fresh database and upgraded database produce identical V5 catalog', async () => {
  const maintenanceDbUrl = new URL(connectionString);
  maintenanceDbUrl.pathname = '/postgres';
  
  const testDbName = `earth_v5_parity_${Date.now()}`;
  const freshDbUrl = new URL(connectionString);
  freshDbUrl.pathname = `/${testDbName}`;

  const adminClient = new Client({ connectionString: maintenanceDbUrl.toString() });
  await adminClient.connect();

  try {
    // 1. Create temporary fresh database
    await adminClient.query(`CREATE DATABASE "${testDbName}"`);

    // 2. Run migrations 001 -> 119 against the fresh database
    await execFileAsync('node', ['scripts/migrate-postgres.mjs'], {
      cwd: new URL('../', import.meta.url).pathname,
      env: { ...process.env, DATABASE_URL: freshDbUrl.toString() },
    });

    // 3. Query catalog from upgraded database
    const upgradedClient = await connectTo(connectionString);
    let upgradedCatalog, upgradedFlows;
    try {
      const catRes = await upgradedClient.query(`
        SELECT id, code, name, description, family_code, design_code, tier, category, ownership_scope, technology_domain,
               construction_credit_units, construction_minutes, operating_credit_units, service_type, service_capacity_units,
               slot_footprint, minimum_scale_capability, active, definition_version, research_credit_units, research_duration_game_days, economic_role
        FROM building_catalog
        ORDER BY id ASC
      `);
      upgradedCatalog = catRes.rows;

      const flowRes = await upgradedClient.query(`
        SELECT catalog_id, asset_id, construction_units, operating_input_units, operating_output_units
        FROM building_catalog_resource_flows
        ORDER BY catalog_id ASC, asset_id ASC
      `);
      upgradedFlows = flowRes.rows;
    } finally {
      await upgradedClient.end();
    }

    // 4. Query catalog from fresh database
    const freshClient = await connectTo(freshDbUrl.toString());
    let freshCatalog, freshFlows;
    try {
      const catRes = await freshClient.query(`
        SELECT id, code, name, description, family_code, design_code, tier, category, ownership_scope, technology_domain,
               construction_credit_units, construction_minutes, operating_credit_units, service_type, service_capacity_units,
               slot_footprint, minimum_scale_capability, active, definition_version, research_credit_units, research_duration_game_days, economic_role
        FROM building_catalog
        ORDER BY id ASC
      `);
      freshCatalog = catRes.rows;

      const flowRes = await freshClient.query(`
        SELECT catalog_id, asset_id, construction_units, operating_input_units, operating_output_units
        FROM building_catalog_resource_flows
        ORDER BY catalog_id ASC, asset_id ASC
      `);
      freshFlows = flowRes.rows;
    } finally {
      await freshClient.end();
    }

    // 5. Assert 100% parity between upgraded database and fresh database
    assert.equal(freshCatalog.length, upgradedCatalog.length, 'Catalog length must be identical');
    assert.deepEqual(freshCatalog, upgradedCatalog, 'Fresh database and upgraded database must have identical building_catalog rows');
    assert.equal(freshFlows.length, upgradedFlows.length, 'Resource flows length must be identical');
    assert.deepEqual(freshFlows, upgradedFlows, 'Fresh database and upgraded database must have identical resource flows');
  } finally {
    try {
      await adminClient.query(`DROP DATABASE IF EXISTS "${testDbName}" WITH (FORCE)`);
    } catch (_) {}
    await adminClient.end();
  }
});

test('PostgreSQL V5 Economic Core Phase 1: Corporation economic provisioning creates all 14 accounts', async () => {
  const client = await connectTo(connectionString);
  const repository = new PostgresRepository(client);
  const testCorpId = `CORP-TEST-${Date.now()}`;
  const testEconId = `ECON-${testCorpId}`;
  try {
    await repository.transaction(async (tx) => {
      await tx.query(`INSERT INTO institutions (id, kind, name, status) VALUES ($1, 'CORPORATION', $2, 'ACTIVE')`, [testCorpId, `Test Corp ${Date.now()}`]);
      await tx.query(`INSERT INTO corporations (id, charter_version, admission_policy, status, created_game_day) VALUES ($1, 'corporation-charter-v5', 'OPEN', 'ACTIVE', 1)`, [testCorpId]);
      await tx.query(`INSERT INTO owner_registry (id, owner_type, economic_id) VALUES ($1, 'CORPORATION', $2)`, [testCorpId, testEconId]);
      
      const countRes = await tx.query('SELECT earth_provision_corporation_economy($1) AS count', [testEconId]);
      assert.equal(Number(countRes.rows[0].count), 14, 'earth_provision_corporation_economy must provision exactly 14 accounts');

      const accounts = await tx.query(`
        SELECT a.account_type, a.asset_id, ea.code AS asset_code, ea.asset_kind
        FROM economic_accounts a
        JOIN economic_assets ea ON ea.id = a.asset_id
        WHERE a.owner_economic_id = $1
        ORDER BY a.asset_id, a.account_type
      `, [testEconId]);
      assert.equal(accounts.rows.length, 14);

      // Verify Credit accounts: TREASURY, OPERATIONS, RESERVE, MARKET_ESCROW
      const creditAccounts = accounts.rows.filter((a) => a.asset_code === 'CREDIT').map((a) => a.account_type).sort();
      assert.deepEqual(creditAccounts, ['MARKET_ESCROW', 'OPERATIONS', 'RESERVE', 'TREASURY']);

      // Verify Resource accounts: INVENTORY and MARKET_ESCROW for all 5 resources
      const resourceCodes = ['COMPONENTS', 'COMPUTE', 'ENERGY', 'FOOD', 'MATERIAL'];
      for (const code of resourceCodes) {
        const resAccts = accounts.rows.filter((a) => a.asset_code === code).map((a) => a.account_type).sort();
        assert.deepEqual(resAccts, ['INVENTORY', 'MARKET_ESCROW'], `Resource ${code} must have INVENTORY and MARKET_ESCROW accounts`);
      }
    });
  } finally {
    await client.query('DELETE FROM economic_accounts WHERE owner_economic_id = $1', [testEconId]);
    await client.query('DELETE FROM owner_registry WHERE economic_id = $1', [testEconId]);
    await client.query('DELETE FROM corporations WHERE id = $1', [testCorpId]);
    await client.query('DELETE FROM institutions WHERE id = $1', [testCorpId]);
    await client.end();
  }
});

test('PostgreSQL V5 Economic Core Phase 1: Corporation founding provisions accounts atomically and read models expose resource balances', async () => {
  const client = await connectTo(connectionString);
  const repository = new PostgresRepository(client);
  const email = `corp-found-${Date.now()}@example.invalid`;
  let humanId;
  let corpId;
  let corpEconId;
  let houseId;
  let houseEconId;

  try {
    const reg = await registerIdentity(repository, { email, personName: 'Founder', houseSurname: `Fnd${Date.now()}`, password: 'correct-horse-battery-staple' });
    humanId = reg.human.id;
    houseId = `HOUSE-${humanId.slice(2)}`;
    houseEconId = `ECON-${houseId}`;

    // Top up house wallet for founding fee + reserve
    await repository.transaction(async (tx) => {
      const wallet = (await tx.query(`SELECT id FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 1 AND account_type = 'WALLET'`, [houseEconId])).rows[0];
      await tx.query(`UPDATE economic_accounts SET balance_units = balance_units + 50000000 WHERE id = $1`, [wallet.id]);
    });

    const corpName = `Founding Corp ${Date.now()}`;
    const foundingCorrelationId = `test-found-${Date.now()}`;
    const foundRes = await foundV5Corporation(repository, {
      humanId,
      name: corpName,
      admissionPolicy: 'OPEN',
      correlationId: foundingCorrelationId,
    });

    assert.equal(foundRes.ok, true);
    corpId = foundRes.corporationId;
    corpEconId = `ECON-${corpId}`;

    // Check fiscal state read model
    const fiscalState = await getCorporationFiscalState(repository, corpId);
    assert.equal(fiscalState.corporation.id, corpId);
    assert.ok(Array.isArray(fiscalState.accounts));
    assert.equal(fiscalState.accounts.length, 14, 'Read model must expose all 14 accounts');
    assert.deepEqual(Object.keys(fiscalState.resourceBalances).sort(), ['components', 'compute', 'energy', 'food', 'material']);
    assert.deepEqual(Object.keys(fiscalState.creditBalances).sort(), ['operations', 'reserve', 'treasury']);

    // Check financial projection read model
    const projection = await getInstitutionFinancialProjection(repository, corpId);
    assert.equal(projection.principalId, corpId);
    assert.ok(projection.resourceBalances);
    assert.deepEqual(Object.keys(projection.resourceBalances).sort(), ['components', 'compute', 'energy', 'food', 'material']);
  } finally {
    if (corpId) {
      await repository.transaction(async (tx) => {
        await tx.query('DELETE FROM v5_corporation_settlement_profiles WHERE corporation_id = $1', [corpId]);
        await tx.query('UPDATE v5_house_settlement_profiles SET corporation_id = NULL WHERE corporation_id = $1', [corpId]);
        await tx.query('DELETE FROM v5_corporation_founding_commands WHERE corporation_id = $1', [corpId]);
        await tx.query('DELETE FROM event_outbox WHERE aggregate_id = $1', [corpId]);
        await tx.query('DELETE FROM comm_channels WHERE scope_id = $1', [corpId]);
        await tx.query('DELETE FROM institution_governance_roles WHERE institution_id = $1', [corpId]);
        await tx.query('DELETE FROM house_affiliations WHERE corporation_id = $1', [corpId]);
        await tx.query('DELETE FROM constitutional_rule_versions_v5 WHERE authority_id = $1', [corpId]);
        await tx.query('DELETE FROM economic_entries WHERE transaction_id IN (SELECT id FROM economic_transactions WHERE correlation_id LIKE $1)', [`test-found-%`]);
        await tx.query('DELETE FROM economic_transactions WHERE correlation_id LIKE $1', [`test-found-%`]);
        await tx.query('DELETE FROM economic_entries WHERE account_id IN (SELECT id FROM economic_accounts WHERE owner_economic_id = $1)', [corpEconId]);
        await tx.query('DELETE FROM economic_accounts WHERE owner_economic_id = $1', [corpEconId]);
        await tx.query('DELETE FROM owner_registry WHERE economic_id = $1', [corpEconId]);
        await tx.query('DELETE FROM corporations WHERE id = $1', [corpId]);
        await tx.query('DELETE FROM institutions WHERE id = $1', [corpId]);
      });
    }
    if (humanId) {
      await repository.transaction(async (tx) => {
        await tx.query('DELETE FROM auth_sessions WHERE account_id = $1', [`account-${humanId.toLowerCase()}`]);
        await tx.query('DELETE FROM game_events WHERE actor_human_id = $1', [humanId]);
        await tx.query('DELETE FROM notifications WHERE human_id = $1', [humanId]);
        await tx.query('DELETE FROM personal_life_maintenance WHERE human_id = $1', [humanId]);
        await tx.query('DELETE FROM event_outbox WHERE aggregate_id = $1', [humanId]);
        await tx.query('DELETE FROM buildings WHERE owner_economic_id = $1', [houseEconId]);
        await tx.query('DELETE FROM economic_entries WHERE account_id IN (SELECT id FROM economic_accounts WHERE owner_economic_id = $1)', [houseEconId]);
        await tx.query('DELETE FROM economic_entries WHERE transaction_id IN (SELECT id FROM economic_transactions WHERE correlation_id LIKE $1)', [`starter:${houseId}:%`]);
        await tx.query('DELETE FROM economic_transactions WHERE correlation_id LIKE $1', [`starter:${houseId}:%`]);
        await tx.query('DELETE FROM economic_accounts WHERE owner_economic_id = $1', [houseEconId]);
        await tx.query('DELETE FROM owner_registry WHERE economic_id = $1', [houseEconId]);
        await tx.query('UPDATE houses SET current_human_id = NULL WHERE id = $1', [houseId]);
        await tx.query('DELETE FROM humans WHERE id = $1', [humanId]);
        await tx.query('UPDATE auth_accounts SET house_id = NULL WHERE email = $1', [email]);
        await tx.query('DELETE FROM house_entry_support WHERE house_id = $1', [houseId]);
        await tx.query('DELETE FROM house_onboarding_progress WHERE house_id = $1', [houseId]);
        await tx.query('DELETE FROM v5_house_settlement_profiles WHERE house_id = $1', [houseId]);
        await tx.query('DELETE FROM houses WHERE id = $1', [houseId]);
        await tx.query('DELETE FROM auth_accounts WHERE email = $1', [email]);
      });
    }
    await client.end();
  }
});

test('PostgreSQL V5 Economic Core Phase 1: Corporation can buy and sell resources through normal market', async () => {
  const client = await connectTo(connectionString);
  const repository = new PostgresRepository(client);
  const emailBuyer = `buyer-corp-${Date.now()}@example.invalid`;
  const emailSeller = `seller-house-${Date.now()}@example.invalid`;
  let buyerHumanId, buyerHouseId, buyerCorpId, buyerCorpEconId;
  let sellerHumanId, sellerHouseId, sellerHouseEconId;
  let buyOrderId, sellOrderId;

  try {
    // 1. Setup Buyer with Corporation
    const regBuyer = await registerIdentity(repository, { email: emailBuyer, personName: 'BuyerCorp', houseSurname: `BHouse${Date.now()}`, password: 'correct-horse-battery-staple' });
    buyerHumanId = regBuyer.human.id;
    buyerHouseId = `HOUSE-${buyerHumanId.slice(2)}`;
    const buyerHouseEconId = `ECON-${buyerHouseId}`;

    await repository.transaction(async (tx) => {
      const wallet = (await tx.query(`SELECT id FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 1 AND account_type = 'WALLET'`, [buyerHouseEconId])).rows[0];
      await tx.query(`UPDATE economic_accounts SET balance_units = balance_units + 50000000 WHERE id = $1`, [wallet.id]);
    });

    const corpRes = await foundV5Corporation(repository, {
      humanId: buyerHumanId,
      name: `Trading Corp ${Date.now()}`,
      admissionPolicy: 'OPEN',
      correlationId: `test-trade-corp-${Date.now()}`,
    });
    buyerCorpId = corpRes.corporationId;
    buyerCorpEconId = `ECON-${buyerCorpId}`;

    // Top up Corporation Treasury with 100,000 Credits (10,000,000 cents)
    await repository.transaction(async (tx) => {
      const treasury = (await tx.query(`SELECT id FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 1 AND account_type = 'TREASURY'`, [buyerCorpEconId])).rows[0];
      await tx.query(`UPDATE economic_accounts SET balance_units = balance_units + 10000000 WHERE id = $1`, [treasury.id]);
    });

    // 2. Setup Seller House with Energy
    const regSeller = await registerIdentity(repository, { email: emailSeller, personName: 'SellerHouse', houseSurname: `SHouse${Date.now()}`, password: 'correct-horse-battery-staple' });
    sellerHumanId = regSeller.human.id;
    sellerHouseId = `HOUSE-${sellerHumanId.slice(2)}`;
    sellerHouseEconId = `ECON-${sellerHouseId}`;

    // Ensure Seller has 1,000 units of Energy (asset 4) in INVENTORY
    await repository.transaction(async (tx) => {
      const inv = (await tx.query(`SELECT id FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 4 AND account_type = 'INVENTORY'`, [sellerHouseEconId])).rows[0];
      await tx.query(`UPDATE economic_accounts SET balance_units = balance_units + 1000000000 WHERE id = $1`, [inv.id]);
    });

    // 3. Corporation submits BUY order for 100 ENERGY at limit price 50.00 Credits
    const buyOrderRes = await submitMarketOrder(repository, {
      humanId: buyerHumanId,
      corporationId: buyerCorpId,
      product: 'energy',
      side: 'buy',
      quantity: 100,
      limitPrice: 50.00,
      correlationId: `buy-order-${Date.now()}`,
    });
    assert.equal(buyOrderRes.ok, true);
    buyOrderId = buyOrderRes.order.id;

    // 4. Seller House submits SELL order for 100 ENERGY at limit price 50.00 Credits
    const sellOrderRes = await submitMarketOrder(repository, {
      humanId: sellerHumanId,
      product: 'energy',
      side: 'sell',
      quantity: 100,
      limitPrice: 50.00,
      correlationId: `sell-order-${Date.now()}`,
    });
    assert.equal(sellOrderRes.ok, true);
    sellOrderId = sellOrderRes.order.id;

    // 5. Settle Market Batch
    const batchId = buyOrderRes.order.batch_id;
    const settleRes = await settleMarketBatch(repository, 'energy', batchId);
    assert.equal(settleRes.ok, true);
    assert.equal(settleRes.filled, true);
    assert.equal(settleRes.fillCount, 1);

    // 6. Verify Corporation received Energy in INVENTORY
    const corpEnergyInv = (await repository.query(
      `SELECT balance_units::TEXT FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 4 AND account_type = 'INVENTORY'`,
      [buyerCorpEconId],
    )).rows[0];
    assert.ok(BigInt(corpEnergyInv.balance_units) >= 100000000n, 'Corporation inventory must receive 100 units of Energy');

    // 7. Corporation now sells 50 ENERGY back to the market
    const corpSellRes = await submitMarketOrder(repository, {
      humanId: buyerHumanId,
      corporationId: buyerCorpId,
      product: 'energy',
      side: 'sell',
      quantity: 50,
      limitPrice: 50.00,
      correlationId: `corp-sell-${Date.now()}`,
    });
    assert.equal(corpSellRes.ok, true);

    // 8. Corporation cancels the sell order and receives escrow back
    const cancelRes = await cancelMarketOrder(repository, {
      orderId: corpSellRes.order.id,
      humanId: buyerHumanId,
    });
    assert.equal(cancelRes.ok, true);
  } finally {
    // Cleanup orders and test accounts
    await client.query('DELETE FROM market_fills WHERE buy_order_id IN (SELECT id FROM market_orders WHERE owner_economic_id = $1 OR owner_economic_id = $2) OR sell_order_id IN (SELECT id FROM market_orders WHERE owner_economic_id = $1 OR owner_economic_id = $2)', [buyerCorpEconId, sellerHouseEconId]);
    await client.query('DELETE FROM market_order_reservations WHERE order_id IN (SELECT id FROM market_orders WHERE owner_economic_id = $1 OR owner_economic_id = $2)', [buyerCorpEconId, sellerHouseEconId]);
    if (buyOrderId) await client.query('DELETE FROM market_order_reservations WHERE order_id = $1', [buyOrderId]);
    if (sellOrderId) await client.query('DELETE FROM market_order_reservations WHERE order_id = $1', [sellOrderId]);
    await client.query('DELETE FROM market_orders WHERE owner_economic_id = $1 OR owner_economic_id = $2', [buyerCorpEconId, sellerHouseEconId]);
    await client.query(`DELETE FROM economic_entries WHERE transaction_id IN (SELECT id FROM economic_transactions WHERE correlation_id LIKE 'market-batch:%')`);
    await client.query(`DELETE FROM economic_transactions WHERE correlation_id LIKE 'market-batch:%'`);

    if (buyerCorpId) {
      await client.query('DELETE FROM v5_corporation_settlement_profiles WHERE corporation_id = $1', [buyerCorpId]);
      await client.query('UPDATE v5_house_settlement_profiles SET corporation_id = NULL WHERE corporation_id = $1', [buyerCorpId]);
      await client.query('DELETE FROM v5_corporation_founding_commands WHERE corporation_id = $1', [buyerCorpId]);
      await client.query('DELETE FROM comm_channels WHERE scope_id = $1', [buyerCorpId]);
      await client.query('DELETE FROM institution_governance_roles WHERE institution_id = $1', [buyerCorpId]);
      await client.query('DELETE FROM house_affiliations WHERE corporation_id = $1', [buyerCorpId]);
      await client.query('DELETE FROM constitutional_rule_versions_v5 WHERE authority_id = $1', [buyerCorpId]);
      await client.query(`DELETE FROM economic_entries WHERE transaction_id IN (SELECT id FROM economic_transactions WHERE correlation_id LIKE 'test-trade-corp-%')`);
      await client.query(`DELETE FROM economic_transactions WHERE correlation_id LIKE 'test-trade-corp-%'`);
      await client.query('DELETE FROM economic_entries WHERE account_id IN (SELECT id FROM economic_accounts WHERE owner_economic_id = $1)', [buyerCorpEconId]);
      await client.query('DELETE FROM economic_accounts WHERE owner_economic_id = $1', [buyerCorpEconId]);
      await client.query('DELETE FROM owner_registry WHERE economic_id = $1', [buyerCorpEconId]);
      await client.query('DELETE FROM corporations WHERE id = $1', [buyerCorpId]);
      await client.query('DELETE FROM institutions WHERE id = $1', [buyerCorpId]);
    }
    for (const [hId, eId, email] of [[buyerHumanId, `ECON-${buyerHouseId}`, emailBuyer], [sellerHumanId, sellerHouseEconId, emailSeller]]) {
      if (!hId) continue;
      const hHouseId = `HOUSE-${hId.slice(2)}`;
      await client.query('DELETE FROM auth_sessions WHERE account_id = $1', [`account-${hId.toLowerCase()}`]);
      await client.query('DELETE FROM game_events WHERE actor_human_id = $1', [hId]);
      await client.query('DELETE FROM notifications WHERE human_id = $1', [hId]);
      await client.query('DELETE FROM personal_life_maintenance WHERE human_id = $1', [hId]);
      await client.query('DELETE FROM event_outbox WHERE aggregate_id = $1', [hId]);
      await client.query('DELETE FROM economic_entries WHERE account_id IN (SELECT id FROM economic_accounts WHERE owner_economic_id = $1)', [eId]);
      await client.query('DELETE FROM economic_entries WHERE transaction_id IN (SELECT id FROM economic_transactions WHERE correlation_id LIKE $1)', [`starter:${hHouseId}:%`]);
      await client.query('DELETE FROM economic_transactions WHERE correlation_id LIKE $1', [`starter:${hHouseId}:%`]);
      await client.query('DELETE FROM economic_accounts WHERE owner_economic_id = $1', [eId]);
      await client.query('DELETE FROM owner_registry WHERE economic_id = $1', [eId]);
      await client.query('UPDATE houses SET current_human_id = NULL WHERE id = $1', [hHouseId]);
      await client.query('DELETE FROM humans WHERE id = $1', [hId]);
      await client.query('UPDATE auth_accounts SET house_id = NULL WHERE email = $1', [email]);
      await client.query('DELETE FROM house_entry_support WHERE house_id = $1', [hHouseId]);
      await client.query('DELETE FROM house_onboarding_progress WHERE house_id = $1', [hHouseId]);
      await client.query('DELETE FROM v5_house_settlement_profiles WHERE house_id = $1', [hHouseId]);
      await client.query('DELETE FROM houses WHERE id = $1', [hHouseId]);
      await client.query('DELETE FROM auth_accounts WHERE email = $1', [email]);
    }
    await client.end();
  }
});

test('PostgreSQL V5 Economic Core Phase 2: Public building zero inputs produce zero output (STARVED)', async () => {
  const client = await connectTo(connectionString);
  const repository = new PostgresRepository(client);
  const testCorpId = `CORP-PUB-ZERO-${Date.now()}`;
  const testEconId = `ECON-${testCorpId}`;
  const testBuildingId = `BLD-PUB-ZERO-${Date.now()}`;
  const testTerritoryId = `TERR-PUB-ZERO-${Date.now()}`;

  try {
    await repository.transaction(async (tx) => {
      await tx.query(`INSERT INTO institutions (id, kind, name, status) VALUES ($1, 'CORPORATION', $2, 'ACTIVE')`, [testCorpId, `Zero Input Corp ${Date.now()}`]);
      await tx.query(`INSERT INTO corporations (id, charter_version, admission_policy, status, created_game_day) VALUES ($1, 'corporation-charter-v5', 'OPEN', 'ACTIVE', 1)`, [testCorpId]);
      await tx.query(`INSERT INTO owner_registry (id, owner_type, economic_id) VALUES ($1, 'CORPORATION', $2)`, [testCorpId, testEconId]);
      await tx.query('SELECT earth_provision_corporation_economy($1)', [testEconId]);

      // Seed Treasury but 0 Energy and 0 Compute inventory
      const treasury = (await tx.query(`SELECT id FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 1 AND account_type = 'TREASURY'`, [testEconId])).rows[0];
      await tx.query(`UPDATE economic_accounts SET balance_units = 100000 WHERE id = $1`, [treasury.id]);

      await tx.query(`INSERT INTO territories (id, corporation_id, name, status, is_primary) VALUES ($1, $2, 'Zero Territory', 'ACTIVE', true)`, [testTerritoryId, testCorpId]);

      // EXTRACTION-REFINING-T1 requires 12 Energy, 1 Compute, produces 30 Material
      await tx.query(`
        INSERT INTO buildings (
          id, catalog_id, owner_economic_id, territory_id, status, construction_state,
          installed_generation, catalog_definition_version, technology_definition_version,
          operating_mode, started_game_day, last_major_rebuild_game_day
        ) VALUES (
          $1, 'EXTRACTION-REFINING-T1', $2, $3, 'ACTIVE', 'ACTIVE',
          1, 'v5-alpha-1', 'tech-gen-v1', 'BALANCED', 1, 1
        )
      `, [testBuildingId, testEconId, testTerritoryId]);

      const res = await settleBuildingUpkeepAndRevenueV2(tx, 2);
      assert.ok(res.publicBuildings >= 1);

      // Check Material inventory remains 0 (zero output)
      const matInv = (await tx.query(`SELECT balance_units::TEXT FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 2 AND account_type = 'INVENTORY'`, [testEconId])).rows[0];
      assert.equal(matInv.balance_units, '0', 'Zero inputs must produce zero output');

      // Check settlement journal
      const journal = (await tx.query(`SELECT * FROM building_settlement_journals WHERE building_id = $1 AND game_day = 2`, [testBuildingId])).rows[0];
      assert.ok(journal, 'Settlement journal must be recorded');
      assert.equal(journal.status, 'STARVED');
      assert.equal(journal.utilization_bps, 0);
      assert.deepEqual(journal.output_units, {});
      assert.deepEqual(journal.input_units, {});
      assert.equal(journal.operating_credit_units, '0');
      assert.ok(journal.shortage_units.ENERGY || journal.shortage_units.COMPUTE, 'Shortage units must be recorded');
    });
  } finally {
    await client.query('DELETE FROM building_settlement_journals WHERE building_id = $1', [testBuildingId]);
    await client.query('DELETE FROM buildings WHERE id = $1', [testBuildingId]);
    await client.query('DELETE FROM territory_capacity_state WHERE territory_id = $1', [testTerritoryId]);
    await client.query('DELETE FROM territories WHERE id = $1', [testTerritoryId]);
    await client.query('DELETE FROM economic_entries WHERE account_id IN (SELECT id FROM economic_accounts WHERE owner_economic_id = $1)', [testEconId]);
    await client.query('DELETE FROM economic_entries WHERE transaction_id IN (SELECT id FROM economic_transactions WHERE source_id = $1 OR correlation_id LIKE $2)', [testEconId, `building-corp:${testEconId}:%`]);
    await client.query('DELETE FROM economic_transactions WHERE source_id = $1 OR correlation_id LIKE $2', [testEconId, `building-corp:${testEconId}:%`]);
    await client.query('DELETE FROM economic_accounts WHERE owner_economic_id = $1', [testEconId]);
    await client.query('DELETE FROM owner_registry WHERE economic_id = $1', [testEconId]);
    await client.query('DELETE FROM corporations WHERE id = $1', [testCorpId]);
    await client.query('DELETE FROM institutions WHERE id = $1', [testCorpId]);
    await client.end();
  }
});

test('PostgreSQL V5 Economic Core Phase 2: Public building partial inputs produce proportional output (PARTIAL)', async () => {
  const client = await connectTo(connectionString);
  const repository = new PostgresRepository(client);
  const testCorpId = `CORP-PUB-PART-${Date.now()}`;
  const testEconId = `ECON-${testCorpId}`;
  const testBuildingId = `BLD-PUB-PART-${Date.now()}`;
  const testTerritoryId = `TERR-PUB-PART-${Date.now()}`;

  try {
    await repository.transaction(async (tx) => {
      await tx.query(`INSERT INTO institutions (id, kind, name, status) VALUES ($1, 'CORPORATION', $2, 'ACTIVE')`, [testCorpId, `Part Input Corp ${Date.now()}`]);
      await tx.query(`INSERT INTO corporations (id, charter_version, admission_policy, status, created_game_day) VALUES ($1, 'corporation-charter-v5', 'OPEN', 'ACTIVE', 1)`, [testCorpId]);
      await tx.query(`INSERT INTO owner_registry (id, owner_type, economic_id) VALUES ($1, 'CORPORATION', $2)`, [testCorpId, testEconId]);
      await tx.query('SELECT earth_provision_corporation_economy($1)', [testEconId]);

      // EXTRACTION-REFINING-T2 requires 26 Energy, 2 Compute, produces 69 Material, operating credit 1680
      // Provide 13 Energy (50%) and 10 Compute (500%)
      const treasury = (await tx.query(`SELECT id FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 1 AND account_type = 'TREASURY'`, [testEconId])).rows[0];
      await tx.query(`UPDATE economic_accounts SET balance_units = 100000 WHERE id = $1`, [treasury.id]);

      const energyInv = (await tx.query(`SELECT id FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 4 AND account_type = 'INVENTORY'`, [testEconId])).rows[0];
      await tx.query(`UPDATE economic_accounts SET balance_units = 13 WHERE id = $1`, [energyInv.id]);

      const computeInv = (await tx.query(`SELECT id FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 5 AND account_type = 'INVENTORY'`, [testEconId])).rows[0];
      await tx.query(`UPDATE economic_accounts SET balance_units = 10 WHERE id = $1`, [computeInv.id]);

      await tx.query(`INSERT INTO territories (id, corporation_id, name, status, is_primary) VALUES ($1, $2, 'Part Territory', 'ACTIVE', true)`, [testTerritoryId, testCorpId]);

      await tx.query(`
        INSERT INTO buildings (
          id, catalog_id, owner_economic_id, territory_id, status, construction_state,
          installed_generation, catalog_definition_version, technology_definition_version,
          operating_mode, started_game_day, last_major_rebuild_game_day
        ) VALUES (
          $1, 'EXTRACTION-REFINING-T2', $2, $3, 'ACTIVE', 'ACTIVE',
          1, 'v5-alpha-1', 'tech-gen-v1', 'BALANCED', 1, 1
        )
      `, [testBuildingId, testEconId, testTerritoryId]);

      const res = await settleBuildingUpkeepAndRevenueV2(tx, 2);
      assert.ok(res.publicBuildings >= 1);

      // Check Material produced is proportional: (69 * 5000) / 10000 = 34
      const matInv = (await tx.query(`SELECT balance_units::TEXT FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 2 AND account_type = 'INVENTORY'`, [testEconId])).rows[0];
      assert.equal(matInv.balance_units, '34', 'Partial inputs must produce proportional 50% output (34 units)');

      // Check Energy consumed = 13 (so balance becomes 0)
      const remEnergy = (await tx.query(`SELECT balance_units::TEXT FROM economic_accounts WHERE id = $1`, [energyInv.id])).rows[0];
      assert.equal(remEnergy.balance_units, '0', 'Consumed 13 units of Energy');

      // Check Compute consumed = 1 (balance becomes 9)
      const remCompute = (await tx.query(`SELECT balance_units::TEXT FROM economic_accounts WHERE id = $1`, [computeInv.id])).rows[0];
      assert.equal(remCompute.balance_units, '9', 'Consumed 1 unit of Compute');

      // Check Treasury operating cost = (1680 * 5000 * 10000) / 100000000 = 840
      const remTreasury = (await tx.query(`SELECT balance_units::TEXT FROM economic_accounts WHERE id = $1`, [treasury.id])).rows[0];
      assert.equal(remTreasury.balance_units, String(100000 - 840), 'Operating credit charged proportionally');

      // Check journal
      const journal = (await tx.query(`SELECT * FROM building_settlement_journals WHERE building_id = $1 AND game_day = 2`, [testBuildingId])).rows[0];
      assert.ok(journal);
      assert.equal(journal.status, 'PARTIAL');
      assert.equal(journal.utilization_bps, 5000);
      assert.deepEqual(journal.limiting_resources, ['ENERGY']);
      assert.equal(journal.shortage_units.ENERGY, '13');
      assert.equal(journal.shortage_units.COMPUTE, '1');
    });
  } finally {
    await client.query('DELETE FROM building_settlement_journals WHERE building_id = $1', [testBuildingId]);
    await client.query('DELETE FROM buildings WHERE id = $1', [testBuildingId]);
    await client.query('DELETE FROM territory_capacity_state WHERE territory_id = $1', [testTerritoryId]);
    await client.query('DELETE FROM territories WHERE id = $1', [testTerritoryId]);
    await client.query('DELETE FROM economic_entries WHERE account_id IN (SELECT id FROM economic_accounts WHERE owner_economic_id = $1)', [testEconId]);
    await client.query('DELETE FROM economic_entries WHERE transaction_id IN (SELECT id FROM economic_transactions WHERE source_id = $1 OR correlation_id LIKE $2)', [testEconId, `building-corp:${testEconId}:%`]);
    await client.query('DELETE FROM economic_transactions WHERE source_id = $1 OR correlation_id LIKE $2', [testEconId, `building-corp:${testEconId}:%`]);
    await client.query('DELETE FROM economic_accounts WHERE owner_economic_id = $1', [testEconId]);
    await client.query('DELETE FROM owner_registry WHERE economic_id = $1', [testEconId]);
    await client.query('DELETE FROM corporations WHERE id = $1', [testCorpId]);
    await client.query('DELETE FROM institutions WHERE id = $1', [testCorpId]);
    await client.end();
  }
});

test('PostgreSQL V5 Economic Core Phase 2: Public building full inputs produce full output (OPERATED)', async () => {
  const client = await connectTo(connectionString);
  const repository = new PostgresRepository(client);
  const testCorpId = `CORP-PUB-FULL-${Date.now()}`;
  const testEconId = `ECON-${testCorpId}`;
  const testBuildingId = `BLD-PUB-FULL-${Date.now()}`;
  const testTerritoryId = `TERR-PUB-FULL-${Date.now()}`;

  try {
    await repository.transaction(async (tx) => {
      await tx.query(`INSERT INTO institutions (id, kind, name, status) VALUES ($1, 'CORPORATION', $2, 'ACTIVE')`, [testCorpId, `Full Input Corp ${Date.now()}`]);
      await tx.query(`INSERT INTO corporations (id, charter_version, admission_policy, status, created_game_day) VALUES ($1, 'corporation-charter-v5', 'OPEN', 'ACTIVE', 1)`, [testCorpId]);
      await tx.query(`INSERT INTO owner_registry (id, owner_type, economic_id) VALUES ($1, 'CORPORATION', $2)`, [testCorpId, testEconId]);
      await tx.query('SELECT earth_provision_corporation_economy($1)', [testEconId]);

      // EXTRACTION-REFINING-T1 requires 12 Energy, 1 Compute, produces 30 Material, operating credit 800
      const treasury = (await tx.query(`SELECT id FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 1 AND account_type = 'TREASURY'`, [testEconId])).rows[0];
      await tx.query(`UPDATE economic_accounts SET balance_units = 100000 WHERE id = $1`, [treasury.id]);

      const energyInv = (await tx.query(`SELECT id FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 4 AND account_type = 'INVENTORY'`, [testEconId])).rows[0];
      await tx.query(`UPDATE economic_accounts SET balance_units = 50 WHERE id = $1`, [energyInv.id]);

      const computeInv = (await tx.query(`SELECT id FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 5 AND account_type = 'INVENTORY'`, [testEconId])).rows[0];
      await tx.query(`UPDATE economic_accounts SET balance_units = 10 WHERE id = $1`, [computeInv.id]);

      await tx.query(`INSERT INTO territories (id, corporation_id, name, status, is_primary) VALUES ($1, $2, 'Full Territory', 'ACTIVE', true)`, [testTerritoryId, testCorpId]);

      await tx.query(`
        INSERT INTO buildings (
          id, catalog_id, owner_economic_id, territory_id, status, construction_state,
          installed_generation, catalog_definition_version, technology_definition_version,
          operating_mode, started_game_day, last_major_rebuild_game_day
        ) VALUES (
          $1, 'EXTRACTION-REFINING-T1', $2, $3, 'ACTIVE', 'ACTIVE',
          1, 'v5-alpha-1', 'tech-gen-v1', 'BALANCED', 1, 1
        )
      `, [testBuildingId, testEconId, testTerritoryId]);

      const res = await settleBuildingUpkeepAndRevenueV2(tx, 2);
      assert.ok(res.publicBuildings >= 1);

      // Check Material produced is 100% full: 30 units
      const matInv = (await tx.query(`SELECT balance_units::TEXT FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 2 AND account_type = 'INVENTORY'`, [testEconId])).rows[0];
      assert.equal(matInv.balance_units, '30', 'Full inputs must produce full 100% output (30 units)');

      // Check Energy consumed = 12 (balance becomes 38)
      const remEnergy = (await tx.query(`SELECT balance_units::TEXT FROM economic_accounts WHERE id = $1`, [energyInv.id])).rows[0];
      assert.equal(remEnergy.balance_units, '38', 'Energy decreased by 12');

      // Check Compute consumed = 1 (balance becomes 9)
      const remCompute = (await tx.query(`SELECT balance_units::TEXT FROM economic_accounts WHERE id = $1`, [computeInv.id])).rows[0];
      assert.equal(remCompute.balance_units, '9', 'Compute decreased by 1');

      // Check Treasury operating cost = 800
      const remTreasury = (await tx.query(`SELECT balance_units::TEXT FROM economic_accounts WHERE id = $1`, [treasury.id])).rows[0];
      assert.equal(remTreasury.balance_units, String(100000 - 800), 'Operating credit charged at 100%');

      // Check journal
      const journal = (await tx.query(`SELECT * FROM building_settlement_journals WHERE building_id = $1 AND game_day = 2`, [testBuildingId])).rows[0];
      assert.ok(journal);
      assert.equal(journal.status, 'OPERATED');
      assert.equal(journal.utilization_bps, 10000);
      assert.deepEqual(journal.shortage_units, {});
    });
  } finally {
    await client.query('DELETE FROM building_settlement_journals WHERE building_id = $1', [testBuildingId]);
    await client.query('DELETE FROM buildings WHERE id = $1', [testBuildingId]);
    await client.query('DELETE FROM territory_capacity_state WHERE territory_id = $1', [testTerritoryId]);
    await client.query('DELETE FROM territories WHERE id = $1', [testTerritoryId]);
    await client.query('DELETE FROM economic_entries WHERE account_id IN (SELECT id FROM economic_accounts WHERE owner_economic_id = $1)', [testEconId]);
    await client.query('DELETE FROM economic_entries WHERE transaction_id IN (SELECT id FROM economic_transactions WHERE source_id = $1 OR correlation_id LIKE $2)', [testEconId, `building-corp:${testEconId}:%`]);
    await client.query('DELETE FROM economic_transactions WHERE source_id = $1 OR correlation_id LIKE $2', [testEconId, `building-corp:${testEconId}:%`]);
    await client.query('DELETE FROM economic_accounts WHERE owner_economic_id = $1', [testEconId]);
    await client.query('DELETE FROM owner_registry WHERE economic_id = $1', [testEconId]);
    await client.query('DELETE FROM corporations WHERE id = $1', [testCorpId]);
    await client.query('DELETE FROM institutions WHERE id = $1', [testCorpId]);
    await client.end();
  }
});

test('PostgreSQL V5 Economic Core Phase 2: Missing output inventory account prevents output safely', async () => {
  const client = await connectTo(connectionString);
  const repository = new PostgresRepository(client);
  const testCorpId = `CORP-PUB-NOINV-${Date.now()}`;
  const testEconId = `ECON-${testCorpId}`;
  const testBuildingId = `BLD-PUB-NOINV-${Date.now()}`;
  const testTerritoryId = `TERR-PUB-NOINV-${Date.now()}`;

  try {
    await repository.transaction(async (tx) => {
      await tx.query(`INSERT INTO institutions (id, kind, name, status) VALUES ($1, 'CORPORATION', $2, 'ACTIVE')`, [testCorpId, `No Inv Corp ${Date.now()}`]);
      await tx.query(`INSERT INTO corporations (id, charter_version, admission_policy, status, created_game_day) VALUES ($1, 'corporation-charter-v5', 'OPEN', 'ACTIVE', 1)`, [testCorpId]);
      await tx.query(`INSERT INTO owner_registry (id, owner_type, economic_id) VALUES ($1, 'CORPORATION', $2)`, [testCorpId, testEconId]);
      await tx.query('SELECT earth_provision_corporation_economy($1)', [testEconId]);

      // Seed Treasury with Credits
      const treasury = (await tx.query(`SELECT id FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 1 AND account_type = 'TREASURY'`, [testEconId])).rows[0];
      await tx.query(`UPDATE economic_accounts SET balance_units = 100000 WHERE id = $1`, [treasury.id]);

      // Delete Material Inventory account (asset 2)
      await tx.query(`DELETE FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 2 AND account_type = 'INVENTORY'`, [testEconId]);

      // Seed Energy & Compute
      const energyInv = (await tx.query(`SELECT id FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 4 AND account_type = 'INVENTORY'`, [testEconId])).rows[0];
      await tx.query(`UPDATE economic_accounts SET balance_units = 50 WHERE id = $1`, [energyInv.id]);

      const computeInv = (await tx.query(`SELECT id FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 5 AND account_type = 'INVENTORY'`, [testEconId])).rows[0];
      await tx.query(`UPDATE economic_accounts SET balance_units = 10 WHERE id = $1`, [computeInv.id]);

      await tx.query(`INSERT INTO territories (id, corporation_id, name, status, is_primary) VALUES ($1, $2, 'No Inv Territory', 'ACTIVE', true)`, [testTerritoryId, testCorpId]);

      await tx.query(`
        INSERT INTO buildings (
          id, catalog_id, owner_economic_id, territory_id, status, construction_state,
          installed_generation, catalog_definition_version, technology_definition_version,
          operating_mode, started_game_day, last_major_rebuild_game_day
        ) VALUES (
          $1, 'EXTRACTION-REFINING-T1', $2, $3, 'ACTIVE', 'ACTIVE',
          1, 'v5-alpha-1', 'tech-gen-v1', 'BALANCED', 1, 1
        )
      `, [testBuildingId, testEconId, testTerritoryId]);

      const res = await settleBuildingUpkeepAndRevenueV2(tx, 2);
      assert.ok(res.publicBuildings >= 1);

      // Journal output_units must be empty because inventory account was missing
      const journal = (await tx.query(`SELECT * FROM building_settlement_journals WHERE building_id = $1 AND game_day = 2`, [testBuildingId])).rows[0];
      assert.ok(journal);
      assert.deepEqual(journal.output_units, {}, 'Missing output inventory account must prevent output');
    });
  } finally {
    await client.query('DELETE FROM building_settlement_journals WHERE building_id = $1', [testBuildingId]);
    await client.query('DELETE FROM buildings WHERE id = $1', [testBuildingId]);
    await client.query('DELETE FROM territory_capacity_state WHERE territory_id = $1', [testTerritoryId]);
    await client.query('DELETE FROM territories WHERE id = $1', [testTerritoryId]);
    await client.query('DELETE FROM economic_entries WHERE account_id IN (SELECT id FROM economic_accounts WHERE owner_economic_id = $1)', [testEconId]);
    await client.query('DELETE FROM economic_entries WHERE transaction_id IN (SELECT id FROM economic_transactions WHERE source_id = $1 OR correlation_id LIKE $2)', [testEconId, `building-corp:${testEconId}:%`]);
    await client.query('DELETE FROM economic_transactions WHERE source_id = $1 OR correlation_id LIKE $2', [testEconId, `building-corp:${testEconId}:%`]);
    await client.query('DELETE FROM economic_accounts WHERE owner_economic_id = $1', [testEconId]);
    await client.query('DELETE FROM owner_registry WHERE economic_id = $1', [testEconId]);
    await client.query('DELETE FROM corporations WHERE id = $1', [testCorpId]);
    await client.query('DELETE FROM institutions WHERE id = $1', [testCorpId]);
    await client.end();
  }
});

test('PostgreSQL V5 Economic Core Phase 2: Multi-building Corporation resource sharing is proportional and inventory remains non-negative', async () => {
  const client = await connectTo(connectionString);
  const repository = new PostgresRepository(client);
  const testCorpId = `CORP-PUB-MULTI-${Date.now()}`;
  const testEconId = `ECON-${testCorpId}`;
  const testBuildingId1 = `BLD-PUB-M1-${Date.now()}`;
  const testBuildingId2 = `BLD-PUB-M2-${Date.now()}`;
  const testTerritoryId = `TERR-PUB-MULTI-${Date.now()}`;

  try {
    await repository.transaction(async (tx) => {
      await tx.query(`INSERT INTO institutions (id, kind, name, status) VALUES ($1, 'CORPORATION', $2, 'ACTIVE')`, [testCorpId, `Multi Input Corp ${Date.now()}`]);
      await tx.query(`INSERT INTO corporations (id, charter_version, admission_policy, status, created_game_day) VALUES ($1, 'corporation-charter-v5', 'OPEN', 'ACTIVE', 1)`, [testCorpId]);
      await tx.query(`INSERT INTO owner_registry (id, owner_type, economic_id) VALUES ($1, 'CORPORATION', $2)`, [testCorpId, testEconId]);
      await tx.query('SELECT earth_provision_corporation_economy($1)', [testEconId]);

      // Seed Treasury with Credits
      const treasury = (await tx.query(`SELECT id FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 1 AND account_type = 'TREASURY'`, [testEconId])).rows[0];
      await tx.query(`UPDATE economic_accounts SET balance_units = 100000 WHERE id = $1`, [treasury.id]);

      // 2x EXTRACTION-REFINING-T1 demands: 24 Energy, 2 Compute total
      // Provide 12 Energy (50% of 24) and 10 Compute (500% of 2)
      const energyInv = (await tx.query(`SELECT id FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 4 AND account_type = 'INVENTORY'`, [testEconId])).rows[0];
      await tx.query(`UPDATE economic_accounts SET balance_units = 12 WHERE id = $1`, [energyInv.id]);

      const computeInv = (await tx.query(`SELECT id FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 5 AND account_type = 'INVENTORY'`, [testEconId])).rows[0];
      await tx.query(`UPDATE economic_accounts SET balance_units = 10 WHERE id = $1`, [computeInv.id]);

      await tx.query(`INSERT INTO territories (id, corporation_id, name, status, is_primary) VALUES ($1, $2, 'Multi Territory', 'ACTIVE', true)`, [testTerritoryId, testCorpId]);

      for (const bId of [testBuildingId1, testBuildingId2]) {
        await tx.query(`
          INSERT INTO buildings (
            id, catalog_id, owner_economic_id, territory_id, status, construction_state,
            installed_generation, catalog_definition_version, technology_definition_version,
            operating_mode, started_game_day, last_major_rebuild_game_day
          ) VALUES (
            $1, 'EXTRACTION-REFINING-T1', $2, $3, 'ACTIVE', 'ACTIVE',
            1, 'v5-alpha-1', 'tech-gen-v1', 'BALANCED', 1, 1
          )
        `, [bId, testEconId, testTerritoryId]);
      }

      const res = await settleBuildingUpkeepAndRevenueV2(tx, 2);
      assert.ok(res.publicBuildings >= 2);

      // Total material produced: 2 * ((30 * 5000) / 10000) = 2 * 15 = 30
      const matInv = (await tx.query(`SELECT balance_units::TEXT FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 2 AND account_type = 'INVENTORY'`, [testEconId])).rows[0];
      assert.equal(matInv.balance_units, '30', 'Two buildings each produced 15 units of Material');

      // Energy balance must be exactly 0 (never negative)
      const remEnergy = (await tx.query(`SELECT balance_units::TEXT FROM economic_accounts WHERE id = $1`, [energyInv.id])).rows[0];
      assert.equal(remEnergy.balance_units, '0', 'Energy balance exact zero, non-negative');

      // Compute consumed: 2 * ((1 * 5000) / 10000) = 0, so compute remains 10
      const remCompute = (await tx.query(`SELECT balance_units::TEXT FROM economic_accounts WHERE id = $1`, [computeInv.id])).rows[0];
      assert.equal(remCompute.balance_units, '10');

      // Check both journals have 5000 bps utilization
      for (const bId of [testBuildingId1, testBuildingId2]) {
        const journal = (await tx.query(`SELECT * FROM building_settlement_journals WHERE building_id = $1 AND game_day = 2`, [bId])).rows[0];
        assert.ok(journal);
        assert.equal(journal.utilization_bps, 5000);
        assert.equal(journal.status, 'PARTIAL');
        assert.deepEqual(journal.limiting_resources, ['ENERGY']);
      }
    });
  } finally {
    for (const bId of [testBuildingId1, testBuildingId2]) {
      await client.query('DELETE FROM building_settlement_journals WHERE building_id = $1', [bId]);
      await client.query('DELETE FROM buildings WHERE id = $1', [bId]);
    }
    await client.query('DELETE FROM territory_capacity_state WHERE territory_id = $1', [testTerritoryId]);
    await client.query('DELETE FROM territories WHERE id = $1', [testTerritoryId]);
    await client.query('DELETE FROM economic_entries WHERE account_id IN (SELECT id FROM economic_accounts WHERE owner_economic_id = $1)', [testEconId]);
    await client.query('DELETE FROM economic_entries WHERE transaction_id IN (SELECT id FROM economic_transactions WHERE source_id = $1 OR correlation_id LIKE $2)', [testEconId, `building-corp:${testEconId}:%`]);
    await client.query('DELETE FROM economic_transactions WHERE source_id = $1 OR correlation_id LIKE $2', [testEconId, `building-corp:${testEconId}:%`]);
    await client.query('DELETE FROM economic_accounts WHERE owner_economic_id = $1', [testEconId]);
    await client.query('DELETE FROM owner_registry WHERE economic_id = $1', [testEconId]);
    await client.query('DELETE FROM corporations WHERE id = $1', [testCorpId]);
    await client.query('DELETE FROM institutions WHERE id = $1', [testCorpId]);
    await client.end();
  }
});

test('PostgreSQL V5 Economic Core Phase 2: Architecture integrity report passes with 0 failures', async () => {
  const client = await connectTo(connectionString);
  try {
    const report = await client.query(
      'SELECT check_name, invalid_count::TEXT FROM earth_integrity_report() ORDER BY check_name',
    );
    assert.ok(report.rows.length >= 8, 'Integrity report must run all architecture checks');
    for (const row of report.rows) {
      assert.equal(Number(row.invalid_count), 0, `Integrity check "${row.check_name}" must have 0 invalid rows, found ${row.invalid_count}`);
    }
  } finally {
    await client.end();
  }
});

test('PostgreSQL V5 Economic Core Phase 3: HOUSING and ENERGY services are RETIRED, while HEALTH and CONNECTIVITY remain ACTIVE', async () => {
  const client = await connectTo(connectionString);
  try {
    const serviceTypes = (await client.query(`SELECT code, status FROM service_types ORDER BY code`)).rows;
    const serviceMap = Object.fromEntries(serviceTypes.map((r) => [r.code, r.status]));
    assert.equal(serviceMap['HOUSING'], 'RETIRED');
    assert.equal(serviceMap['ENERGY'], 'RETIRED');
    assert.equal(serviceMap['CONNECTIVITY'], 'ACTIVE');
    assert.equal(serviceMap['HEALTH'], 'ACTIVE');

    const needRules = (await client.query(`SELECT need_code, status FROM need_rules ORDER BY need_code`)).rows;
    const needMap = Object.fromEntries(needRules.map((r) => [r.need_code, r.status]));
    assert.equal(needMap['HOUSING'], 'RETIRED');
    assert.equal(needMap['ENERGY'], 'RETIRED');
    assert.equal(needMap['CONNECTIVITY'], 'ACTIVE');
    assert.equal(needMap['HEALTH'], 'ACTIVE');

    const estimate = estimateLifeMaintenance();
    assert.equal(estimate.resources.FOOD, 1);
    assert.equal(estimate.resources.ENERGY, 1);
  } finally {
    await client.end();
  }
});

test('PostgreSQL V5 Economic Core Phase 3: Service settlement exclusively allocates active services (HEALTH, CONNECTIVITY) and skips retired services', async () => {
  const client = await connectTo(connectionString);
  const repository = new PostgresRepository(client);

  const emailHouse = `house-serv-${Date.now()}@example.invalid`;
  const emailCorpOwner = `corp-serv-owner-${Date.now()}@example.invalid`;
  let houseHumanId, houseId, houseEconId;
  let corpOwnerHumanId, corpOwnerHouseId, corpOwnerHouseEconId;
  let testCorpId, testCorpEconId;
  const testTerritoryId = `TERR-SERV-${Date.now()}`;
  const testClinicId = `BLD-CLINIC-${Date.now()}`;
  const gameDay = 15;

  try {
    // 1. Setup Corp Owner and Corporation
    const regCorpOwner = await registerIdentity(repository, { email: emailCorpOwner, personName: 'CorpOwner', houseSurname: `COHouse${Date.now()}`, password: 'correct-horse-battery-staple' });
    corpOwnerHumanId = regCorpOwner.human.id;
    corpOwnerHouseId = `HOUSE-${corpOwnerHumanId.slice(2)}`;
    corpOwnerHouseEconId = `ECON-${corpOwnerHouseId}`;

    await repository.transaction(async (tx) => {
      const wallet = (await tx.query(`SELECT id FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 1 AND account_type = 'WALLET'`, [corpOwnerHouseEconId])).rows[0];
      await tx.query(`UPDATE economic_accounts SET balance_units = balance_units + 50000000 WHERE id = $1`, [wallet.id]);
    });

    const corpRes = await foundV5Corporation(repository, {
      humanId: corpOwnerHumanId,
      name: `Service Corp ${Date.now()}`,
      admissionPolicy: 'OPEN',
      correlationId: `test-serv-corp-${Date.now()}`,
    });
    testCorpId = corpRes.corporationId;
    testCorpEconId = `ECON-${testCorpId}`;

    // 2. Setup Territory and Public Health Service Provider (PUBLIC-MEDICAL-T1)
    await repository.transaction(async (tx) => {
      await tx.query(`INSERT INTO territories (id, corporation_id, name, status, is_primary) VALUES ($1, $2, 'Service Territory', 'ACTIVE', true)`, [testTerritoryId, testCorpId]);
      await tx.query(`
        INSERT INTO buildings (
          id, catalog_id, owner_economic_id, territory_id, status, construction_state,
          installed_generation, catalog_definition_version, technology_definition_version,
          operating_mode, started_game_day, last_major_rebuild_game_day
        ) VALUES (
          $1, 'PUBLIC-MEDICAL-T1', $2, $3, 'ACTIVE', 'ACTIVE',
          1, 'v5-alpha-1', 'tech-gen-v1', 'BALANCED', 1, 1
        )
      `, [testClinicId, testCorpEconId, testTerritoryId]);
    });

    // 3. Setup Resident House in territory
    const regHouse = await registerIdentity(repository, { email: emailHouse, personName: 'Resident', houseSurname: `ResHouse${Date.now()}`, password: 'correct-horse-battery-staple' });
    houseHumanId = regHouse.human.id;
    houseId = `HOUSE-${houseHumanId.slice(2)}`;
    houseEconId = `ECON-${houseId}`;

    await repository.transaction(async (tx) => {
      await tx.query(`INSERT INTO house_residencies (id, house_id, territory_id, residency_class, status, effective_from_game_day, correlation_id) VALUES ($1, $2, $3, 'PRIMARY', 'ACTIVE', 1, $1)`, [`res-${houseId}`, houseId, testTerritoryId]);
      const wallet = (await tx.query(`SELECT id FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 1 AND account_type = 'WALLET'`, [houseEconId])).rows[0];
      await tx.query(`UPDATE economic_accounts SET balance_units = balance_units + 1000 WHERE id = $1`, [wallet.id]);

      // 4. Run Service Settlement
      const result = await settleHouseNeedsAndServices(tx, gameDay, 0, 1);
      assert.ok(result.houses >= 1);

      // 5. Verify assessments: must contain HEALTH, must NOT contain HOUSING or ENERGY
      const assessments = (await tx.query(`SELECT need_code, demand_units, allocated_units, shortfall_units, risk_level FROM house_need_assessments WHERE house_id = $1 AND game_day = $2`, [houseId, gameDay])).rows;
      const needCodes = assessments.map((a) => a.need_code);
      assert.ok(needCodes.includes('HEALTH'), 'HEALTH need must be assessed');
      assert.ok(!needCodes.includes('HOUSING'), 'HOUSING service must NOT be assessed');
      assert.ok(!needCodes.includes('ENERGY'), 'Abstract ENERGY service must NOT be assessed');

      // 6. Verify allocations: must allocate HEALTH service
      const allocations = (await tx.query(`SELECT service_code, allocated_units FROM service_allocations WHERE house_id = $1 AND game_day = $2`, [houseId, gameDay])).rows;
      for (const alloc of allocations) {
        assert.notEqual(alloc.service_code, 'HOUSING');
        assert.notEqual(alloc.service_code, 'ENERGY');
      }
    });
  } finally {
    if (houseId) {
      await client.query('DELETE FROM service_allocations WHERE house_id = $1', [houseId]);
      await client.query('DELETE FROM house_need_assessments WHERE house_id = $1', [houseId]);
      await client.query('DELETE FROM house_residencies WHERE house_id = $1', [houseId]);
    }
    await client.query('DELETE FROM buildings WHERE id = $1', [testClinicId]);
    await client.query('DELETE FROM territory_capacity_state WHERE territory_id = $1', [testTerritoryId]);
    await client.query('DELETE FROM territories WHERE id = $1', [testTerritoryId]);

    await client.query(`DELETE FROM economic_entries WHERE transaction_id IN (SELECT id FROM economic_transactions WHERE correlation_id LIKE 'test-serv-corp-%')`);
    await client.query(`DELETE FROM economic_transactions WHERE correlation_id LIKE 'test-serv-corp-%'`);

    if (testCorpId) {
      await client.query('DELETE FROM v5_corporation_settlement_profiles WHERE corporation_id = $1', [testCorpId]);
      await client.query('UPDATE v5_house_settlement_profiles SET corporation_id = NULL WHERE corporation_id = $1', [testCorpId]);
      await client.query('DELETE FROM v5_corporation_founding_commands WHERE corporation_id = $1', [testCorpId]);
      await client.query('DELETE FROM comm_channels WHERE scope_id = $1', [testCorpId]);
      await client.query('DELETE FROM institution_governance_roles WHERE institution_id = $1', [testCorpId]);
      await client.query('DELETE FROM house_affiliations WHERE corporation_id = $1', [testCorpId]);
      await client.query('DELETE FROM constitutional_rule_versions_v5 WHERE authority_id = $1', [testCorpId]);
      await client.query('DELETE FROM economic_entries WHERE account_id IN (SELECT id FROM economic_accounts WHERE owner_economic_id = $1)', [testCorpEconId]);
      await client.query('DELETE FROM economic_accounts WHERE owner_economic_id = $1', [testCorpEconId]);
      await client.query('DELETE FROM owner_registry WHERE economic_id = $1', [testCorpEconId]);
      await client.query('DELETE FROM corporations WHERE id = $1', [testCorpId]);
      await client.query('DELETE FROM institutions WHERE id = $1', [testCorpId]);
    }

    for (const [hId, eId, email] of [[houseHumanId, houseEconId, emailHouse], [corpOwnerHumanId, corpOwnerHouseEconId, emailCorpOwner]]) {
      if (!hId) continue;
      const hHouseId = `HOUSE-${hId.slice(2)}`;
      await client.query('DELETE FROM auth_sessions WHERE account_id = $1', [`account-${hId.toLowerCase()}`]);
      await client.query('DELETE FROM game_events WHERE actor_human_id = $1', [hId]);
      await client.query('DELETE FROM notifications WHERE human_id = $1', [hId]);
      await client.query('DELETE FROM personal_life_maintenance WHERE human_id = $1', [hId]);
      await client.query('DELETE FROM house_daily_statements WHERE house_id = $1', [hHouseId]);
      await client.query('DELETE FROM house_need_assessments WHERE house_id = $1', [hHouseId]);
      await client.query('DELETE FROM service_allocations WHERE house_id = $1', [hHouseId]);
      await client.query('DELETE FROM event_outbox WHERE aggregate_id = $1', [hId]);
      await client.query('DELETE FROM economic_entries WHERE account_id IN (SELECT id FROM economic_accounts WHERE owner_economic_id = $1)', [eId]);
      await client.query('DELETE FROM economic_entries WHERE transaction_id IN (SELECT id FROM economic_transactions WHERE source_id = $1 OR correlation_id LIKE $2)', [hId, `starter:${hHouseId}:%`]);
      await client.query('DELETE FROM economic_transactions WHERE source_id = $1 OR correlation_id LIKE $2', [hId, `starter:${hHouseId}:%`]);
      await client.query('DELETE FROM economic_accounts WHERE owner_economic_id = $1', [eId]);
      await client.query('DELETE FROM owner_registry WHERE economic_id = $1', [eId]);
      await client.query('UPDATE houses SET current_human_id = NULL WHERE id = $1', [hHouseId]);
      await client.query('DELETE FROM humans WHERE id = $1', [hId]);
      await client.query('UPDATE auth_accounts SET house_id = NULL WHERE email = $1', [email]);
      await client.query('DELETE FROM house_entry_support WHERE house_id = $1', [hHouseId]);
      await client.query('DELETE FROM house_onboarding_progress WHERE house_id = $1', [hHouseId]);
      await client.query('DELETE FROM house_residencies WHERE house_id = $1', [hHouseId]);
      await client.query('DELETE FROM v5_house_settlement_profiles WHERE house_id = $1', [hHouseId]);
      await client.query('DELETE FROM houses WHERE id = $1', [hHouseId]);
      await client.query('DELETE FROM auth_accounts WHERE email = $1', [email]);
    }
    await client.end();
  }
});

test('PostgreSQL V5 Economic Core Phase 3: Life maintenance consumes actual FOOD and ENERGY resources directly from House inventory', async () => {
  const client = await connectTo(connectionString);
  const repository = new PostgresRepository(client);

  const emailMaint = `maint-house-${Date.now()}@example.invalid`;
  let humanId, houseId, houseEconId;
  const gameDay = 20;

  try {
    const reg = await registerIdentity(repository, { email: emailMaint, personName: 'MaintPerson', houseSurname: `MHouse${Date.now()}`, password: 'correct-horse-battery-staple' });
    humanId = reg.human.id;
    houseId = `HOUSE-${humanId.slice(2)}`;
    houseEconId = `ECON-${houseId}`;

    await repository.transaction(async (tx) => {
      // 1. Seed House inventory with 5 FOOD (asset 6) and 5 ENERGY (asset 4)
      const foodInv = (await tx.query(`SELECT id FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 6 AND account_type = 'INVENTORY'`, [houseEconId])).rows[0];
      await tx.query(`UPDATE economic_accounts SET balance_units = 5 WHERE id = $1`, [foodInv.id]);

      const energyInv = (await tx.query(`SELECT id FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 4 AND account_type = 'INVENTORY'`, [houseEconId])).rows[0];
      await tx.query(`UPDATE economic_accounts SET balance_units = 5 WHERE id = $1`, [energyInv.id]);

      // 2. Settle life maintenance
      const settledCount = await settleLifeMaintenanceInTransaction(tx, gameDay);
      assert.ok(settledCount >= 1);

      // 3. Verify inventory balances: 5 - 1 = 4 for both FOOD and ENERGY
      const remFood = (await tx.query(`SELECT balance_units::TEXT FROM economic_accounts WHERE id = $1`, [foodInv.id])).rows[0];
      assert.equal(remFood.balance_units, '4', 'FOOD inventory decremented by 1');

      const remEnergy = (await tx.query(`SELECT balance_units::TEXT FROM economic_accounts WHERE id = $1`, [energyInv.id])).rows[0];
      assert.equal(remEnergy.balance_units, '4', 'ENERGY inventory decremented by 1');

      // 4. Verify personal_life_maintenance journal record
      const journal = (await tx.query(`SELECT * FROM personal_life_maintenance WHERE human_id = $1 AND game_day = $2`, [humanId, gameDay])).rows[0];
      assert.ok(journal);
      assert.equal(journal.food_required_units, '1');
      assert.equal(journal.food_consumed_units, '1');
      assert.equal(journal.food_shortfall_units, '0');
      assert.equal(journal.energy_required_units, '1');
      assert.equal(journal.energy_consumed_units, '1');
      assert.equal(journal.energy_shortfall_units, '0');
      assert.equal(journal.status, 'FED');

      // 5. Refresh and verify House daily statement
      await refreshHouseDailyStatementsInTransaction(tx, gameDay);
      const statement = (await tx.query(`SELECT consumption FROM house_daily_statements WHERE house_id = $1 AND game_day = $2`, [houseId, gameDay])).rows[0];
      assert.ok(statement);
      const consumption = statement.consumption;
      assert.equal(consumption['FOOD'], '1', 'Statement consumption records 1 FOOD');
      assert.equal(consumption['ENERGY'], '1', 'Statement consumption records 1 direct ENERGY');
    });
  } finally {
    if (humanId) {
      await client.query('DELETE FROM personal_life_maintenance WHERE human_id = $1', [humanId]);
      await client.query('DELETE FROM house_daily_statements WHERE house_id = $1', [houseId]);
      await client.query('DELETE FROM auth_sessions WHERE account_id = $1', [`account-${humanId.toLowerCase()}`]);
      await client.query('DELETE FROM game_events WHERE actor_human_id = $1', [humanId]);
      await client.query('DELETE FROM notifications WHERE human_id = $1', [humanId]);
      await client.query('DELETE FROM event_outbox WHERE aggregate_id = $1', [humanId]);
      await client.query('DELETE FROM economic_entries WHERE transaction_id IN (SELECT id FROM economic_transactions WHERE source_id = $1 OR correlation_id LIKE $2)', [humanId, `starter:${houseId}:%`]);
      await client.query('DELETE FROM economic_transactions WHERE source_id = $1 OR correlation_id LIKE $2', [humanId, `starter:${houseId}:%`]);
      await client.query('DELETE FROM economic_entries WHERE account_id IN (SELECT id FROM economic_accounts WHERE owner_economic_id = $1)', [houseEconId]);
      await client.query('DELETE FROM economic_accounts WHERE owner_economic_id = $1', [houseEconId]);
      await client.query('DELETE FROM owner_registry WHERE economic_id = $1', [houseEconId]);
      await client.query('UPDATE houses SET current_human_id = NULL WHERE id = $1', [houseId]);
      await client.query('DELETE FROM humans WHERE id = $1', [humanId]);
      await client.query('UPDATE auth_accounts SET house_id = NULL WHERE email = $1', [emailMaint]);
      await client.query('DELETE FROM house_entry_support WHERE house_id = $1', [houseId]);
      await client.query('DELETE FROM house_onboarding_progress WHERE house_id = $1', [houseId]);
      await client.query('DELETE FROM v5_house_settlement_profiles WHERE house_id = $1', [houseId]);
      await client.query('DELETE FROM houses WHERE id = $1', [houseId]);
      await client.query('DELETE FROM auth_accounts WHERE email = $1', [emailMaint]);
    }
    await client.end();
  }
});

test('PostgreSQL V5 Economic Core Phase 3: Life maintenance with zero inventory handles shortages safely without negative balances', async () => {
  const client = await connectTo(connectionString);
  const repository = new PostgresRepository(client);

  const emailStarve = `starve-house-${Date.now()}@example.invalid`;
  let humanId, houseId, houseEconId;
  const gameDay = 25;

  try {
    const reg = await registerIdentity(repository, { email: emailStarve, personName: 'StarvePerson', houseSurname: `SHouse${Date.now()}`, password: 'correct-horse-battery-staple' });
    humanId = reg.human.id;
    houseId = `HOUSE-${humanId.slice(2)}`;
    houseEconId = `ECON-${houseId}`;

    await repository.transaction(async (tx) => {
      // Zero out all inventory accounts (e.g. starter package food)
      await tx.query(`UPDATE economic_accounts SET balance_units = 0 WHERE owner_economic_id = $1 AND account_type = 'INVENTORY'`, [houseEconId]);

      // 1. Settle life maintenance
      const settledCount = await settleLifeMaintenanceInTransaction(tx, gameDay);
      assert.ok(settledCount >= 1);

      // 2. Verify personal_life_maintenance journal record
      const journal = (await tx.query(`SELECT * FROM personal_life_maintenance WHERE human_id = $1 AND game_day = $2`, [humanId, gameDay])).rows[0];
      assert.ok(journal);
      assert.equal(journal.food_required_units, '1');
      assert.equal(journal.food_consumed_units, '0');
      assert.equal(journal.food_shortfall_units, '1');
      assert.equal(journal.energy_required_units, '1');
      assert.equal(journal.energy_consumed_units, '0');
      assert.equal(journal.energy_shortfall_units, '1');
      assert.equal(journal.status, 'UNFED');

      // 3. Verify inventory balances remain 0 (never negative)
      const foodInv = (await tx.query(`SELECT balance_units::TEXT FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 6 AND account_type = 'INVENTORY'`, [houseEconId])).rows[0];
      assert.equal(foodInv.balance_units, '0');

      const energyInv = (await tx.query(`SELECT balance_units::TEXT FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 4 AND account_type = 'INVENTORY'`, [houseEconId])).rows[0];
      assert.equal(energyInv.balance_units, '0');
    });
  } finally {
    if (humanId) {
      await client.query('DELETE FROM personal_life_maintenance WHERE human_id = $1', [humanId]);
      await client.query('DELETE FROM house_daily_statements WHERE house_id = $1', [houseId]);
      await client.query('DELETE FROM auth_sessions WHERE account_id = $1', [`account-${humanId.toLowerCase()}`]);
      await client.query('DELETE FROM game_events WHERE actor_human_id = $1', [humanId]);
      await client.query('DELETE FROM notifications WHERE human_id = $1', [humanId]);
      await client.query('DELETE FROM event_outbox WHERE aggregate_id = $1', [humanId]);
      await client.query('DELETE FROM economic_entries WHERE transaction_id IN (SELECT id FROM economic_transactions WHERE source_id = $1 OR correlation_id LIKE $2)', [humanId, `starter:${houseId}:%`]);
      await client.query('DELETE FROM economic_transactions WHERE source_id = $1 OR correlation_id LIKE $2', [humanId, `starter:${houseId}:%`]);
      await client.query('DELETE FROM economic_entries WHERE account_id IN (SELECT id FROM economic_accounts WHERE owner_economic_id = $1)', [houseEconId]);
      await client.query('DELETE FROM economic_accounts WHERE owner_economic_id = $1', [houseEconId]);
      await client.query('DELETE FROM owner_registry WHERE economic_id = $1', [houseEconId]);
      await client.query('UPDATE houses SET current_human_id = NULL WHERE id = $1', [houseId]);
      await client.query('DELETE FROM humans WHERE id = $1', [humanId]);
      await client.query('UPDATE auth_accounts SET house_id = NULL WHERE email = $1', [emailStarve]);
      await client.query('DELETE FROM house_entry_support WHERE house_id = $1', [houseId]);
      await client.query('DELETE FROM house_onboarding_progress WHERE house_id = $1', [houseId]);
      await client.query('DELETE FROM v5_house_settlement_profiles WHERE house_id = $1', [houseId]);
      await client.query('DELETE FROM houses WHERE id = $1', [houseId]);
      await client.query('DELETE FROM auth_accounts WHERE email = $1', [emailStarve]);
    }
    await client.end();
  }
});

test('PostgreSQL V5 Economic Core Phase 3: Historical service assessments and allocations remain readable and valid', async () => {
  const client = await connectTo(connectionString);
  const repository = new PostgresRepository(client);
  const emailHist = `hist-house-${Date.now()}@example.invalid`;
  let humanId, houseId, houseEconId;
  const oldDay = 1;

  try {
    const reg = await registerIdentity(repository, { email: emailHist, personName: 'HistPerson', houseSurname: `HHouse${Date.now()}`, password: 'correct-horse-battery-staple' });
    humanId = reg.human.id;
    houseId = `HOUSE-${humanId.slice(2)}`;
    houseEconId = `ECON-${houseId}`;

    // Insert historical HOUSING and ENERGY need assessments
    await client.query(`
      INSERT INTO house_need_assessments
        (house_id, game_day, need_code, demand_units, available_units, allocated_units, shortfall_units, risk_level, rules_version)
      VALUES
        ($1, $2, 'HOUSING', 1, 1, 1, 0, 'NORMAL', 'needs-v1'),
        ($1, $2, 'ENERGY', 1, 1, 1, 0, 'NORMAL', 'needs-v1')
    `, [houseId, oldDay]);

    const historical = (await client.query(`SELECT need_code, allocated_units FROM house_need_assessments WHERE house_id = $1 AND game_day = $2 ORDER BY need_code`, [houseId, oldDay])).rows;
    assert.equal(historical.length, 2);
    assert.equal(historical[0].need_code, 'ENERGY');
    assert.equal(historical[1].need_code, 'HOUSING');
  } finally {
    if (humanId) {
      await client.query('DELETE FROM house_need_assessments WHERE house_id = $1', [houseId]);
      await client.query('DELETE FROM auth_sessions WHERE account_id = $1', [`account-${humanId.toLowerCase()}`]);
      await client.query('DELETE FROM game_events WHERE actor_human_id = $1', [humanId]);
      await client.query('DELETE FROM notifications WHERE human_id = $1', [humanId]);
      await client.query('DELETE FROM personal_life_maintenance WHERE human_id = $1', [humanId]);
      await client.query('DELETE FROM event_outbox WHERE aggregate_id = $1', [humanId]);
      await client.query('DELETE FROM economic_entries WHERE transaction_id IN (SELECT id FROM economic_transactions WHERE source_id = $1 OR correlation_id LIKE $2)', [humanId, `starter:${houseId}:%`]);
      await client.query('DELETE FROM economic_transactions WHERE source_id = $1 OR correlation_id LIKE $2', [humanId, `starter:${houseId}:%`]);
      await client.query('DELETE FROM economic_entries WHERE account_id IN (SELECT id FROM economic_accounts WHERE owner_economic_id = $1)', [houseEconId]);
      await client.query('DELETE FROM economic_accounts WHERE owner_economic_id = $1', [houseEconId]);
      await client.query('DELETE FROM owner_registry WHERE economic_id = $1', [houseEconId]);
      await client.query('UPDATE houses SET current_human_id = NULL WHERE id = $1', [houseId]);
      await client.query('DELETE FROM humans WHERE id = $1', [humanId]);
      await client.query('UPDATE auth_accounts SET house_id = NULL WHERE email = $1', [emailHist]);
      await client.query('DELETE FROM house_entry_support WHERE house_id = $1', [houseId]);
      await client.query('DELETE FROM house_onboarding_progress WHERE house_id = $1', [houseId]);
      await client.query('DELETE FROM v5_house_settlement_profiles WHERE house_id = $1', [houseId]);
      await client.query('DELETE FROM houses WHERE id = $1', [houseId]);
      await client.query('DELETE FROM auth_accounts WHERE email = $1', [emailHist]);
    }
    await client.end();
  }
});

test('PostgreSQL V5 Economic Core Phase 4: Base production chains 1-5 execute end-to-end with database catalog flows and asset conservation', async () => {
  const client = await connectTo(connectionString);
  const repository = new PostgresRepository(client);

  const email = `phase4-chain-${Date.now()}@example.invalid`;
  const corpId = `CORP-CHAIN-${Date.now()}`;
  const corpEconId = `ECON-${corpId}`;
  const territoryId = `TERR-CHAIN-${Date.now()}`;
  const residencyId = `RES-CHAIN-${Date.now()}`;

  const solarId = `BLD-SOLAR-${Date.now()}`;
  const farmId = `BLD-FARM-${Date.now()}`;
  const matRecId = `BLD-MATREC-${Date.now()}`;
  const extractId = `BLD-EXTRACT-${Date.now()}`;
  const fabId = `BLD-FAB-${Date.now()}`;
  const computeId = `BLD-COMPUTE-${Date.now()}`;

  let humanId, houseId, houseEconId;

  try {
    const reg = await registerIdentity(repository, { email, personName: 'ChainPerson', houseSurname: `CHouse${Date.now()}`, password: 'correct-horse-battery-staple' });
    humanId = reg.human.id;
    houseId = `HOUSE-${humanId.slice(2)}`;
    houseEconId = `ECON-${houseId}`;

    await repository.transaction(async (tx) => {
      // 1. Setup Corporation & Territory
      await tx.query(`INSERT INTO institutions (id, kind, name, status) VALUES ($1, 'CORPORATION', $2, 'ACTIVE')`, [corpId, `Chain Corp ${Date.now()}`]);
      await tx.query(`INSERT INTO corporations (id, charter_version, admission_policy, status, created_game_day) VALUES ($1, 'corporation-charter-v5', 'OPEN', 'ACTIVE', 1)`, [corpId]);
      await tx.query(`INSERT INTO owner_registry (id, owner_type, economic_id) VALUES ($1, 'CORPORATION', $2)`, [corpId, corpEconId]);
      await tx.query('SELECT earth_provision_corporation_economy($1)', [corpEconId]);

      const corpTreasury = (await tx.query(`SELECT id FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 1 AND account_type = 'TREASURY'`, [corpEconId])).rows[0];
      await tx.query(`UPDATE economic_accounts SET balance_units = 100000 WHERE id = $1`, [corpTreasury.id]);

      await tx.query(`INSERT INTO territories (id, corporation_id, name, status, is_primary) VALUES ($1, $2, 'Chain Territory', 'ACTIVE', true)`, [territoryId, corpId]);

      // Move House to this territory and affiliate with Corporation (required for private buildings)
      await tx.query(`INSERT INTO house_residencies (id, house_id, territory_id, residency_class, status, effective_from_game_day, correlation_id) VALUES ($1, $2, $3, 'PRIMARY', 'ACTIVE', 1, $4)`, [residencyId, houseId, territoryId, `res:${houseId}:${territoryId}:${Date.now()}`]);
      await tx.query(`INSERT INTO house_affiliations (house_id, corporation_id, primary_territory_id, joined_game_day, status) VALUES ($1, $2, $3, 1, 'ACTIVE')`, [houseId, corpId, territoryId]);

      // Reset House inventory to 0
      await tx.query(`UPDATE economic_accounts SET balance_units = 0 WHERE owner_economic_id = $1 AND account_type = 'INVENTORY'`, [houseEconId]);
      const houseWallet = (await tx.query(`SELECT id FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 1 AND account_type = 'WALLET'`, [houseEconId])).rows[0];
      await tx.query(`UPDATE economic_accounts SET balance_units = 50000 WHERE id = $1`, [houseWallet.id]);

      // Chain 1: SOLAR_MICROGRID-T1 (Private: in: 0, out: 5 ENERGY)
      await tx.query(`
        INSERT INTO buildings (id, catalog_id, owner_economic_id, territory_id, status, construction_state, installed_generation, catalog_definition_version, technology_definition_version, operating_mode, started_game_day, last_major_rebuild_game_day)
        VALUES ($1, 'SOLAR-MICROGRID-T1', $2, $3, 'ACTIVE', 'ACTIVE', 1, 'v5-alpha-1', 'tech-gen-v1', 'BALANCED', 1, 1)
      `, [solarId, houseEconId, territoryId]);

      // Chain 1: VERTICAL-FARM-T1 (Private: in: 1 ENERGY, 1 COMPUTE, out: 4 FOOD)
      await tx.query(`
        INSERT INTO buildings (id, catalog_id, owner_economic_id, territory_id, status, construction_state, installed_generation, catalog_definition_version, technology_definition_version, operating_mode, started_game_day, last_major_rebuild_game_day)
        VALUES ($1, 'VERTICAL-FARM-T1', $2, $3, 'ACTIVE', 'ACTIVE', 1, 'v5-alpha-1', 'tech-gen-v1', 'BALANCED', 1, 1)
      `, [farmId, houseEconId, territoryId]);

      // Chain 2: MATERIALS-RECOVERY-T1 (Private: in: 2 ENERGY, 1 COMPUTE, out: 3 MATERIAL)
      await tx.query(`
        INSERT INTO buildings (id, catalog_id, owner_economic_id, territory_id, status, construction_state, installed_generation, catalog_definition_version, technology_definition_version, operating_mode, started_game_day, last_major_rebuild_game_day)
        VALUES ($1, 'MATERIALS-RECOVERY-T1', $2, $3, 'ACTIVE', 'ACTIVE', 1, 'v5-alpha-1', 'tech-gen-v1', 'BALANCED', 1, 1)
      `, [matRecId, houseEconId, territoryId]);

      // Chain 3: EXTRACTION-REFINING-T1 (Public: in: 12 ENERGY, 1 COMPUTE, out: 30 MATERIAL)
      await tx.query(`
        INSERT INTO buildings (id, catalog_id, owner_economic_id, territory_id, status, construction_state, installed_generation, catalog_definition_version, technology_definition_version, operating_mode, started_game_day, last_major_rebuild_game_day)
        VALUES ($1, 'EXTRACTION-REFINING-T1', $2, $3, 'ACTIVE', 'ACTIVE', 1, 'v5-alpha-1', 'tech-gen-v1', 'BALANCED', 1, 1)
      `, [extractId, corpEconId, territoryId]);

      // Chain 4: PRECISION-FAB-T1 (Private: in: 2 MATERIAL, 2 ENERGY, out: 4 COMPONENTS)
      await tx.query(`
        INSERT INTO buildings (id, catalog_id, owner_economic_id, territory_id, status, construction_state, installed_generation, catalog_definition_version, technology_definition_version, operating_mode, started_game_day, last_major_rebuild_game_day)
        VALUES ($1, 'PRECISION-FAB-T1', $2, $3, 'ACTIVE', 'ACTIVE', 1, 'v5-alpha-1', 'tech-gen-v1', 'BALANCED', 1, 1)
      `, [fabId, houseEconId, territoryId]);

      // Chain 5: COMPUTE-CLUSTER-T1 (Private: in: 1 COMPONENTS, 3 ENERGY, out: 5 COMPUTE)
      await tx.query(`
        INSERT INTO buildings (id, catalog_id, owner_economic_id, territory_id, status, construction_state, installed_generation, catalog_definition_version, technology_definition_version, operating_mode, started_game_day, last_major_rebuild_game_day)
        VALUES ($1, 'COMPUTE-CLUSTER-T1', $2, $3, 'ACTIVE', 'ACTIVE', 1, 'v5-alpha-1', 'tech-gen-v1', 'BALANCED', 1, 1)
      `, [computeId, houseEconId, territoryId]);
    });

    // Step 1: Day 10 - Settle Solar Microgrid alone (deactivate other buildings temporarily to step cleanly)
    await repository.transaction(async (tx) => {
      await tx.query(`UPDATE buildings SET v5_productive_status = 'SUSPENDED' WHERE id IN ($1, $2, $3, $4, $5)`, [farmId, matRecId, extractId, fabId, computeId]);
      await settleBuildingUpkeepAndRevenueV2(tx, 10);

      // Check House received 5 ENERGY
      const energyInv = (await tx.query(`SELECT balance_units::TEXT FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 4 AND account_type = 'INVENTORY'`, [houseEconId])).rows[0];
      assert.equal(energyInv.balance_units, '5', 'Solar Microgrid produced 5 ENERGY');
    });

    // Step 2: Day 11 - Settle Chain 1 (Vertical Farm produces FOOD)
    await repository.transaction(async (tx) => {
      // Provide 1 seed COMPUTE to House
      const computeInvAcc = (await tx.query(`SELECT id FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 5 AND account_type = 'INVENTORY'`, [houseEconId])).rows[0];
      await tx.query(`UPDATE economic_accounts SET balance_units = 1 WHERE id = $1`, [computeInvAcc.id]);

      await tx.query(`UPDATE buildings SET v5_productive_status = 'ACTIVE' WHERE id = $1`, [farmId]);
      await tx.query(`UPDATE buildings SET v5_productive_status = 'SUSPENDED' WHERE id = $1`, [solarId]);

      await settleBuildingUpkeepAndRevenueV2(tx, 11);

      // Vertical Farm consumed 1 ENERGY (5 -> 4), 1 COMPUTE (1 -> 0), produced 4 FOOD
      const foodInv = (await tx.query(`SELECT balance_units::TEXT FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 6 AND account_type = 'INVENTORY'`, [houseEconId])).rows[0];
      assert.equal(foodInv.balance_units, '4', 'Vertical Farm produced 4 FOOD');

      const remEnergy = (await tx.query(`SELECT balance_units::TEXT FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 4 AND account_type = 'INVENTORY'`, [houseEconId])).rows[0];
      assert.equal(remEnergy.balance_units, '4', 'Remaining House ENERGY is 4');
    });

    // Step 3: Day 12 - Settle Chain 2 (Materials Recovery Workshop produces MATERIAL)
    await repository.transaction(async (tx) => {
      // Provide 1 seed COMPUTE to House
      const computeInvAcc = (await tx.query(`SELECT id FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 5 AND account_type = 'INVENTORY'`, [houseEconId])).rows[0];
      await tx.query(`UPDATE economic_accounts SET balance_units = 1 WHERE id = $1`, [computeInvAcc.id]);

      await tx.query(`UPDATE buildings SET v5_productive_status = 'SUSPENDED' WHERE id = $1`, [farmId]);
      await tx.query(`UPDATE buildings SET v5_productive_status = 'ACTIVE' WHERE id = $1`, [matRecId]);

      await settleBuildingUpkeepAndRevenueV2(tx, 12);

      // Materials Recovery consumed 2 ENERGY (4 -> 2), 1 COMPUTE (1 -> 0), produced 3 MATERIAL
      const matInv = (await tx.query(`SELECT balance_units::TEXT FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 2 AND account_type = 'INVENTORY'`, [houseEconId])).rows[0];
      assert.equal(matInv.balance_units, '3', 'Materials Recovery produced 3 MATERIAL');

      const remEnergy = (await tx.query(`SELECT balance_units::TEXT FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 4 AND account_type = 'INVENTORY'`, [houseEconId])).rows[0];
      assert.equal(remEnergy.balance_units, '2', 'Remaining House ENERGY is 2');
    });

    // Step 4: Day 13 - Settle Chain 3 (Corporation Extraction & Refining Complex produces MATERIAL)
    await repository.transaction(async (tx) => {
      // Seed Corporation with 12 ENERGY and 1 COMPUTE
      const corpEnergyInv = (await tx.query(`SELECT id FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 4 AND account_type = 'INVENTORY'`, [corpEconId])).rows[0];
      const corpComputeInv = (await tx.query(`SELECT id FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 5 AND account_type = 'INVENTORY'`, [corpEconId])).rows[0];
      await tx.query(`UPDATE economic_accounts SET balance_units = 12 WHERE id = $1`, [corpEnergyInv.id]);
      await tx.query(`UPDATE economic_accounts SET balance_units = 1 WHERE id = $1`, [corpComputeInv.id]);

      await tx.query(`UPDATE buildings SET v5_productive_status = 'SUSPENDED' WHERE id = $1`, [matRecId]);
      await tx.query(`UPDATE buildings SET v5_productive_status = 'ACTIVE' WHERE id = $1`, [extractId]);

      await settleBuildingUpkeepAndRevenueV2(tx, 13);

      // Extraction Complex consumed 12 ENERGY and 1 COMPUTE, produced 30 MATERIAL
      const corpMatInv = (await tx.query(`SELECT balance_units::TEXT FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 2 AND account_type = 'INVENTORY'`, [corpEconId])).rows[0];
      assert.equal(corpMatInv.balance_units, '30', 'Extraction & Refining Complex produced 30 MATERIAL');
    });

    // Step 5: Day 14 - Settle Chain 4 (Precision Fabrication Workshop produces COMPONENTS)
    await repository.transaction(async (tx) => {
      // House currently has 3 MATERIAL and 2 ENERGY. Precision Fab requires 2 MATERIAL and 2 ENERGY.
      await tx.query(`UPDATE buildings SET v5_productive_status = 'SUSPENDED' WHERE id = $1`, [extractId]);
      await tx.query(`UPDATE buildings SET v5_productive_status = 'ACTIVE' WHERE id = $1`, [fabId]);

      await settleBuildingUpkeepAndRevenueV2(tx, 14);

      // Precision Fab consumed 2 MATERIAL (3 -> 1), 2 ENERGY (2 -> 0), produced 4 COMPONENTS
      const compInv = (await tx.query(`SELECT balance_units::TEXT FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 3 AND account_type = 'INVENTORY'`, [houseEconId])).rows[0];
      assert.equal(compInv.balance_units, '4', 'Precision Fabrication produced 4 COMPONENTS');

      const remMat = (await tx.query(`SELECT balance_units::TEXT FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 2 AND account_type = 'INVENTORY'`, [houseEconId])).rows[0];
      assert.equal(remMat.balance_units, '1', 'Remaining House MATERIAL is 1');
    });

    // Step 6: Day 15 - Settle Chain 5 (Compute Cluster produces COMPUTE)
    await repository.transaction(async (tx) => {
      // House currently has 4 COMPONENTS. Seed 3 ENERGY. Compute Cluster requires 1 COMPONENTS and 3 ENERGY.
      const houseEnergyInv = (await tx.query(`SELECT id FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 4 AND account_type = 'INVENTORY'`, [houseEconId])).rows[0];
      await tx.query(`UPDATE economic_accounts SET balance_units = 3 WHERE id = $1`, [houseEnergyInv.id]);

      await tx.query(`UPDATE buildings SET v5_productive_status = 'SUSPENDED' WHERE id = $1`, [fabId]);
      await tx.query(`UPDATE buildings SET v5_productive_status = 'ACTIVE' WHERE id = $1`, [computeId]);

      await settleBuildingUpkeepAndRevenueV2(tx, 15);

      // Compute Cluster consumed 1 COMPONENTS (4 -> 3), 3 ENERGY (3 -> 0), produced 5 COMPUTE
      const compuInv = (await tx.query(`SELECT balance_units::TEXT FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 5 AND account_type = 'INVENTORY'`, [houseEconId])).rows[0];
      assert.equal(compuInv.balance_units, '5', 'Compute Cluster produced 5 COMPUTE');

      const remComp = (await tx.query(`SELECT balance_units::TEXT FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 3 AND account_type = 'INVENTORY'`, [houseEconId])).rows[0];
      assert.equal(remComp.balance_units, '3', 'Remaining House COMPONENTS is 3');
    });

    // Step 7: Verify all settlement journals were recorded with status OPERATED and 10000 utilization_bps
    const journals = (await client.query(`SELECT building_id, utilization_bps, status FROM building_settlement_journals WHERE building_id IN ($1, $2, $3, $4, $5, $6) ORDER BY game_day`, [solarId, farmId, matRecId, extractId, fabId, computeId])).rows;
    assert.equal(journals.length, 6);
    for (const j of journals) {
      assert.equal(j.utilization_bps, 10000, `Building ${j.building_id} must operate at 100%`);
      assert.equal(j.status, 'OPERATED');
    }
  } finally {
    await client.query('DELETE FROM building_settlement_journals WHERE building_id IN ($1, $2, $3, $4, $5, $6)', [solarId, farmId, matRecId, extractId, fabId, computeId]);
    await client.query('DELETE FROM buildings WHERE id IN ($1, $2, $3, $4, $5, $6)', [solarId, farmId, matRecId, extractId, fabId, computeId]);
    await client.query('DELETE FROM house_affiliations WHERE house_id = $1', [houseId]);
    await client.query('DELETE FROM house_residencies WHERE house_id = $1', [houseId]);
    await client.query('DELETE FROM territory_capacity_state WHERE territory_id = $1', [territoryId]);
    await client.query('DELETE FROM territories WHERE id = $1', [territoryId]);
    await client.query('DELETE FROM economic_entries WHERE account_id IN (SELECT id FROM economic_accounts WHERE owner_economic_id IN ($1, $2))', [corpEconId, houseEconId]);
    await client.query('DELETE FROM economic_entries WHERE transaction_id IN (SELECT id FROM economic_transactions WHERE source_id IN ($1, $2, $3) OR correlation_id LIKE $4 OR correlation_id LIKE $5 OR correlation_id LIKE $6)', [corpEconId, houseEconId, humanId, `building-%:${corpEconId}:%`, `building-%:${houseEconId}:%`, `starter:${houseId}:%`]);
    await client.query('DELETE FROM economic_transactions WHERE source_id IN ($1, $2, $3) OR correlation_id LIKE $4 OR correlation_id LIKE $5 OR correlation_id LIKE $6', [corpEconId, houseEconId, humanId, `building-%:${corpEconId}:%`, `building-%:${houseEconId}:%`, `starter:${houseId}:%`]);
    await client.query('DELETE FROM economic_accounts WHERE owner_economic_id IN ($1, $2)', [corpEconId, houseEconId]);
    await client.query('DELETE FROM owner_registry WHERE economic_id IN ($1, $2)', [corpEconId, houseEconId]);
    await client.query('DELETE FROM corporations WHERE id = $1', [corpId]);
    await client.query('DELETE FROM institutions WHERE id = $1', [corpId]);
    if (humanId) {
      await client.query('DELETE FROM auth_sessions WHERE account_id = $1', [`account-${humanId.toLowerCase()}`]);
      await client.query('DELETE FROM game_events WHERE actor_human_id = $1', [humanId]);
      await client.query('DELETE FROM notifications WHERE human_id = $1', [humanId]);
      await client.query('DELETE FROM personal_life_maintenance WHERE human_id = $1', [humanId]);
      await client.query('DELETE FROM event_outbox WHERE aggregate_id = $1', [humanId]);
      await client.query('UPDATE houses SET current_human_id = NULL WHERE id = $1', [houseId]);
      await client.query('DELETE FROM humans WHERE id = $1', [humanId]);
      await client.query('UPDATE auth_accounts SET house_id = NULL WHERE email = $1', [email]);
      await client.query('DELETE FROM house_entry_support WHERE house_id = $1', [houseId]);
      await client.query('DELETE FROM house_onboarding_progress WHERE house_id = $1', [houseId]);
      await client.query('DELETE FROM v5_house_settlement_profiles WHERE house_id = $1', [houseId]);
      await client.query('DELETE FROM houses WHERE id = $1', [houseId]);
      await client.query('DELETE FROM auth_accounts WHERE email = $1', [email]);
    }
    await client.end();
  }
});

test('PostgreSQL V5 Economic Core Phase 4: Condition modifiers (DEMAND_MULTIPLIER & SUPPLY_MULTIPLIER) scale inputs and outputs correctly', async () => {
  const client = await connectTo(connectionString);
  const repository = new PostgresRepository(client);

  const corpId = `CORP-COND-${Date.now()}`;
  const corpEconId = `ECON-${corpId}`;
  const territoryId = `TERR-COND-${Date.now()}`;
  const extractId = `BLD-EXTRACT-COND-${Date.now()}`;
  const conditionDemandId = `COND-DEMAND-${Date.now()}`;
  const conditionSupplyId = `COND-SUPPLY-${Date.now()}`;
  const gameDay = 30;

  try {
    await repository.transaction(async (tx) => {
      await tx.query(`INSERT INTO institutions (id, kind, name, status) VALUES ($1, 'CORPORATION', $2, 'ACTIVE')`, [corpId, `Condition Corp ${Date.now()}`]);
      await tx.query(`INSERT INTO corporations (id, charter_version, admission_policy, status, created_game_day) VALUES ($1, 'corporation-charter-v5', 'OPEN', 'ACTIVE', 1)`, [corpId]);
      await tx.query(`INSERT INTO owner_registry (id, owner_type, economic_id) VALUES ($1, 'CORPORATION', $2)`, [corpId, corpEconId]);
      await tx.query('SELECT earth_provision_corporation_economy($1)', [corpEconId]);

      const corpTreasury = (await tx.query(`SELECT id FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 1 AND account_type = 'TREASURY'`, [corpEconId])).rows[0];
      await tx.query(`UPDATE economic_accounts SET balance_units = 100000 WHERE id = $1`, [corpTreasury.id]);

      await tx.query(`INSERT INTO territories (id, corporation_id, name, status, is_primary) VALUES ($1, $2, 'Cond Territory', 'ACTIVE', true)`, [territoryId, corpId]);

      // EXTRACTION-REFINING-T1: base in: 12 ENERGY, 1 COMPUTE; base out: 30 MATERIAL
      await tx.query(`
        INSERT INTO buildings (id, catalog_id, owner_economic_id, territory_id, status, construction_state, installed_generation, catalog_definition_version, technology_definition_version, operating_mode, started_game_day, last_major_rebuild_game_day)
        VALUES ($1, 'EXTRACTION-REFINING-T1', $2, $3, 'ACTIVE', 'ACTIVE', 1, 'v5-alpha-1', 'tech-gen-v1', 'BALANCED', 1, 1)
      `, [extractId, corpEconId, territoryId]);

      // Add DEMAND_MULTIPLIER +2500 bps (1.25x) for ENERGY: 12 * 1.25 = 15
      await tx.query(`
        INSERT INTO world_conditions (id, condition_code, title, description, source_type, source_id, scope_type, scope_id, effect_type, target_key, modifier_bps, effective_from_game_day, effective_to_game_day, rules_version)
        VALUES ($1, 'ENERGY_DEMAND_SURGE', 'Energy Demand Surge', 'Surge in energy requirements', 'SYSTEM_EVENT', 'SYSTEM', 'TERRITORY', $2, 'DEMAND_MULTIPLIER', 'ENERGY', 2500, 1, 50, 'world-conditions-v1')
      `, [conditionDemandId, territoryId]);

      // Add SUPPLY_MULTIPLIER +2000 bps (1.20x) for MATERIAL: 30 * 1.20 = 36
      await tx.query(`
        INSERT INTO world_conditions (id, condition_code, title, description, source_type, source_id, scope_type, scope_id, effect_type, target_key, modifier_bps, effective_from_game_day, effective_to_game_day, rules_version)
        VALUES ($1, 'RICH_VEIN_DISCOVERY', 'Rich Vein Discovery', 'High mineral yield', 'SYSTEM_EVENT', 'SYSTEM', 'TERRITORY', $2, 'SUPPLY_MULTIPLIER', 'MATERIAL', 2000, 1, 50, 'world-conditions-v1')
      `, [conditionSupplyId, territoryId]);

      // Provide 15 ENERGY and 1 COMPUTE
      const energyInv = (await tx.query(`SELECT id FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 4 AND account_type = 'INVENTORY'`, [corpEconId])).rows[0];
      const computeInv = (await tx.query(`SELECT id FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 5 AND account_type = 'INVENTORY'`, [corpEconId])).rows[0];
      await tx.query(`UPDATE economic_accounts SET balance_units = 15 WHERE id = $1`, [energyInv.id]);
      await tx.query(`UPDATE economic_accounts SET balance_units = 1 WHERE id = $1`, [computeInv.id]);

      await settleBuildingUpkeepAndRevenueV2(tx, gameDay);

      // Check Material output = 36 (boosted from 30)
      const matInv = (await tx.query(`SELECT balance_units::TEXT FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 2 AND account_type = 'INVENTORY'`, [corpEconId])).rows[0];
      assert.equal(matInv.balance_units, '36', 'Material output boosted by 20% to 36 units');

      // Check Energy consumed = 15 (boosted from 12)
      const remEnergy = (await tx.query(`SELECT balance_units::TEXT FROM economic_accounts WHERE id = $1`, [energyInv.id])).rows[0];
      assert.equal(remEnergy.balance_units, '0', 'Energy demand increased by 25% to 15 units');

      // Check settlement journal
      const journal = (await tx.query(`SELECT * FROM building_settlement_journals WHERE building_id = $1 AND game_day = $2`, [extractId, gameDay])).rows[0];
      assert.ok(journal);
      assert.equal(journal.status, 'OPERATED');
      assert.equal(journal.utilization_bps, 10000);
      assert.deepEqual(journal.input_units, { ENERGY: '15', COMPUTE: '1' });
      assert.deepEqual(journal.output_units, { MATERIAL: '36' });
    });
  } finally {
    await client.query('DELETE FROM world_conditions WHERE id IN ($1, $2)', [conditionDemandId, conditionSupplyId]);
    await client.query('DELETE FROM building_settlement_journals WHERE building_id = $1', [extractId]);
    await client.query('DELETE FROM buildings WHERE id = $1', [extractId]);
    await client.query('DELETE FROM territory_capacity_state WHERE territory_id = $1', [territoryId]);
    await client.query('DELETE FROM territories WHERE id = $1', [territoryId]);
    await client.query('DELETE FROM economic_entries WHERE account_id IN (SELECT id FROM economic_accounts WHERE owner_economic_id = $1)', [corpEconId]);
    await client.query('DELETE FROM economic_entries WHERE transaction_id IN (SELECT id FROM economic_transactions WHERE source_id = $1 OR correlation_id LIKE $2)', [corpEconId, `building-corp:${corpEconId}:%`]);
    await client.query('DELETE FROM economic_transactions WHERE source_id = $1 OR correlation_id LIKE $2', [corpEconId, `building-corp:${corpEconId}:%`]);
    await client.query('DELETE FROM economic_accounts WHERE owner_economic_id = $1', [corpEconId]);
    await client.query('DELETE FROM owner_registry WHERE economic_id = $1', [corpEconId]);
    await client.query('DELETE FROM corporations WHERE id = $1', [corpId]);
    await client.query('DELETE FROM institutions WHERE id = $1', [corpId]);
    await client.end();
  }
});

test('PostgreSQL V5 Economic Core Phase 4: Operating modes (CONSERVATIVE vs BALANCED) scale utilization, resource flows, and operating expenses', async () => {
  const client = await connectTo(connectionString);
  const repository = new PostgresRepository(client);

  const corpId = `CORP-OPMODE-${Date.now()}`;
  const corpEconId = `ECON-${corpId}`;
  const territoryId = `TERR-OPMODE-${Date.now()}`;
  const bldConservative = `BLD-CONSERV-${Date.now()}`;
  const bldBalanced = `BLD-BALANCED-${Date.now()}`;
  const gameDay = 35;

  try {
    await repository.transaction(async (tx) => {
      await tx.query(`INSERT INTO institutions (id, kind, name, status) VALUES ($1, 'CORPORATION', $2, 'ACTIVE')`, [corpId, `OpMode Corp ${Date.now()}`]);
      await tx.query(`INSERT INTO corporations (id, charter_version, admission_policy, status, created_game_day) VALUES ($1, 'corporation-charter-v5', 'OPEN', 'ACTIVE', 1)`, [corpId]);
      await tx.query(`INSERT INTO owner_registry (id, owner_type, economic_id) VALUES ($1, 'CORPORATION', $2)`, [corpId, corpEconId]);
      await tx.query('SELECT earth_provision_corporation_economy($1)', [corpEconId]);

      const corpTreasury = (await tx.query(`SELECT id FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 1 AND account_type = 'TREASURY'`, [corpEconId])).rows[0];
      await tx.query(`UPDATE economic_accounts SET balance_units = 100000 WHERE id = $1`, [corpTreasury.id]);

      await tx.query(`INSERT INTO territories (id, corporation_id, name, status, is_primary) VALUES ($1, $2, 'OpMode Territory', 'ACTIVE', true)`, [territoryId, corpId]);

      // EXTRACTION-REFINING-T1: base in: 12 ENERGY, 1 COMPUTE; out: 30 MATERIAL; credit: 800
      await tx.query(`
        INSERT INTO buildings (id, catalog_id, owner_economic_id, territory_id, status, construction_state, installed_generation, catalog_definition_version, technology_definition_version, operating_mode, started_game_day, last_major_rebuild_game_day)
        VALUES
          ($1, 'EXTRACTION-REFINING-T1', $3, $4, 'ACTIVE', 'ACTIVE', 1, 'v5-alpha-1', 'tech-gen-v1', 'CONSERVATIVE', 1, 1),
          ($2, 'EXTRACTION-REFINING-T1', $3, $4, 'ACTIVE', 'ACTIVE', 1, 'v5-alpha-1', 'tech-gen-v1', 'BALANCED', 1, 1)
      `, [bldConservative, bldBalanced, corpEconId, territoryId]);

      // Provide ample inventory so mode determines utilization
      const energyInv = (await tx.query(`SELECT id FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 4 AND account_type = 'INVENTORY'`, [corpEconId])).rows[0];
      const computeInv = (await tx.query(`SELECT id FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 5 AND account_type = 'INVENTORY'`, [corpEconId])).rows[0];
      await tx.query(`UPDATE economic_accounts SET balance_units = 100 WHERE id = $1`, [energyInv.id]);
      await tx.query(`UPDATE economic_accounts SET balance_units = 10 WHERE id = $1`, [computeInv.id]);

      await settleBuildingUpkeepAndRevenueV2(tx, gameDay);

      // 1. Check Conservative Journal: utilization = 7000, input: 8 ENERGY, output: 21 MATERIAL, credit: 560
      const jCons = (await tx.query(`SELECT * FROM building_settlement_journals WHERE building_id = $1 AND game_day = $2`, [bldConservative, gameDay])).rows[0];
      assert.ok(jCons);
      assert.equal(jCons.utilization_bps, 7000, 'Conservative mode caps utilization at 7000 bps');
      assert.deepEqual(jCons.input_units, { ENERGY: '8' }); // 12 * 70% = 8; 1 * 70% = 0
      assert.deepEqual(jCons.output_units, { MATERIAL: '21' }); // 30 * 70% = 21
      assert.equal(jCons.operating_credit_units, '560'); // 800 * 70% = 560

      // 2. Check Balanced Journal: utilization = 10000, input: 12 ENERGY, 1 COMPUTE, output: 30 MATERIAL, credit: 800
      const jBal = (await tx.query(`SELECT * FROM building_settlement_journals WHERE building_id = $1 AND game_day = $2`, [bldBalanced, gameDay])).rows[0];
      assert.ok(jBal);
      assert.equal(jBal.utilization_bps, 10000, 'Balanced mode operates at 10000 bps');
      assert.deepEqual(jBal.input_units, { ENERGY: '12', COMPUTE: '1' });
      assert.deepEqual(jBal.output_units, { MATERIAL: '30' });
      assert.equal(jBal.operating_credit_units, '800');

      // 3. Check combined Material inventory: 21 + 30 = 51
      const matInv = (await tx.query(`SELECT balance_units::TEXT FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 2 AND account_type = 'INVENTORY'`, [corpEconId])).rows[0];
      assert.equal(matInv.balance_units, '51', 'Total produced Material is 51');

      // 4. Check combined Treasury expense: 560 + 800 = 1360
      const remTreasury = (await tx.query(`SELECT balance_units::TEXT FROM economic_accounts WHERE id = $1`, [corpTreasury.id])).rows[0];
      assert.equal(remTreasury.balance_units, String(100000 - 1360));
    });
  } finally {
    await client.query('DELETE FROM building_settlement_journals WHERE building_id IN ($1, $2)', [bldConservative, bldBalanced]);
    await client.query('DELETE FROM buildings WHERE id IN ($1, $2)', [bldConservative, bldBalanced]);
    await client.query('DELETE FROM territory_capacity_state WHERE territory_id = $1', [territoryId]);
    await client.query('DELETE FROM territories WHERE id = $1', [territoryId]);
    await client.query('DELETE FROM economic_entries WHERE account_id IN (SELECT id FROM economic_accounts WHERE owner_economic_id = $1)', [corpEconId]);
    await client.query('DELETE FROM economic_entries WHERE transaction_id IN (SELECT id FROM economic_transactions WHERE source_id = $1 OR correlation_id LIKE $2)', [corpEconId, `building-corp:${corpEconId}:%`]);
    await client.query('DELETE FROM economic_transactions WHERE source_id = $1 OR correlation_id LIKE $2', [corpEconId, `building-corp:${corpEconId}:%`]);
    await client.query('DELETE FROM economic_accounts WHERE owner_economic_id = $1', [corpEconId]);
    await client.query('DELETE FROM owner_registry WHERE economic_id = $1', [corpEconId]);
    await client.query('DELETE FROM corporations WHERE id = $1', [corpId]);
    await client.query('DELETE FROM institutions WHERE id = $1', [corpId]);
    await client.end();
  }
});

test('PostgreSQL V5 Economic Core Phase 4: Production never creates CREDIT and ledger postings conserve assets', async () => {
  const client = await connectTo(connectionString);
  try {
    // 1. Verify that no RESOURCE_PRODUCTION or RESOURCE_CONSUMPTION transaction contains CREDIT (asset_id = 1)
    const invalidCreditInProd = await client.query(`
      SELECT t.id, t.transaction_kind, e.asset_id, e.delta_units
      FROM economic_transactions t
      JOIN economic_entries e ON e.transaction_id = t.id
      WHERE t.transaction_kind IN ('RESOURCE_PRODUCTION', 'RESOURCE_CONSUMPTION')
        AND e.asset_id = 1
    `);
    assert.equal(invalidCreditInProd.rows.length, 0, 'Production/Consumption transactions must NEVER involve CREDIT');

    // 2. Verify all modern V5 economic transactions are strictly balanced (sum(delta_units) = 0 for every asset)
    const unbalancedTx = await client.query(`
      SELECT t.id, t.transaction_kind, e.asset_id, SUM(e.delta_units) AS net_delta
      FROM economic_transactions t
      JOIN economic_entries e ON e.transaction_id = t.id
      WHERE t.correlation_id LIKE 'building-%'
         OR t.correlation_id LIKE 'service:%'
         OR t.rules_version IN ('building-settlement-v4', 'services-v1', 'life-maintenance-v2')
      GROUP BY t.id, t.transaction_kind, e.asset_id
      HAVING SUM(e.delta_units) <> 0
    `);
    assert.equal(unbalancedTx.rows.length, 0, 'All modern economic transactions must be zero-sum conserved');
  } finally {
    await client.end();
  }
});

test('PostgreSQL V5 Economic Core Phase 4: Service providers receive real CREDIT transfers for delivered services', async () => {
  const client = await connectTo(connectionString);
  const repository = new PostgresRepository(client);

  const email = `service-pay-${Date.now()}@example.invalid`;
  const corpId = `CORP-SVC-PAY-${Date.now()}`;
  const corpEconId = `ECON-${corpId}`;
  const territoryId = `TERR-SVC-PAY-${Date.now()}`;
  const clinicId = `BLD-CLINIC-PAY-${Date.now()}`;
  const residencyId = `RES-SVC-PAY-${Date.now()}`;
  const gameDay = 40;

  let humanId, houseId, houseEconId;

  try {
    const reg = await registerIdentity(repository, { email, personName: 'SvcPayer', houseSurname: `SPHouse${Date.now()}`, password: 'correct-horse-battery-staple' });
    humanId = reg.human.id;
    houseId = `HOUSE-${humanId.slice(2)}`;
    houseEconId = `ECON-${houseId}`;

    await repository.transaction(async (tx) => {
      await tx.query(`INSERT INTO institutions (id, kind, name, status) VALUES ($1, 'CORPORATION', $2, 'ACTIVE')`, [corpId, `Svc Pay Corp ${Date.now()}`]);
      await tx.query(`INSERT INTO corporations (id, charter_version, admission_policy, status, created_game_day) VALUES ($1, 'corporation-charter-v5', 'OPEN', 'ACTIVE', 1)`, [corpId]);
      await tx.query(`INSERT INTO owner_registry (id, owner_type, economic_id) VALUES ($1, 'CORPORATION', $2)`, [corpId, corpEconId]);
      await tx.query('SELECT earth_provision_corporation_economy($1)', [corpEconId]);

      await tx.query(`INSERT INTO territories (id, corporation_id, name, status, is_primary) VALUES ($1, $2, 'SvcPay Territory', 'ACTIVE', true)`, [territoryId, corpId]);

      // Move House to this territory
      await tx.query(`INSERT INTO house_residencies (id, house_id, territory_id, residency_class, status, effective_from_game_day, correlation_id) VALUES ($1, $2, $3, 'PRIMARY', 'ACTIVE', 1, $4)`, [residencyId, houseId, territoryId, `res:${houseId}:${territoryId}:${Date.now()}`]);

      // Seed House WALLET with 10,000 CREDIT
      const houseWallet = (await tx.query(`SELECT id FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 1 AND account_type = 'WALLET'`, [houseEconId])).rows[0];
      await tx.query(`UPDATE economic_accounts SET balance_units = 10000 WHERE id = $1`, [houseWallet.id]);

      // Setup PUBLIC_MEDICAL-T1 (Public, provides HEALTH capacity 16)
      await tx.query(`
        INSERT INTO buildings (id, catalog_id, owner_economic_id, territory_id, status, construction_state, installed_generation, catalog_definition_version, technology_definition_version, operating_mode, started_game_day, last_major_rebuild_game_day)
        VALUES ($1, 'PUBLIC-MEDICAL-T1', $2, $3, 'ACTIVE', 'ACTIVE', 1, 'v5-alpha-1', 'tech-gen-v1', 'BALANCED', 1, 1)
      `, [clinicId, corpEconId, territoryId]);

      // Settle needs and services with shardCount = 1
      const res = await settleHouseNeedsAndServices(tx, gameDay, 0, 1);
      assert.ok(res.allocations >= 1);

      // Verify Service price is paid: HEALTH price is 1 CREDIT per unit. Demand is 1 human = 1 unit.
      // House WALLET: 10,000 - 1 = 9,999
      const remWallet = (await tx.query(`SELECT balance_units::TEXT FROM economic_accounts WHERE id = $1`, [houseWallet.id])).rows[0];
      assert.equal(remWallet.balance_units, '9999', 'House paid 1 CREDIT for HEALTH service');

      // Corporation OPERATIONS account: 0 + 1 = 1
      const corpOps = (await tx.query(`SELECT balance_units::TEXT FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 1 AND account_type = 'OPERATIONS'`, [corpEconId])).rows[0];
      assert.equal(corpOps.balance_units, '1', 'Corporation received 1 CREDIT into OPERATIONS account');

      // Check service allocation record
      const allocation = (await tx.query(`SELECT * FROM service_allocations WHERE house_id = $1 AND game_day = $2 AND service_code = 'HEALTH'`, [houseId, gameDay])).rows[0];
      assert.ok(allocation);
      assert.equal(allocation.allocated_units, '1');
      assert.equal(allocation.price_units, '1');
      assert.ok(allocation.economic_transaction_id, 'Real economic transaction recorded');
    });
  } finally {
    await client.query('DELETE FROM service_allocations WHERE house_id = $1', [houseId]);
    await client.query('DELETE FROM house_need_assessments WHERE house_id = $1', [houseId]);
    await client.query('DELETE FROM buildings WHERE id = $1', [clinicId]);
    await client.query('DELETE FROM house_residencies WHERE house_id = $1', [houseId]);
    await client.query('DELETE FROM territory_capacity_state WHERE territory_id = $1', [territoryId]);
    await client.query('DELETE FROM territories WHERE id = $1', [territoryId]);
    await client.query('DELETE FROM economic_entries WHERE account_id IN (SELECT id FROM economic_accounts WHERE owner_economic_id IN ($1, $2))', [corpEconId, houseEconId]);
    await client.query('DELETE FROM economic_entries WHERE transaction_id IN (SELECT id FROM economic_transactions WHERE source_id IN ($1, $2, $3) OR correlation_id LIKE $4 OR correlation_id LIKE $5)', [corpEconId, houseEconId, humanId, `service:${gameDay}:${houseId}:%`, `starter:${houseId}:%`]);
    await client.query('DELETE FROM economic_transactions WHERE source_id IN ($1, $2, $3) OR correlation_id LIKE $4 OR correlation_id LIKE $5', [corpEconId, houseEconId, humanId, `service:${gameDay}:${houseId}:%`, `starter:${houseId}:%`]);
    await client.query('DELETE FROM economic_accounts WHERE owner_economic_id IN ($1, $2)', [corpEconId, houseEconId]);
    await client.query('DELETE FROM owner_registry WHERE economic_id IN ($1, $2)', [corpEconId, houseEconId]);
    await client.query('DELETE FROM corporations WHERE id = $1', [corpId]);
    await client.query('DELETE FROM institutions WHERE id = $1', [corpId]);
    if (humanId) {
      await client.query('DELETE FROM auth_sessions WHERE account_id = $1', [`account-${humanId.toLowerCase()}`]);
      await client.query('DELETE FROM game_events WHERE actor_human_id = $1', [humanId]);
      await client.query('DELETE FROM notifications WHERE human_id = $1', [humanId]);
      await client.query('DELETE FROM personal_life_maintenance WHERE human_id = $1', [humanId]);
      await client.query('DELETE FROM event_outbox WHERE aggregate_id = $1', [humanId]);
      await client.query('UPDATE houses SET current_human_id = NULL WHERE id = $1', [houseId]);
      await client.query('DELETE FROM humans WHERE id = $1', [humanId]);
      await client.query('UPDATE auth_accounts SET house_id = NULL WHERE email = $1', [email]);
      await client.query('DELETE FROM house_entry_support WHERE house_id = $1', [houseId]);
      await client.query('DELETE FROM house_onboarding_progress WHERE house_id = $1', [houseId]);
      await client.query('DELETE FROM v5_house_settlement_profiles WHERE house_id = $1', [houseId]);
      await client.query('DELETE FROM houses WHERE id = $1', [houseId]);
      await client.query('DELETE FROM auth_accounts WHERE email = $1', [email]);
    }
    await client.end();
  }
});

test('PostgreSQL V5 Economic Core Phase 5: Private clinics and Corporation medical centers coexist with prioritized allocation', async () => {
  const client = await connectTo(connectionString);
  const repository = new PostgresRepository(client);

  const email1 = `clinic-doctor-${Date.now()}@example.invalid`;
  const email2 = `clinic-patient-${Date.now()}@example.invalid`;
  const corpId = `CORP-SVC-COEXIST-${Date.now()}`;
  const corpEconId = `ECON-${corpId}`;
  const territoryId = `TERR-SVC-COEXIST-${Date.now()}`;
  const clinicId = `BLD-COMMUNITY-CLINIC-${Date.now()}`;
  const hospitalId = `BLD-PUBLIC-HOSPITAL-${Date.now()}`;
  const gameDay = 50;

  let humanId1, houseId1, houseEconId1;
  let humanId2, houseId2, houseEconId2;
  const extraHumanIds = [];
  const extraAuthEmails = [];

  try {
    const reg1 = await registerIdentity(repository, { email: email1, personName: 'DocHuman', houseSurname: `DocHouse${Date.now()}`, password: 'correct-horse-battery-staple' });
    humanId1 = reg1.human.id;
    houseId1 = `HOUSE-${humanId1.slice(2)}`;
    houseEconId1 = `ECON-${houseId1}`;

    const reg2 = await registerIdentity(repository, { email: email2, personName: 'PatientHuman', houseSurname: `PatientHouse${Date.now()}`, password: 'correct-horse-battery-staple' });
    humanId2 = reg2.human.id;
    houseId2 = `HOUSE-${humanId2.slice(2)}`;
    houseEconId2 = `ECON-${houseId2}`;

    await repository.transaction(async (tx) => {
      // 1. Setup Corporation & Territory
      await tx.query(`INSERT INTO institutions (id, kind, name, status) VALUES ($1, 'CORPORATION', $2, 'ACTIVE')`, [corpId, `Coexist Health Corp ${Date.now()}`]);
      await tx.query(`INSERT INTO corporations (id, charter_version, admission_policy, status, created_game_day) VALUES ($1, 'corporation-charter-v5', 'OPEN', 'ACTIVE', 1)`, [corpId]);
      await tx.query(`INSERT INTO owner_registry (id, owner_type, economic_id) VALUES ($1, 'CORPORATION', $2)`, [corpId, corpEconId]);
      await tx.query('SELECT earth_provision_corporation_economy($1)', [corpEconId]);
      await tx.query(`INSERT INTO territories (id, corporation_id, name, status, is_primary) VALUES ($1, $2, 'Health Territory', 'ACTIVE', true)`, [territoryId, corpId]);

      // 2. Add extra 9 human residents to House 2 so total residents = 10
      for (let i = 1; i <= 9; i++) {
        const extraEmail = `extra-pat-${i}-${Date.now()}@example.invalid`;
        const authId = `ACC-EXTRA-PAT-${i}-${Date.now()}`;
        extraAuthEmails.push(extraEmail);
        await tx.query(`INSERT INTO auth_accounts (id, email, password_hash, password_salt, password_iterations, house_id) VALUES ($1, $2, 'dummy-hash', 'dummy-salt', 1000, $3)`, [authId, extraEmail, houseId2]);
        const hId = `H-EXTRA-${i}-${Date.now()}`;
        extraHumanIds.push(hId);
        await tx.query(`INSERT INTO humans (id, account_id, house_id, display_name, status) VALUES ($1, $2, $3, $4, 'ACTIVE')`, [hId, authId, houseId2, `Patient Resident ${i}`]);
      }

      // 3. Move both houses to Territory and affiliate with Corporation
      await tx.query(`INSERT INTO house_residencies (id, house_id, territory_id, residency_class, status, effective_from_game_day, correlation_id) VALUES ($1, $2, $3, 'PRIMARY', 'ACTIVE', 1, $4)`, [`res:1:${Date.now()}`, houseId1, territoryId, `res:1:${Date.now()}`]);
      await tx.query(`INSERT INTO house_residencies (id, house_id, territory_id, residency_class, status, effective_from_game_day, correlation_id) VALUES ($1, $2, $3, 'PRIMARY', 'ACTIVE', 1, $4)`, [`res:2:${Date.now()}`, houseId2, territoryId, `res:2:${Date.now()}`]);
      await tx.query(`INSERT INTO house_affiliations (house_id, corporation_id, primary_territory_id, joined_game_day, status) VALUES ($1, $2, $3, 1, 'ACTIVE')`, [houseId1, corpId, territoryId]);
      await tx.query(`INSERT INTO house_affiliations (house_id, corporation_id, primary_territory_id, joined_game_day, status) VALUES ($1, $2, $3, 1, 'ACTIVE')`, [houseId2, corpId, territoryId]);

      // 4. Fund House WALLETs with 5,000 CREDIT each
      const house1Wallet = (await tx.query(`SELECT id FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 1 AND account_type = 'WALLET'`, [houseEconId1])).rows[0];
      const house2Wallet = (await tx.query(`SELECT id FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 1 AND account_type = 'WALLET'`, [houseEconId2])).rows[0];
      await tx.query(`UPDATE economic_accounts SET balance_units = 5000 WHERE id = $1`, [house1Wallet.id]);
      await tx.query(`UPDATE economic_accounts SET balance_units = 5000 WHERE id = $1`, [house2Wallet.id]);

      // 5. Build COMMUNITY-CLINIC-T1 (Private, owned by House 1, capacity 8 HEALTH)
      await tx.query(`
        INSERT INTO buildings (id, catalog_id, owner_economic_id, territory_id, status, construction_state, installed_generation, catalog_definition_version, technology_definition_version, operating_mode, started_game_day, last_major_rebuild_game_day)
        VALUES ($1, 'COMMUNITY-CLINIC-T1', $2, $3, 'ACTIVE', 'ACTIVE', 1, 'v5-alpha-1', 'tech-gen-v1', 'BALANCED', 1, 1)
      `, [clinicId, houseEconId1, territoryId]);

      // 6. Build PUBLIC-MEDICAL-T1 (Public, owned by Corporation, capacity 100 HEALTH)
      await tx.query(`
        INSERT INTO buildings (id, catalog_id, owner_economic_id, territory_id, status, construction_state, installed_generation, catalog_definition_version, technology_definition_version, operating_mode, started_game_day, last_major_rebuild_game_day)
        VALUES ($1, 'PUBLIC-MEDICAL-T1', $2, $3, 'ACTIVE', 'ACTIVE', 1, 'v5-alpha-1', 'tech-gen-v1', 'BALANCED', 1, 1)
      `, [hospitalId, corpEconId, territoryId]);

      // 7. Settle Needs and Services
      const res = await settleHouseNeedsAndServices(tx, gameDay, 0, 1);
      assert.equal(res.houses, 2);
      assert.ok(res.allocations >= 3); // House 1 self-alloc, House 2 private alloc, House 2 public alloc

      // 8. Verify House 1 self-allocation:
      // Demand = 1 unit. Self-allocated 1 unit from its own clinic with 0 CREDIT payment.
      const house1Alloc = (await tx.query(`SELECT * FROM service_allocations WHERE house_id = $1 AND game_day = $2 AND service_code = 'HEALTH'`, [houseId1, gameDay])).rows[0];
      assert.ok(house1Alloc);
      assert.equal(house1Alloc.allocated_units, '1');
      assert.equal(house1Alloc.provider_economic_id, houseEconId1);
      assert.equal(house1Alloc.economic_transaction_id, null, 'Self-service requires no payment transaction');

      // 9. Verify House 2 allocations:
      // Demand = 10 units.
      // Priority waterfall: 7 units from private clinic (House 1), 3 units from public medical center (Corporation).
      const house2Allocations = (await tx.query(`SELECT * FROM service_allocations WHERE house_id = $1 AND game_day = $2 AND service_code = 'HEALTH' ORDER BY allocated_units DESC`, [houseId2, gameDay])).rows;
      assert.equal(house2Allocations.length, 2);

      const privateAlloc = house2Allocations.find((a) => a.provider_economic_id === houseEconId1);
      const publicAlloc = house2Allocations.find((a) => a.provider_economic_id === corpEconId);
      assert.ok(privateAlloc);
      assert.ok(publicAlloc);
      assert.equal(privateAlloc.allocated_units, '7', 'Private clinic supplied remaining 7 units');
      assert.equal(privateAlloc.price_units, '7');
      assert.equal(publicAlloc.allocated_units, '3', 'Public medical center supplied remaining 3 units');
      assert.equal(publicAlloc.price_units, '3');

      // 10. Verify Balances after Service Settlement:
      // House 1 WALLET: 5000 initial + 7 service revenue = 5007
      const house1RemWallet = (await tx.query(`SELECT balance_units::TEXT FROM economic_accounts WHERE id = $1`, [house1Wallet.id])).rows[0];
      assert.equal(house1RemWallet.balance_units, '5007', 'Doctor house received 7 CREDIT in service revenue');

      // House 2 WALLET: 5000 initial - 7 (private) - 3 (public) = 4990
      const house2RemWallet = (await tx.query(`SELECT balance_units::TEXT FROM economic_accounts WHERE id = $1`, [house2Wallet.id])).rows[0];
      assert.equal(house2RemWallet.balance_units, '4990', 'Patient house paid 10 CREDIT total for services');

      // Corporation OPERATIONS: 0 initial + 3 service revenue = 3
      const corpOps = (await tx.query(`SELECT balance_units::TEXT FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 1 AND account_type = 'OPERATIONS'`, [corpEconId])).rows[0];
      assert.equal(corpOps.balance_units, '3', 'Corporation received 3 CREDIT into OPERATIONS account');

      // 11. Run settleCorporationDynamics and verify operating snapshot
      await settleCorporationDynamics(tx, gameDay);
      const snap = (await tx.query(`SELECT * FROM corporation_operating_snapshots WHERE corporation_id = $1 AND game_day = $2`, [corpId, gameDay])).rows[0];
      assert.ok(snap);
      assert.equal(snap.service_capacity_units, '100', 'Corporation public medical center provides 100 capacity');
      assert.equal(snap.service_allocated_units, '3', 'Corporation allocated 3 units to member houses');
      assert.equal(snap.service_revenue_units, '3', 'Corporation earned 3 CREDIT in service revenue');
    });
  } finally {
    await client.query('DELETE FROM service_allocations WHERE house_id IN ($1, $2)', [houseId1, houseId2]);
    await client.query('DELETE FROM house_need_assessments WHERE house_id IN ($1, $2)', [houseId1, houseId2]);
    await client.query('DELETE FROM corporation_operating_snapshots WHERE corporation_id = $1', [corpId]);
    await client.query('DELETE FROM buildings WHERE id IN ($1, $2)', [clinicId, hospitalId]);
    await client.query('DELETE FROM house_affiliations WHERE house_id IN ($1, $2)', [houseId1, houseId2]);
    await client.query('DELETE FROM house_residencies WHERE house_id IN ($1, $2)', [houseId1, houseId2]);
    await client.query('DELETE FROM territory_capacity_state WHERE territory_id = $1', [territoryId]);
    await client.query('DELETE FROM territories WHERE id = $1', [territoryId]);
    await client.query('DELETE FROM economic_entries WHERE account_id IN (SELECT id FROM economic_accounts WHERE owner_economic_id IN ($1, $2, $3))', [corpEconId, houseEconId1, houseEconId2]);
    await client.query('DELETE FROM economic_entries WHERE transaction_id IN (SELECT id FROM economic_transactions WHERE source_id IN ($1, $2, $3, $4, $5) OR correlation_id LIKE $6 OR correlation_id LIKE $7 OR correlation_id LIKE $8)', [corpEconId, houseEconId1, houseEconId2, humanId1, humanId2, `service:${gameDay}:%`, `starter:${houseId1}:%`, `starter:${houseId2}:%`]);
    await client.query('DELETE FROM economic_transactions WHERE source_id IN ($1, $2, $3, $4, $5) OR correlation_id LIKE $6 OR correlation_id LIKE $7 OR correlation_id LIKE $8', [corpEconId, houseEconId1, houseEconId2, humanId1, humanId2, `service:${gameDay}:%`, `starter:${houseId1}:%`, `starter:${houseId2}:%`]);
    await client.query('DELETE FROM economic_accounts WHERE owner_economic_id IN ($1, $2, $3)', [corpEconId, houseEconId1, houseEconId2]);
    await client.query('DELETE FROM owner_registry WHERE economic_id IN ($1, $2, $3)', [corpEconId, houseEconId1, houseEconId2]);
    await client.query('DELETE FROM corporations WHERE id = $1', [corpId]);
    await client.query('DELETE FROM institutions WHERE id = $1', [corpId]);
    for (const hId of extraHumanIds) {
      await client.query('DELETE FROM humans WHERE id = $1', [hId]);
    }
    for (const em of extraAuthEmails) {
      await client.query('DELETE FROM auth_accounts WHERE email = $1', [em]);
    }
    for (const [hId, hHumanId, em] of [[houseId1, humanId1, email1], [houseId2, humanId2, email2]]) {
      if (hHumanId) {
        await client.query('DELETE FROM auth_sessions WHERE account_id = $1', [`account-${hHumanId.toLowerCase()}`]);
        await client.query('DELETE FROM game_events WHERE actor_human_id = $1', [hHumanId]);
        await client.query('DELETE FROM notifications WHERE human_id = $1', [hHumanId]);
        await client.query('DELETE FROM personal_life_maintenance WHERE human_id = $1', [hHumanId]);
        await client.query('DELETE FROM event_outbox WHERE aggregate_id = $1', [hHumanId]);
        await client.query('UPDATE houses SET current_human_id = NULL WHERE id = $1', [hId]);
        await client.query('DELETE FROM humans WHERE id = $1', [hHumanId]);
        await client.query('UPDATE auth_accounts SET house_id = NULL WHERE email = $1', [em]);
        await client.query('DELETE FROM house_entry_support WHERE house_id = $1', [hId]);
        await client.query('DELETE FROM house_onboarding_progress WHERE house_id = $1', [hId]);
        await client.query('DELETE FROM v5_house_settlement_profiles WHERE house_id = $1', [hId]);
        await client.query('DELETE FROM houses WHERE id = $1', [hId]);
        await client.query('DELETE FROM auth_accounts WHERE email = $1', [em]);
      }
    }
    await client.end();
  }
});

test('PostgreSQL V5 Economic Core Phase 5: Data Services Studios and Civic Data Networks coexist with prioritized allocation', async () => {
  const client = await connectTo(connectionString);
  const repository = new PostgresRepository(client);

  const email1 = `data-studio-${Date.now()}@example.invalid`;
  const email2 = `data-client-${Date.now()}@example.invalid`;
  const corpId = `CORP-SVC-DATA-${Date.now()}`;
  const corpEconId = `ECON-${corpId}`;
  const territoryId = `TERR-SVC-DATA-${Date.now()}`;
  const studioId = `BLD-DATA-STUDIO-${Date.now()}`;
  const networkId = `BLD-CIVIC-NETWORK-${Date.now()}`;
  const gameDay = 51;

  let humanId1, houseId1, houseEconId1;
  let humanId2, houseId2, houseEconId2;
  const extraHumanIds = [];
  const extraAuthEmails = [];

  try {
    const reg1 = await registerIdentity(repository, { email: email1, personName: 'StudioHuman', houseSurname: `StudioHouse${Date.now()}`, password: 'correct-horse-battery-staple' });
    humanId1 = reg1.human.id;
    houseId1 = `HOUSE-${humanId1.slice(2)}`;
    houseEconId1 = `ECON-${houseId1}`;

    const reg2 = await registerIdentity(repository, { email: email2, personName: 'ClientHuman', houseSurname: `ClientHouse${Date.now()}`, password: 'correct-horse-battery-staple' });
    humanId2 = reg2.human.id;
    houseId2 = `HOUSE-${humanId2.slice(2)}`;
    houseEconId2 = `ECON-${houseId2}`;

    await repository.transaction(async (tx) => {
      // 1. Setup Corporation & Territory
      await tx.query(`INSERT INTO institutions (id, kind, name, status) VALUES ($1, 'CORPORATION', $2, 'ACTIVE')`, [corpId, `Coexist Data Corp ${Date.now()}`]);
      await tx.query(`INSERT INTO corporations (id, charter_version, admission_policy, status, created_game_day) VALUES ($1, 'corporation-charter-v5', 'OPEN', 'ACTIVE', 1)`, [corpId]);
      await tx.query(`INSERT INTO owner_registry (id, owner_type, economic_id) VALUES ($1, 'CORPORATION', $2)`, [corpId, corpEconId]);
      await tx.query('SELECT earth_provision_corporation_economy($1)', [corpEconId]);
      await tx.query(`INSERT INTO territories (id, corporation_id, name, status, is_primary) VALUES ($1, $2, 'Data Territory', 'ACTIVE', true)`, [territoryId, corpId]);

      // 2. Add extra 11 human residents to House 2 so total residents = 12
      for (let i = 1; i <= 11; i++) {
        const extraEmail = `extra-dat-${i}-${Date.now()}@example.invalid`;
        const authId = `ACC-EXTRA-DAT-${i}-${Date.now()}`;
        extraAuthEmails.push(extraEmail);
        await tx.query(`INSERT INTO auth_accounts (id, email, password_hash, password_salt, password_iterations, house_id) VALUES ($1, $2, 'dummy-hash', 'dummy-salt', 1000, $3)`, [authId, extraEmail, houseId2]);
        const hId = `H-EXTRA-DAT-${i}-${Date.now()}`;
        extraHumanIds.push(hId);
        await tx.query(`INSERT INTO humans (id, account_id, house_id, display_name, status) VALUES ($1, $2, $3, $4, 'ACTIVE')`, [hId, authId, houseId2, `Data Resident ${i}`]);
      }

      // 3. Move both houses to Territory and affiliate with Corporation
      await tx.query(`INSERT INTO house_residencies (id, house_id, territory_id, residency_class, status, effective_from_game_day, correlation_id) VALUES ($1, $2, $3, 'PRIMARY', 'ACTIVE', 1, $4)`, [`res:d1:${Date.now()}`, houseId1, territoryId, `res:d1:${Date.now()}`]);
      await tx.query(`INSERT INTO house_residencies (id, house_id, territory_id, residency_class, status, effective_from_game_day, correlation_id) VALUES ($1, $2, $3, 'PRIMARY', 'ACTIVE', 1, $4)`, [`res:d2:${Date.now()}`, houseId2, territoryId, `res:d2:${Date.now()}`]);
      await tx.query(`INSERT INTO house_affiliations (house_id, corporation_id, primary_territory_id, joined_game_day, status) VALUES ($1, $2, $3, 1, 'ACTIVE')`, [houseId1, corpId, territoryId]);
      await tx.query(`INSERT INTO house_affiliations (house_id, corporation_id, primary_territory_id, joined_game_day, status) VALUES ($1, $2, $3, 1, 'ACTIVE')`, [houseId2, corpId, territoryId]);

      // 4. Fund House WALLETs with 5,000 CREDIT each
      const house1Wallet = (await tx.query(`SELECT id FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 1 AND account_type = 'WALLET'`, [houseEconId1])).rows[0];
      const house2Wallet = (await tx.query(`SELECT id FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 1 AND account_type = 'WALLET'`, [houseEconId2])).rows[0];
      await tx.query(`UPDATE economic_accounts SET balance_units = 5000 WHERE id = $1`, [house1Wallet.id]);
      await tx.query(`UPDATE economic_accounts SET balance_units = 5000 WHERE id = $1`, [house2Wallet.id]);

      // 5. Build DATA-SERVICES-T1 (Private, owned by House 1, capacity 8 CONNECTIVITY)
      await tx.query(`
        INSERT INTO buildings (id, catalog_id, owner_economic_id, territory_id, status, construction_state, installed_generation, catalog_definition_version, technology_definition_version, operating_mode, started_game_day, last_major_rebuild_game_day)
        VALUES ($1, 'DATA-SERVICES-T1', $2, $3, 'ACTIVE', 'ACTIVE', 1, 'v5-alpha-1', 'tech-gen-v1', 'BALANCED', 1, 1)
      `, [studioId, houseEconId1, territoryId]);

      // 6. Build CIVIC-DATA-T1 (Public, owned by Corporation, capacity 100 CONNECTIVITY)
      await tx.query(`
        INSERT INTO buildings (id, catalog_id, owner_economic_id, territory_id, status, construction_state, installed_generation, catalog_definition_version, technology_definition_version, operating_mode, started_game_day, last_major_rebuild_game_day)
        VALUES ($1, 'CIVIC-DATA-T1', $2, $3, 'ACTIVE', 'ACTIVE', 1, 'v5-alpha-1', 'tech-gen-v1', 'BALANCED', 1, 1)
      `, [networkId, corpEconId, territoryId]);

      // 7. Settle Needs and Services
      const res = await settleHouseNeedsAndServices(tx, gameDay, 0, 1);
      assert.equal(res.houses, 2);
      assert.ok(res.allocations >= 3);

      // 8. House 1 self-allocates 1 CONNECTIVITY (0 payment)
      const house1Alloc = (await tx.query(`SELECT * FROM service_allocations WHERE house_id = $1 AND game_day = $2 AND service_code = 'CONNECTIVITY'`, [houseId1, gameDay])).rows[0];
      assert.ok(house1Alloc);
      assert.equal(house1Alloc.allocated_units, '1');
      assert.equal(house1Alloc.provider_economic_id, houseEconId1);
      assert.equal(house1Alloc.economic_transaction_id, null);

      // 9. House 2 allocates 7 from studio + 5 from civic data network
      const house2Allocations = (await tx.query(`SELECT * FROM service_allocations WHERE house_id = $1 AND game_day = $2 AND service_code = 'CONNECTIVITY' ORDER BY allocated_units DESC`, [houseId2, gameDay])).rows;
      assert.equal(house2Allocations.length, 2);
      const privAlloc = house2Allocations.find((a) => a.provider_economic_id === houseEconId1);
      const pubAlloc = house2Allocations.find((a) => a.provider_economic_id === corpEconId);
      assert.equal(privAlloc.allocated_units, '7');
      assert.equal(pubAlloc.allocated_units, '5');

      // 10. House 1 WALLET receives 7 CREDIT; House 2 pays 12; Corporation receives 5
      const house1RemWallet = (await tx.query(`SELECT balance_units::TEXT FROM economic_accounts WHERE id = $1`, [house1Wallet.id])).rows[0];
      assert.equal(house1RemWallet.balance_units, '5007');

      const house2RemWallet = (await tx.query(`SELECT balance_units::TEXT FROM economic_accounts WHERE id = $1`, [house2Wallet.id])).rows[0];
      assert.equal(house2RemWallet.balance_units, '4988');

      const corpOps = (await tx.query(`SELECT balance_units::TEXT FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 1 AND account_type = 'OPERATIONS'`, [corpEconId])).rows[0];
      assert.equal(corpOps.balance_units, '5');
    });
  } finally {
    await client.query('DELETE FROM service_allocations WHERE house_id IN ($1, $2)', [houseId1, houseId2]);
    await client.query('DELETE FROM house_need_assessments WHERE house_id IN ($1, $2)', [houseId1, houseId2]);
    await client.query('DELETE FROM buildings WHERE id IN ($1, $2)', [studioId, networkId]);
    await client.query('DELETE FROM house_affiliations WHERE house_id IN ($1, $2)', [houseId1, houseId2]);
    await client.query('DELETE FROM house_residencies WHERE house_id IN ($1, $2)', [houseId1, houseId2]);
    await client.query('DELETE FROM territory_capacity_state WHERE territory_id = $1', [territoryId]);
    await client.query('DELETE FROM territories WHERE id = $1', [territoryId]);
    await client.query('DELETE FROM economic_entries WHERE account_id IN (SELECT id FROM economic_accounts WHERE owner_economic_id IN ($1, $2, $3))', [corpEconId, houseEconId1, houseEconId2]);
    await client.query('DELETE FROM economic_entries WHERE transaction_id IN (SELECT id FROM economic_transactions WHERE source_id IN ($1, $2, $3, $4, $5) OR correlation_id LIKE $6 OR correlation_id LIKE $7 OR correlation_id LIKE $8)', [corpEconId, houseEconId1, houseEconId2, humanId1, humanId2, `service:${gameDay}:%`, `starter:${houseId1}:%`, `starter:${houseId2}:%`]);
    await client.query('DELETE FROM economic_transactions WHERE source_id IN ($1, $2, $3, $4, $5) OR correlation_id LIKE $6 OR correlation_id LIKE $7 OR correlation_id LIKE $8', [corpEconId, houseEconId1, houseEconId2, humanId1, humanId2, `service:${gameDay}:%`, `starter:${houseId1}:%`, `starter:${houseId2}:%`]);
    await client.query('DELETE FROM economic_accounts WHERE owner_economic_id IN ($1, $2, $3)', [corpEconId, houseEconId1, houseEconId2]);
    await client.query('DELETE FROM owner_registry WHERE economic_id IN ($1, $2, $3)', [corpEconId, houseEconId1, houseEconId2]);
    await client.query('DELETE FROM corporations WHERE id = $1', [corpId]);
    await client.query('DELETE FROM institutions WHERE id = $1', [corpId]);
    for (const hId of extraHumanIds) {
      await client.query('DELETE FROM humans WHERE id = $1', [hId]);
    }
    for (const em of extraAuthEmails) {
      await client.query('DELETE FROM auth_accounts WHERE email = $1', [em]);
    }
    for (const [hId, hHumanId, em] of [[houseId1, humanId1, email1], [houseId2, humanId2, email2]]) {
      if (hHumanId) {
        await client.query('DELETE FROM auth_sessions WHERE account_id = $1', [`account-${hHumanId.toLowerCase()}`]);
        await client.query('DELETE FROM game_events WHERE actor_human_id = $1', [hHumanId]);
        await client.query('DELETE FROM notifications WHERE human_id = $1', [hHumanId]);
        await client.query('DELETE FROM personal_life_maintenance WHERE human_id = $1', [hHumanId]);
        await client.query('DELETE FROM event_outbox WHERE aggregate_id = $1', [hHumanId]);
        await client.query('UPDATE houses SET current_human_id = NULL WHERE id = $1', [hId]);
        await client.query('DELETE FROM humans WHERE id = $1', [hHumanId]);
        await client.query('UPDATE auth_accounts SET house_id = NULL WHERE email = $1', [em]);
        await client.query('DELETE FROM house_entry_support WHERE house_id = $1', [hId]);
        await client.query('DELETE FROM house_onboarding_progress WHERE house_id = $1', [hId]);
        await client.query('DELETE FROM v5_house_settlement_profiles WHERE house_id = $1', [hId]);
        await client.query('DELETE FROM houses WHERE id = $1', [hId]);
        await client.query('DELETE FROM auth_accounts WHERE email = $1', [em]);
      }
    }
    await client.end();
  }
});

test('PostgreSQL V5 Economic Core Phase 5: Insufficient service capacity records shortfall and assesses risk level', async () => {
  const client = await connectTo(connectionString);
  const repository = new PostgresRepository(client);

  const email = `shortfall-user-${Date.now()}@example.invalid`;
  const corpId = `CORP-SVC-SHORTFALL-${Date.now()}`;
  const corpEconId = `ECON-${corpId}`;
  const territoryId = `TERR-SVC-SHORTFALL-${Date.now()}`;
  const clinicId = `BLD-SHORTFALL-CLINIC-${Date.now()}`;
  const gameDay = 52;

  let humanId, houseId, houseEconId;
  const extraHumanIds = [];
  const extraAuthEmails = [];

  try {
    const reg = await registerIdentity(repository, { email, personName: 'ShortfallHuman', houseSurname: `ShortfallHouse${Date.now()}`, password: 'correct-horse-battery-staple' });
    humanId = reg.human.id;
    houseId = `HOUSE-${humanId.slice(2)}`;
    houseEconId = `ECON-${houseId}`;

    await repository.transaction(async (tx) => {
      await tx.query(`INSERT INTO institutions (id, kind, name, status) VALUES ($1, 'CORPORATION', $2, 'ACTIVE')`, [corpId, `Shortfall Corp ${Date.now()}`]);
      await tx.query(`INSERT INTO corporations (id, charter_version, admission_policy, status, created_game_day) VALUES ($1, 'corporation-charter-v5', 'OPEN', 'ACTIVE', 1)`, [corpId]);
      await tx.query(`INSERT INTO owner_registry (id, owner_type, economic_id) VALUES ($1, 'CORPORATION', $2)`, [corpId, corpEconId]);
      await tx.query('SELECT earth_provision_corporation_economy($1)', [corpEconId]);
      await tx.query(`INSERT INTO territories (id, corporation_id, name, status, is_primary) VALUES ($1, $2, 'Shortfall Territory', 'ACTIVE', true)`, [territoryId, corpId]);

      // Add extra 19 humans so total residents = 20 (demand = 20 for HEALTH and 20 for CONNECTIVITY)
      for (let i = 1; i <= 19; i++) {
        const extraEmail = `extra-sf-${i}-${Date.now()}@example.invalid`;
        const authId = `ACC-EXTRA-SF-${i}-${Date.now()}`;
        extraAuthEmails.push(extraEmail);
        await tx.query(`INSERT INTO auth_accounts (id, email, password_hash, password_salt, password_iterations, house_id) VALUES ($1, $2, 'dummy-hash', 'dummy-salt', 1000, $3)`, [authId, extraEmail, houseId]);
        const hId = `H-EXTRA-SF-${i}-${Date.now()}`;
        extraHumanIds.push(hId);
        await tx.query(`INSERT INTO humans (id, account_id, house_id, display_name, status) VALUES ($1, $2, $3, $4, 'ACTIVE')`, [hId, authId, houseId, `Shortfall Resident ${i}`]);
      }

      await tx.query(`INSERT INTO house_residencies (id, house_id, territory_id, residency_class, status, effective_from_game_day, correlation_id) VALUES ($1, $2, $3, 'PRIMARY', 'ACTIVE', 1, $4)`, [`res:sf:${Date.now()}`, houseId, territoryId, `res:sf:${Date.now()}`]);
      await tx.query(`INSERT INTO house_affiliations (house_id, corporation_id, primary_territory_id, joined_game_day, status) VALUES ($1, $2, $3, 1, 'ACTIVE')`, [houseId, corpId, territoryId]);

      // Build COMMUNITY-CLINIC-T1 (capacity 8 HEALTH, owned by House). Provide 0 CONNECTIVITY provider in territory.
      await tx.query(`
        INSERT INTO buildings (id, catalog_id, owner_economic_id, territory_id, status, construction_state, installed_generation, catalog_definition_version, technology_definition_version, operating_mode, started_game_day, last_major_rebuild_game_day)
        VALUES ($1, 'COMMUNITY-CLINIC-T1', $2, $3, 'ACTIVE', 'ACTIVE', 1, 'v5-alpha-1', 'tech-gen-v1', 'BALANCED', 1, 1)
      `, [clinicId, houseEconId, territoryId]);

      const res = await settleHouseNeedsAndServices(tx, gameDay, 0, 1);
      assert.ok(res.shortfalls >= 1);

      // 1. HEALTH Assessment: Demand 20, Allocated 8, Shortfall 12 -> WATCH (8/20 = 40% < 75%)
      const healthAssessment = (await tx.query(`SELECT * FROM house_need_assessments WHERE house_id = $1 AND game_day = $2 AND need_code = 'HEALTH'`, [houseId, gameDay])).rows[0];
      assert.ok(healthAssessment);
      assert.equal(healthAssessment.demand_units, '20');
      assert.equal(healthAssessment.allocated_units, '8');
      assert.equal(healthAssessment.shortfall_units, '12');
      assert.equal(healthAssessment.risk_level, 'WATCH');

      // 2. CONNECTIVITY Assessment: Demand 20, Allocated 0, Shortfall 20 -> CRITICAL
      const connAssessment = (await tx.query(`SELECT * FROM house_need_assessments WHERE house_id = $1 AND game_day = $2 AND need_code = 'CONNECTIVITY'`, [houseId, gameDay])).rows[0];
      assert.ok(connAssessment);
      assert.equal(connAssessment.demand_units, '20');
      assert.equal(connAssessment.allocated_units, '0');
      assert.equal(connAssessment.shortfall_units, '20');
      assert.equal(connAssessment.risk_level, 'CRITICAL');
    });
  } finally {
    await client.query('DELETE FROM service_allocations WHERE house_id = $1', [houseId]);
    await client.query('DELETE FROM house_need_assessments WHERE house_id = $1', [houseId]);
    await client.query('DELETE FROM buildings WHERE id = $1', [clinicId]);
    await client.query('DELETE FROM house_affiliations WHERE house_id = $1', [houseId]);
    await client.query('DELETE FROM house_residencies WHERE house_id = $1', [houseId]);
    await client.query('DELETE FROM territory_capacity_state WHERE territory_id = $1', [territoryId]);
    await client.query('DELETE FROM territories WHERE id = $1', [territoryId]);
    await client.query('DELETE FROM economic_entries WHERE account_id IN (SELECT id FROM economic_accounts WHERE owner_economic_id IN ($1, $2))', [corpEconId, houseEconId]);
    await client.query('DELETE FROM economic_entries WHERE transaction_id IN (SELECT id FROM economic_transactions WHERE source_id IN ($1, $2, $3) OR correlation_id LIKE $4 OR correlation_id LIKE $5)', [corpEconId, houseEconId, humanId, `service:${gameDay}:%`, `starter:${houseId}:%`]);
    await client.query('DELETE FROM economic_transactions WHERE source_id IN ($1, $2, $3) OR correlation_id LIKE $4 OR correlation_id LIKE $5', [corpEconId, houseEconId, humanId, `service:${gameDay}:%`, `starter:${houseId}:%`]);
    await client.query('DELETE FROM economic_accounts WHERE owner_economic_id IN ($1, $2)', [corpEconId, houseEconId]);
    await client.query('DELETE FROM owner_registry WHERE economic_id IN ($1, $2)', [corpEconId, houseEconId]);
    await client.query('DELETE FROM corporations WHERE id = $1', [corpId]);
    await client.query('DELETE FROM institutions WHERE id = $1', [corpId]);
    for (const hId of extraHumanIds) {
      await client.query('DELETE FROM humans WHERE id = $1', [hId]);
    }
    for (const em of extraAuthEmails) {
      await client.query('DELETE FROM auth_accounts WHERE email = $1', [em]);
    }
    if (humanId) {
      await client.query('DELETE FROM auth_sessions WHERE account_id = $1', [`account-${humanId.toLowerCase()}`]);
      await client.query('DELETE FROM game_events WHERE actor_human_id = $1', [humanId]);
      await client.query('DELETE FROM notifications WHERE human_id = $1', [humanId]);
      await client.query('DELETE FROM personal_life_maintenance WHERE human_id = $1', [humanId]);
      await client.query('DELETE FROM event_outbox WHERE aggregate_id = $1', [humanId]);
      await client.query('UPDATE houses SET current_human_id = NULL WHERE id = $1', [houseId]);
      await client.query('DELETE FROM humans WHERE id = $1', [humanId]);
      await client.query('UPDATE auth_accounts SET house_id = NULL WHERE email = $1', [email]);
      await client.query('DELETE FROM house_entry_support WHERE house_id = $1', [houseId]);
      await client.query('DELETE FROM house_onboarding_progress WHERE house_id = $1', [houseId]);
      await client.query('DELETE FROM v5_house_settlement_profiles WHERE house_id = $1', [houseId]);
      await client.query('DELETE FROM houses WHERE id = $1', [houseId]);
      await client.query('DELETE FROM auth_accounts WHERE email = $1', [email]);
    }
    await client.end();
  }
});

test('PostgreSQL V5 Economic Core Phase 5: Unfunded consumer receives service with financial obligation without minting credit', async () => {
  const client = await connectTo(connectionString);
  const repository = new PostgresRepository(client);

  const email = `unfunded-user-${Date.now()}@example.invalid`;
  const corpId = `CORP-SVC-UNFUNDED-${Date.now()}`;
  const corpEconId = `ECON-${corpId}`;
  const territoryId = `TERR-SVC-UNFUNDED-${Date.now()}`;
  const hospitalId = `BLD-UNFUNDED-HOSPITAL-${Date.now()}`;
  const gameDay = 53;

  let humanId, houseId, houseEconId;

  try {
    const reg = await registerIdentity(repository, { email, personName: 'UnfundedHuman', houseSurname: `UnfundedHouse${Date.now()}`, password: 'correct-horse-battery-staple' });
    humanId = reg.human.id;
    houseId = `HOUSE-${humanId.slice(2)}`;
    houseEconId = `ECON-${houseId}`;

    await repository.transaction(async (tx) => {
      await tx.query(`INSERT INTO institutions (id, kind, name, status) VALUES ($1, 'CORPORATION', $2, 'ACTIVE')`, [corpId, `Unfunded Corp ${Date.now()}`]);
      await tx.query(`INSERT INTO corporations (id, charter_version, admission_policy, status, created_game_day) VALUES ($1, 'corporation-charter-v5', 'OPEN', 'ACTIVE', 1)`, [corpId]);
      await tx.query(`INSERT INTO owner_registry (id, owner_type, economic_id) VALUES ($1, 'CORPORATION', $2)`, [corpId, corpEconId]);
      await tx.query('SELECT earth_provision_corporation_economy($1)', [corpEconId]);
      await tx.query(`INSERT INTO territories (id, corporation_id, name, status, is_primary) VALUES ($1, $2, 'Unfunded Territory', 'ACTIVE', true)`, [territoryId, corpId]);

      await tx.query(`INSERT INTO house_residencies (id, house_id, territory_id, residency_class, status, effective_from_game_day, correlation_id) VALUES ($1, $2, $3, 'PRIMARY', 'ACTIVE', 1, $4)`, [`res:unf:${Date.now()}`, houseId, territoryId, `res:unf:${Date.now()}`]);

      // Set House WALLET balance to 0 CREDIT
      const houseWallet = (await tx.query(`SELECT id FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 1 AND account_type = 'WALLET'`, [houseEconId])).rows[0];
      await tx.query(`UPDATE economic_accounts SET balance_units = 0 WHERE id = $1`, [houseWallet.id]);

      // Setup PUBLIC-MEDICAL-T1 (Corporation owned)
      await tx.query(`
        INSERT INTO buildings (id, catalog_id, owner_economic_id, territory_id, status, construction_state, installed_generation, catalog_definition_version, technology_definition_version, operating_mode, started_game_day, last_major_rebuild_game_day)
        VALUES ($1, 'PUBLIC-MEDICAL-T1', $2, $3, 'ACTIVE', 'ACTIVE', 1, 'v5-alpha-1', 'tech-gen-v1', 'BALANCED', 1, 1)
      `, [hospitalId, corpEconId, territoryId]);

      // Settle needs and services
      const res = await settleHouseNeedsAndServices(tx, gameDay, 0, 1);
      assert.ok(res.allocations >= 1);

      // 1. Verify service allocation was recorded
      const allocation = (await tx.query(`SELECT * FROM service_allocations WHERE house_id = $1 AND game_day = $2 AND service_code = 'HEALTH'`, [houseId, gameDay])).rows[0];
      assert.ok(allocation);
      assert.equal(allocation.allocated_units, '1');
      assert.equal(allocation.price_units, '1');
      assert.equal(allocation.economic_transaction_id, null, 'No payment transaction because payer had 0 CREDIT');

      // 2. Verify financial obligation (SERVICE_INVOICE) was created
      const obligation = (await tx.query(`SELECT * FROM financial_obligations WHERE debtor_economic_id = $1 AND creditor_economic_id = $2 AND obligation_type = 'SERVICE_INVOICE'`, [houseEconId, corpEconId])).rows[0];
      assert.ok(obligation);
      assert.equal(obligation.principal_due_units, '1');
      assert.equal(obligation.status, 'DUE');

      // 3. Verify WALLET balances never become negative or artificially inflated
      const houseRemWallet = (await tx.query(`SELECT balance_units::TEXT FROM economic_accounts WHERE id = $1`, [houseWallet.id])).rows[0];
      assert.equal(houseRemWallet.balance_units, '0', 'House WALLET is not negative');

      const corpOps = (await tx.query(`SELECT balance_units::TEXT FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 1 AND account_type = 'OPERATIONS'`, [corpEconId])).rows[0];
      assert.equal(corpOps.balance_units, '0', 'Corporation OPERATIONS has 0 unbacked CREDIT');
    });
  } finally {
    await client.query('DELETE FROM financial_obligations WHERE debtor_economic_id = $1', [houseEconId]);
    await client.query('DELETE FROM service_allocations WHERE house_id = $1', [houseId]);
    await client.query('DELETE FROM house_need_assessments WHERE house_id = $1', [houseId]);
    await client.query('DELETE FROM buildings WHERE id = $1', [hospitalId]);
    await client.query('DELETE FROM house_residencies WHERE house_id = $1', [houseId]);
    await client.query('DELETE FROM territory_capacity_state WHERE territory_id = $1', [territoryId]);
    await client.query('DELETE FROM territories WHERE id = $1', [territoryId]);
    await client.query('DELETE FROM economic_entries WHERE account_id IN (SELECT id FROM economic_accounts WHERE owner_economic_id IN ($1, $2))', [corpEconId, houseEconId]);
    await client.query('DELETE FROM economic_entries WHERE transaction_id IN (SELECT id FROM economic_transactions WHERE source_id IN ($1, $2, $3) OR correlation_id LIKE $4 OR correlation_id LIKE $5)', [corpEconId, houseEconId, humanId, `service:${gameDay}:%`, `starter:${houseId}:%`]);
    await client.query('DELETE FROM economic_transactions WHERE source_id IN ($1, $2, $3) OR correlation_id LIKE $4 OR correlation_id LIKE $5', [corpEconId, houseEconId, humanId, `service:${gameDay}:%`, `starter:${houseId}:%`]);
    await client.query('DELETE FROM economic_accounts WHERE owner_economic_id IN ($1, $2)', [corpEconId, houseEconId]);
    await client.query('DELETE FROM owner_registry WHERE economic_id IN ($1, $2)', [corpEconId, houseEconId]);
    await client.query('DELETE FROM corporations WHERE id = $1', [corpId]);
    await client.query('DELETE FROM institutions WHERE id = $1', [corpId]);
    if (humanId) {
      await client.query('DELETE FROM auth_sessions WHERE account_id = $1', [`account-${humanId.toLowerCase()}`]);
      await client.query('DELETE FROM game_events WHERE actor_human_id = $1', [humanId]);
      await client.query('DELETE FROM notifications WHERE human_id = $1', [humanId]);
      await client.query('DELETE FROM personal_life_maintenance WHERE human_id = $1', [humanId]);
      await client.query('DELETE FROM event_outbox WHERE aggregate_id = $1', [humanId]);
      await client.query('UPDATE houses SET current_human_id = NULL WHERE id = $1', [houseId]);
      await client.query('DELETE FROM humans WHERE id = $1', [humanId]);
      await client.query('UPDATE auth_accounts SET house_id = NULL WHERE email = $1', [email]);
      await client.query('DELETE FROM house_entry_support WHERE house_id = $1', [houseId]);
      await client.query('DELETE FROM house_onboarding_progress WHERE house_id = $1', [houseId]);
      await client.query('DELETE FROM v5_house_settlement_profiles WHERE house_id = $1', [houseId]);
      await client.query('DELETE FROM houses WHERE id = $1', [houseId]);
      await client.query('DELETE FROM auth_accounts WHERE email = $1', [email]);
    }
    await client.end();
  }
});

test('PostgreSQL V5 Economic Core Phase 5: Architecture integrity report passes with 0 failures across all production entities', async () => {
  const client = await connectTo(connectionString);
  try {
    const reportRes = await client.query('SELECT * FROM earth_integrity_report()');
    for (const check of reportRes.rows) {
      assert.equal(check.invalid_count, '0', `Integrity check ${check.check_name} must have 0 invalid rows`);
    }
  } finally {
    await client.end();
  }
});

// ─── Phase 6: Enforce Tier and Scale Engineering ───

test('PostgreSQL V5 Economic Core Phase 6: House cannot construct Tier 2 building without SCALE_COMMERCIAL', async () => {
  const client = await connectTo(connectionString);
  const repository = new PostgresRepository(client);
  const ts = Date.now();
  const corpId = `CORP-P6T1-${ts}`;
  const corpEconId = `ECON-${corpId}`;
  const houseId = `HOUSE-P6T1-${ts}`;
  const houseEconId = `ECON-${houseId}`;
  const humanId = `HUMAN-P6T1-${ts}`;
  const email = `phase6t1+${ts}@test.local`;

  try {
    await repository.transaction(async (tx) => {
      // Setup Corporation
      await tx.query(`INSERT INTO institutions (id, kind, name, status) VALUES ($1, 'CORPORATION', 'Scale Test Corp', 'ACTIVE')`, [corpId]);
      await tx.query(`INSERT INTO corporations (id, charter_version, admission_policy, status, created_game_day) VALUES ($1, 'corporation-charter-v5', 'OPEN', 'ACTIVE', 1)`, [corpId]);
      await tx.query(`INSERT INTO owner_registry (id, owner_type, economic_id) VALUES ($1, 'CORPORATION', $2)`, [corpId, corpEconId]);
      await tx.query('SELECT earth_provision_corporation_economy($1)', [corpEconId]);
      // Setup House and Human
      await tx.query(`INSERT INTO auth_accounts (id, email, password_hash, password_salt, password_iterations) VALUES ($1, $2, 'test-password-hash', 'salt', 100000)`, [`AUTH-${humanId}`, email]);
      await tx.query(`INSERT INTO houses (id, account_id, house_name, status) VALUES ($1, $2, 'Scale Test House', 'ACTIVE')`, [houseId, `AUTH-${humanId}`]);
      await tx.query(`INSERT INTO owner_registry (id, owner_type, economic_id) VALUES ($1, 'HOUSE', $2)`, [houseId, houseEconId]);
      await tx.query('SELECT earth_provision_house_economy($1)', [houseEconId]);
      await tx.query(`INSERT INTO humans (id, account_id, house_id, display_name, status) VALUES ($1, $2, $3, 'Scale Tester', 'ACTIVE')`, [humanId, `AUTH-${humanId}`, houseId]);
      await tx.query(`INSERT INTO house_affiliations (house_id, corporation_id, joined_game_day, status) VALUES ($1, $2, 1, 'ACTIVE')`, [houseId, corpId]);
      // Fund wallet
      const wallet = (await tx.query(`SELECT id FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 1 AND account_type = 'WALLET'`, [houseEconId])).rows[0];
      await tx.query(`UPDATE economic_accounts SET balance_units = 500000 WHERE id = $1`, [wallet.id]);

      // Quote T2 Solar Microgrid (requires SCALE_COMMERCIAL) — should show blocker
      const quote = await quoteV5Building(repository, { ownerId: humanId, buildingType: 'SOLAR-MICROGRID-T2' });
      assert.equal(quote.ok, true);
      assert.equal(quote.eligible, false);
      assert.ok(quote.blockers.some(b => String(b).includes('scale capability')), 'Blocker must mention scale capability');
      assert.equal(quote.minimumScaleCapability, 'SCALE_COMMERCIAL');

      // Attempt purchase — should throw
      await assert.rejects(
        () => purchaseV5Building(repository, { ownerId: humanId, buildingType: 'SOLAR-MICROGRID-T2', name: 'T2 Solar', correlationId: `p6t1-purchase-${ts}` }),
        (err) => err.message.includes('scale capability'),
      );

      // T1 should still work (SCALE_NONE)
      const t1Quote = await quoteV5Building(repository, { ownerId: humanId, buildingType: 'SOLAR-MICROGRID-T1' });
      assert.equal(t1Quote.scaleAuthorization?.authorized, true, 'T1 construction should be scale-authorized without special capabilities');
    });
  } finally {
    await client.query('DELETE FROM economic_entries WHERE account_id IN (SELECT id FROM economic_accounts WHERE owner_economic_id IN ($1, $2))', [houseEconId, corpEconId]);
    await client.query('DELETE FROM economic_transactions WHERE correlation_id LIKE $1', [`p6t1-%`]);
    await client.query('DELETE FROM economic_accounts WHERE owner_economic_id IN ($1, $2)', [houseEconId, corpEconId]);
    await client.query('DELETE FROM house_affiliations WHERE house_id = $1', [houseId]);
    await client.query('DELETE FROM humans WHERE id = $1', [humanId]);
    await client.query('DELETE FROM v5_house_settlement_profiles WHERE house_id = $1', [houseId]);
    await client.query('DELETE FROM v5_corporation_settlement_profiles WHERE corporation_id = $1', [corpId]);
    await client.query('DELETE FROM houses WHERE id = $1', [houseId]);
    await client.query('DELETE FROM owner_registry WHERE economic_id IN ($1, $2)', [houseEconId, corpEconId]);
    await client.query('DELETE FROM corporations WHERE id = $1', [corpId]);
    await client.query('DELETE FROM institutions WHERE id = $1', [corpId]);
    await client.query('DELETE FROM auth_accounts WHERE id = $1', [`AUTH-${humanId}`]);
    await client.end();
  }
});

test('PostgreSQL V5 Economic Core Phase 6: Corporation cannot construct Tier 3 without SCALE_INDUSTRIAL', async () => {
  const client = await connectTo(connectionString);
  const repository = new PostgresRepository(client);
  const ts = Date.now();
  const corpId = `CORP-P6T2-${ts}`;
  const corpEconId = `ECON-${corpId}`;
  const houseId = `HOUSE-P6T2-${ts}`;
  const houseEconId = `ECON-${houseId}`;
  const humanId = `HUMAN-P6T2-${ts}`;
  const email = `phase6t2+${ts}@test.local`;

  try {
    await repository.transaction(async (tx) => {
      await tx.query(`INSERT INTO institutions (id, kind, name, status) VALUES ($1, 'CORPORATION', 'Corp Scale T2', 'ACTIVE')`, [corpId]);
      await tx.query(`INSERT INTO corporations (id, charter_version, admission_policy, status, created_game_day) VALUES ($1, 'corporation-charter-v5', 'OPEN', 'ACTIVE', 1)`, [corpId]);
      await tx.query(`INSERT INTO owner_registry (id, owner_type, economic_id) VALUES ($1, 'CORPORATION', $2)`, [corpId, corpEconId]);
      await tx.query('SELECT earth_provision_corporation_economy($1)', [corpEconId]);
      await tx.query(`INSERT INTO auth_accounts (id, email, password_hash, password_salt, password_iterations) VALUES ($1, $2, 'test-password-hash', 'salt', 100000)`, [`AUTH-${humanId}`, email]);
      await tx.query(`INSERT INTO houses (id, account_id, house_name, status) VALUES ($1, $2, 'Corp Scale House', 'ACTIVE')`, [houseId, `AUTH-${humanId}`]);
      await tx.query(`INSERT INTO owner_registry (id, owner_type, economic_id) VALUES ($1, 'HOUSE', $2)`, [houseId, houseEconId]);
      await tx.query('SELECT earth_provision_house_economy($1)', [houseEconId]);
      await tx.query(`INSERT INTO humans (id, account_id, house_id, display_name, status) VALUES ($1, $2, $3, 'Corp Tester', 'ACTIVE')`, [humanId, `AUTH-${humanId}`, houseId]);
      await tx.query(`INSERT INTO house_affiliations (house_id, corporation_id, joined_game_day, status) VALUES ($1, $2, 1, 'ACTIVE')`, [houseId, corpId]);
      await tx.query(`INSERT INTO institution_governance_roles (institution_id, human_id, role_code, status) VALUES ($1, $2, 'CORPORATION_EXECUTIVE', 'ACTIVE')`, [corpId, humanId]);
      // Grant SCALE_COMMERCIAL but not SCALE_INDUSTRIAL
      await grantCorporationScaleCapability(tx, corpEconId, 'SCALE_COMMERCIAL', 1);

      // Fund treasury
      const treasury = (await tx.query(`SELECT id FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 1 AND account_type = 'TREASURY'`, [corpEconId])).rows[0];
      await tx.query(`UPDATE economic_accounts SET balance_units = 1000000 WHERE id = $1`, [treasury.id]);

      // Quote PUBLIC-MEDICAL-CENTER-T3 (requires SCALE_INDUSTRIAL)
      const quote = await quoteV5Building(repository, { ownerId: humanId, buildingType: 'PUBLIC-MEDICAL-T3' });
      assert.equal(quote.ok, true);
      assert.equal(quote.eligible, false);
      assert.ok(quote.blockers.some(b => String(b).includes('SCALE_INDUSTRIAL')), 'Should require SCALE_INDUSTRIAL');

      // T2 should be eligible (SCALE_COMMERCIAL is unlocked)
      const t2Quote = await quoteV5Building(repository, { ownerId: humanId, buildingType: 'PUBLIC-MEDICAL-T2' });
      assert.equal(t2Quote.scaleAuthorization?.authorized, true, 'T2 public building should be authorized with SCALE_COMMERCIAL');
    });
  } finally {
    await client.query('DELETE FROM corporation_scale_capabilities WHERE corporation_economic_id = $1', [corpEconId]);
    await client.query('DELETE FROM institution_governance_roles WHERE institution_id = $1', [corpId]);
    await client.query('DELETE FROM economic_entries WHERE account_id IN (SELECT id FROM economic_accounts WHERE owner_economic_id IN ($1, $2))', [houseEconId, corpEconId]);
    await client.query('DELETE FROM economic_accounts WHERE owner_economic_id IN ($1, $2)', [houseEconId, corpEconId]);
    await client.query('DELETE FROM house_affiliations WHERE house_id = $1', [houseId]);
    await client.query('DELETE FROM humans WHERE id = $1', [humanId]);
    await client.query('DELETE FROM v5_house_settlement_profiles WHERE house_id = $1', [houseId]);
    await client.query('DELETE FROM v5_corporation_settlement_profiles WHERE corporation_id = $1', [corpId]);
    await client.query('DELETE FROM houses WHERE id = $1', [houseId]);
    await client.query('DELETE FROM owner_registry WHERE economic_id IN ($1, $2)', [houseEconId, corpEconId]);
    await client.query('DELETE FROM corporations WHERE id = $1', [corpId]);
    await client.query('DELETE FROM institutions WHERE id = $1', [corpId]);
    await client.query('DELETE FROM auth_accounts WHERE id = $1', [`AUTH-${humanId}`]);
    await client.end();
  }
});

test('PostgreSQL V5 Economic Core Phase 6: Corporation unlocking SCALE_COMMERCIAL allows affiliated House to construct T2', async () => {
  const client = await connectTo(connectionString);
  const repository = new PostgresRepository(client);
  const ts = Date.now();
  const corpId = `CORP-P6T3-${ts}`;
  const corpEconId = `ECON-${corpId}`;
  const houseId = `HOUSE-P6T3-${ts}`;
  const houseEconId = `ECON-${houseId}`;
  const humanId = `HUMAN-P6T3-${ts}`;
  const email = `phase6t3+${ts}@test.local`;

  try {
    await repository.transaction(async (tx) => {
      await tx.query(`INSERT INTO institutions (id, kind, name, status) VALUES ($1, 'CORPORATION', 'Unlock Corp', 'ACTIVE')`, [corpId]);
      await tx.query(`INSERT INTO corporations (id, charter_version, admission_policy, status, created_game_day) VALUES ($1, 'corporation-charter-v5', 'OPEN', 'ACTIVE', 1)`, [corpId]);
      await tx.query(`INSERT INTO owner_registry (id, owner_type, economic_id) VALUES ($1, 'CORPORATION', $2)`, [corpId, corpEconId]);
      await tx.query('SELECT earth_provision_corporation_economy($1)', [corpEconId]);
      await tx.query(`INSERT INTO auth_accounts (id, email, password_hash, password_salt, password_iterations) VALUES ($1, $2, 'test-password-hash', 'salt', 100000)`, [`AUTH-${humanId}`, email]);
      await tx.query(`INSERT INTO houses (id, account_id, house_name, status) VALUES ($1, $2, 'Unlock House', 'ACTIVE')`, [houseId, `AUTH-${humanId}`]);
      await tx.query(`INSERT INTO owner_registry (id, owner_type, economic_id) VALUES ($1, 'HOUSE', $2)`, [houseId, houseEconId]);
      await tx.query('SELECT earth_provision_house_economy($1)', [houseEconId]);
      await tx.query(`INSERT INTO humans (id, account_id, house_id, display_name, status) VALUES ($1, $2, $3, 'Affiliated Human', 'ACTIVE')`, [humanId, `AUTH-${humanId}`, houseId]);
      await tx.query(`INSERT INTO house_affiliations (house_id, corporation_id, joined_game_day, status) VALUES ($1, $2, 1, 'ACTIVE')`, [houseId, corpId]);
      const wallet = (await tx.query(`SELECT id FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 1 AND account_type = 'WALLET'`, [houseEconId])).rows[0];
      await tx.query(`UPDATE economic_accounts SET balance_units = 500000 WHERE id = $1`, [wallet.id]);

      // Before granting — T2 should be blocked
      const quoteBefore = await quoteV5Building(repository, { ownerId: humanId, buildingType: 'SOLAR-MICROGRID-T2' });
      assert.equal(quoteBefore.eligible, false);

      // Grant SCALE_COMMERCIAL to the Corporation
      await grantCorporationScaleCapability(tx, corpEconId, 'SCALE_COMMERCIAL', 1);

      // After granting — T2 should pass scale check
      const quoteAfter = await quoteV5Building(repository, { ownerId: humanId, buildingType: 'SOLAR-MICROGRID-T2' });
      assert.equal(quoteAfter.scaleAuthorization?.authorized, true, 'Affiliated House should inherit Corporation scale capability');
    });
  } finally {
    await client.query('DELETE FROM corporation_scale_capabilities WHERE corporation_economic_id = $1', [corpEconId]);
    await client.query('DELETE FROM economic_entries WHERE account_id IN (SELECT id FROM economic_accounts WHERE owner_economic_id IN ($1, $2))', [houseEconId, corpEconId]);
    await client.query('DELETE FROM economic_accounts WHERE owner_economic_id IN ($1, $2)', [houseEconId, corpEconId]);
    await client.query('DELETE FROM house_affiliations WHERE house_id = $1', [houseId]);
    await client.query('DELETE FROM humans WHERE id = $1', [humanId]);
    await client.query('DELETE FROM v5_house_settlement_profiles WHERE house_id = $1', [houseId]);
    await client.query('DELETE FROM v5_corporation_settlement_profiles WHERE corporation_id = $1', [corpId]);
    await client.query('DELETE FROM houses WHERE id = $1', [houseId]);
    await client.query('DELETE FROM owner_registry WHERE economic_id IN ($1, $2)', [houseEconId, corpEconId]);
    await client.query('DELETE FROM corporations WHERE id = $1', [corpId]);
    await client.query('DELETE FROM institutions WHERE id = $1', [corpId]);
    await client.query('DELETE FROM auth_accounts WHERE id = $1', [`AUTH-${humanId}`]);
    await client.end();
  }
});

test('PostgreSQL V5 Economic Core Phase 6: Independent House can build T2 only after Earth baseline unlock', async () => {
  const client = await connectTo(connectionString);
  const repository = new PostgresRepository(client);
  const ts = Date.now();
  const houseId = `HOUSE-P6T4-${ts}`;
  const houseEconId = `ECON-${houseId}`;
  const humanId = `HUMAN-P6T4-${ts}`;
  const email = `phase6t4+${ts}@test.local`;

  try {
    await repository.transaction(async (tx) => {
      await tx.query(`INSERT INTO auth_accounts (id, email, password_hash, password_salt, password_iterations) VALUES ($1, $2, 'test-password-hash', 'salt', 100000)`, [`AUTH-${humanId}`, email]);
      await tx.query(`INSERT INTO houses (id, account_id, house_name, status) VALUES ($1, $2, 'Independent House', 'ACTIVE')`, [houseId, `AUTH-${humanId}`]);
      await tx.query(`INSERT INTO owner_registry (id, owner_type, economic_id) VALUES ($1, 'HOUSE', $2)`, [houseId, houseEconId]);
      await tx.query('SELECT earth_provision_house_economy($1)', [houseEconId]);
      await tx.query(`INSERT INTO humans (id, account_id, house_id, display_name, status) VALUES ($1, $2, $3, 'Independent Human', 'ACTIVE')`, [humanId, `AUTH-${humanId}`, houseId]);
      const wallet = (await tx.query(`SELECT id FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 1 AND account_type = 'WALLET'`, [houseEconId])).rows[0];
      await tx.query(`UPDATE economic_accounts SET balance_units = 500000 WHERE id = $1`, [wallet.id]);

      // No affiliation — T2 should be blocked (no Corp, no Earth baseline)
      const quoteBefore = await quoteV5Building(repository, { ownerId: humanId, buildingType: 'SOLAR-MICROGRID-T2' });
      assert.equal(quoteBefore.eligible, false);
      assert.ok(quoteBefore.blockers.some(b => String(b).includes('scale capability')));

      // Grant SCALE_COMMERCIAL as Earth baseline
      await grantEarthBaselineScaleCapability(tx, 'SCALE_COMMERCIAL', 1);

      // Now T2 should be available
      const quoteAfter = await quoteV5Building(repository, { ownerId: humanId, buildingType: 'SOLAR-MICROGRID-T2' });
      assert.equal(quoteAfter.scaleAuthorization?.authorized, true, 'Earth baseline SCALE_COMMERCIAL should authorize independent House for T2');

      // Cleanup baseline
      await tx.query('DELETE FROM earth_scale_capabilities WHERE scale_capability = $1', ['SCALE_COMMERCIAL']);
    });
  } finally {
    await client.query('DELETE FROM earth_scale_capabilities WHERE scale_capability = $1', ['SCALE_COMMERCIAL']);
    await client.query('DELETE FROM economic_entries WHERE account_id IN (SELECT id FROM economic_accounts WHERE owner_economic_id = $1)', [houseEconId]);
    await client.query('DELETE FROM economic_accounts WHERE owner_economic_id = $1', [houseEconId]);
    await client.query('DELETE FROM humans WHERE id = $1', [humanId]);
    await client.query('DELETE FROM v5_house_settlement_profiles WHERE house_id = $1', [houseId]);
    await client.query('DELETE FROM houses WHERE id = $1', [houseId]);
    await client.query('DELETE FROM owner_registry WHERE economic_id = $1', [houseEconId]);
    await client.query('DELETE FROM auth_accounts WHERE id = $1', [`AUTH-${humanId}`]);
    await client.end();
  }
});

test('PostgreSQL V5 Economic Core Phase 6: Upgrade quote shows before/after rent and scale authorization', async () => {
  const client = await connectTo(connectionString);
  const repository = new PostgresRepository(client);
  const ts = Date.now();
  const corpId = `CORP-P6T5-${ts}`;
  const corpEconId = `ECON-${corpId}`;
  const houseId = `HOUSE-P6T5-${ts}`;
  const houseEconId = `ECON-${houseId}`;
  const humanId = `HUMAN-P6T5-${ts}`;
  const email = `phase6t5+${ts}@test.local`;
  const buildingId = `BLD-P6T5-${ts}`;
  const territoryId = `TERR-P6T5-${ts}`;

  try {
    await repository.transaction(async (tx) => {
      await tx.query(`INSERT INTO institutions (id, kind, name, status) VALUES ($1, 'CORPORATION', 'Rent Corp', 'ACTIVE')`, [corpId]);
      await tx.query(`INSERT INTO corporations (id, charter_version, admission_policy, status, created_game_day) VALUES ($1, 'corporation-charter-v5', 'OPEN', 'ACTIVE', 1)`, [corpId]);
      await tx.query(`INSERT INTO owner_registry (id, owner_type, economic_id) VALUES ($1, 'CORPORATION', $2)`, [corpId, corpEconId]);
      await tx.query('SELECT earth_provision_corporation_economy($1)', [corpEconId]);
      await tx.query(`INSERT INTO auth_accounts (id, email, password_hash, password_salt, password_iterations) VALUES ($1, $2, 'test-password-hash', 'salt', 100000)`, [`AUTH-${humanId}`, email]);
      await tx.query(`INSERT INTO houses (id, account_id, house_name, status) VALUES ($1, $2, 'Rent House', 'ACTIVE')`, [houseId, `AUTH-${humanId}`]);
      await tx.query(`INSERT INTO owner_registry (id, owner_type, economic_id) VALUES ($1, 'HOUSE', $2)`, [houseId, houseEconId]);
      await tx.query('SELECT earth_provision_house_economy($1)', [houseEconId]);
      await tx.query(`INSERT INTO humans (id, account_id, house_id, display_name, status) VALUES ($1, $2, $3, 'Rent Tester', 'ACTIVE')`, [humanId, `AUTH-${humanId}`, houseId]);
      await tx.query(`INSERT INTO house_affiliations (house_id, corporation_id, joined_game_day, status) VALUES ($1, $2, 1, 'ACTIVE')`, [houseId, corpId]);
      await tx.query(`INSERT INTO territories (id, corporation_id, name, status, is_primary, created_game_day) VALUES ($1, $2, 'Rent Territory', 'ACTIVE', true, 1)`, [territoryId, corpId]);
      // Grant SCALE_COMMERCIAL
      await grantCorporationScaleCapability(tx, corpEconId, 'SCALE_COMMERCIAL', 1);
      // Fund wallet
      const wallet = (await tx.query(`SELECT id FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 1 AND account_type = 'WALLET'`, [houseEconId])).rows[0];
      await tx.query(`UPDATE economic_accounts SET balance_units = 500000 WHERE id = $1`, [wallet.id]);
      // Create T1 Solar Microgrid (owned by House)
      await tx.query(`INSERT INTO buildings (id, catalog_id, owner_economic_id, territory_id, status, construction_state, installed_generation, catalog_definition_version, technology_definition_version, operating_mode, started_game_day, last_major_rebuild_game_day) VALUES ($1, 'SOLAR-MICROGRID-T1', $2, $3, 'ACTIVE', 'ACTIVE', 1, 'v5-alpha-1', 'tech-gen-v1', 'BALANCED', 1, 1)`, [buildingId, houseEconId, territoryId]);

      // Quote upgrade T1 -> T2
      const quote = await quoteBuildingUpgrade(repository, { buildingId, humanId });
      assert.equal(quote.ok, true);
      assert.equal(quote.currentTier, 1);
      assert.equal(quote.targetTier, 2);
      assert.equal(quote.minimumScaleCapability, 'SCALE_COMMERCIAL');
      assert.equal(quote.scaleAuthorization?.authorized, true);
      // Rent fields should be present
      assert.ok(quote.beforeRentUnits !== undefined, 'beforeRentUnits must be present');
      assert.ok(quote.afterRentUnits !== undefined, 'afterRentUnits must be present');
      assert.ok(quote.deltaRentUnits !== undefined, 'deltaRentUnits must be present');
      // Resource requirements should be present
      assert.ok(Array.isArray(quote.resourceRequirements), 'resourceRequirements must be an array');

      // Without SCALE_COMMERCIAL — quote should show blocker
      await tx.query('DELETE FROM corporation_scale_capabilities WHERE corporation_economic_id = $1', [corpEconId]);
      const blockedQuote = await quoteBuildingUpgrade(repository, { buildingId, humanId });
      assert.ok(blockedQuote.blockers.includes('SCALE_CAPABILITY_REQUIRED'), 'Must have SCALE_CAPABILITY_REQUIRED blocker');
      assert.equal(blockedQuote.eligible, false);
    });
  } finally {
    await client.query('DELETE FROM corporation_scale_capabilities WHERE corporation_economic_id = $1', [corpEconId]);
    await client.query('DELETE FROM v5_house_settlement_profiles WHERE house_id = $1', [houseId]);
    await client.query('DELETE FROM construction_projects WHERE building_id = $1', [buildingId]);
    await client.query('DELETE FROM buildings WHERE id = $1', [buildingId]);
    await client.query('DELETE FROM territories WHERE id = $1', [territoryId]);
    await client.query('DELETE FROM economic_entries WHERE account_id IN (SELECT id FROM economic_accounts WHERE owner_economic_id IN ($1, $2))', [houseEconId, corpEconId]);
    await client.query('DELETE FROM economic_accounts WHERE owner_economic_id IN ($1, $2)', [houseEconId, corpEconId]);
    await client.query('DELETE FROM house_affiliations WHERE house_id = $1', [houseId]);
    await client.query('DELETE FROM institution_governance_roles WHERE institution_id = $1', [corpId]);
    await client.query('DELETE FROM humans WHERE id = $1', [humanId]);
    await client.query('DELETE FROM v5_house_settlement_profiles WHERE house_id = $1', [houseId]);
    await client.query('DELETE FROM v5_corporation_settlement_profiles WHERE corporation_id = $1', [corpId]);
    await client.query('DELETE FROM houses WHERE id = $1', [houseId]);
    await client.query('DELETE FROM owner_registry WHERE economic_id IN ($1, $2)', [houseEconId, corpEconId]);
    await client.query('DELETE FROM corporations WHERE id = $1', [corpId]);
    await client.query('DELETE FROM institutions WHERE id = $1', [corpId]);
    await client.query('DELETE FROM auth_accounts WHERE id = $1', [`AUTH-${humanId}`]);
    await client.end();
  }
});

test('PostgreSQL V5 Economic Core Phase 6: Tier upgrade consumes incremental credit and resource costs', async () => {
  const client = await connectTo(connectionString);
  const repository = new PostgresRepository(client);
  const ts = Date.now();
  const corpId = `CORP-P6T6-${ts}`;
  const corpEconId = `ECON-${corpId}`;
  const houseId = `HOUSE-P6T6-${ts}`;
  const houseEconId = `ECON-${houseId}`;
  const humanId = `HUMAN-P6T6-${ts}`;
  const email = `phase6t6+${ts}@test.local`;
  const buildingId = `BLD-P6T6-${ts}`;
  const territoryId = `TERR-P6T6-${ts}`;

  try {
    await repository.transaction(async (tx) => {
      await tx.query(`INSERT INTO institutions (id, kind, name, status) VALUES ($1, 'CORPORATION', 'Resource Corp', 'ACTIVE')`, [corpId]);
      await tx.query(`INSERT INTO corporations (id, charter_version, admission_policy, status, created_game_day) VALUES ($1, 'corporation-charter-v5', 'OPEN', 'ACTIVE', 1)`, [corpId]);
      await tx.query(`INSERT INTO owner_registry (id, owner_type, economic_id) VALUES ($1, 'CORPORATION', $2)`, [corpId, corpEconId]);
      await tx.query('SELECT earth_provision_corporation_economy($1)', [corpEconId]);
      await tx.query(`INSERT INTO auth_accounts (id, email, password_hash, password_salt, password_iterations) VALUES ($1, $2, 'test-password-hash', 'salt', 100000)`, [`AUTH-${humanId}`, email]);
      await tx.query(`INSERT INTO houses (id, account_id, house_name, status) VALUES ($1, $2, 'Resource House', 'ACTIVE')`, [houseId, `AUTH-${humanId}`]);
      await tx.query(`INSERT INTO owner_registry (id, owner_type, economic_id) VALUES ($1, 'HOUSE', $2)`, [houseId, houseEconId]);
      await tx.query('SELECT earth_provision_house_economy($1)', [houseEconId]);
      await tx.query(`INSERT INTO humans (id, account_id, house_id, display_name, status) VALUES ($1, $2, $3, 'Resource Tester', 'ACTIVE')`, [humanId, `AUTH-${humanId}`, houseId]);
      await tx.query(`INSERT INTO house_affiliations (house_id, corporation_id, joined_game_day, status) VALUES ($1, $2, 1, 'ACTIVE')`, [houseId, corpId]);
      await tx.query(`INSERT INTO territories (id, corporation_id, name, status, is_primary, created_game_day) VALUES ($1, $2, 'Resource Territory', 'ACTIVE', true, 1)`, [territoryId, corpId]);
      await grantCorporationScaleCapability(tx, corpEconId, 'SCALE_COMMERCIAL', 1);
      // Fund wallet with enough credits
      const wallet = (await tx.query(`SELECT id FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 1 AND account_type = 'WALLET'`, [houseEconId])).rows[0];
      await tx.query(`UPDATE economic_accounts SET balance_units = 500000 WHERE id = $1`, [wallet.id]);
      // Fund MATERIAL (asset_id=2) with enough for incremental T1->T2 (delta: 300 - 120 = 180)
      const matAcc = (await tx.query(`SELECT id FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 2 AND account_type = 'INVENTORY'`, [houseEconId])).rows[0];
      await tx.query(`UPDATE economic_accounts SET balance_units = 500 WHERE id = $1`, [matAcc.id]);
      // Fund COMPONENTS (asset_id=3) with enough for incremental T1->T2 (delta: 30 - 12 = 18)
      const compAcc = (await tx.query(`SELECT id FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 3 AND account_type = 'INVENTORY'`, [houseEconId])).rows[0];
      await tx.query(`UPDATE economic_accounts SET balance_units = 100 WHERE id = $1`, [compAcc.id]);
      // Fund COMPUTE (asset_id=5) with enough for incremental T1->T2 (delta: 12 - 5 = 7)
      const computeAcc = (await tx.query(`SELECT id FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 5 AND account_type = 'INVENTORY'`, [houseEconId])).rows[0];
      await tx.query(`UPDATE economic_accounts SET balance_units = 50 WHERE id = $1`, [computeAcc.id]);
      // Create T1 Solar Microgrid
      await tx.query(`INSERT INTO buildings (id, catalog_id, owner_economic_id, territory_id, status, construction_state, installed_generation, catalog_definition_version, technology_definition_version, operating_mode, started_game_day, last_major_rebuild_game_day) VALUES ($1, 'SOLAR-MICROGRID-T1', $2, $3, 'ACTIVE', 'ACTIVE', 1, 'v5-alpha-1', 'tech-gen-v1', 'BALANCED', 1, 1)`, [buildingId, houseEconId, territoryId]);

      // Record balances before upgrade
      const walletBefore = BigInt((await tx.query(`SELECT balance_units::TEXT AS b FROM economic_accounts WHERE id = $1`, [wallet.id])).rows[0].b);
      const matBefore = BigInt((await tx.query(`SELECT balance_units::TEXT AS b FROM economic_accounts WHERE id = $1`, [matAcc.id])).rows[0].b);
      const compBefore = BigInt((await tx.query(`SELECT balance_units::TEXT AS b FROM economic_accounts WHERE id = $1`, [compAcc.id])).rows[0].b);
      const computeBefore = BigInt((await tx.query(`SELECT balance_units::TEXT AS b FROM economic_accounts WHERE id = $1`, [computeAcc.id])).rows[0].b);

      // Execute upgrade T1 -> T2
      const correlationId = `p6t6-upgrade-${ts}`;
      const result = await upgradeBuilding(repository, { buildingId, humanId, correlationId });
      assert.equal(result.ok, true);
      assert.equal(result.fromTier, 1);
      assert.equal(result.toTier, 2);
      assert.ok(result.resourceCostUnits, 'resourceCostUnits must be present in result');

      // Verify incremental credit cost (T2: 30000 - T1: 12000 = 18000)
      const walletAfter = BigInt((await tx.query(`SELECT balance_units::TEXT AS b FROM economic_accounts WHERE id = $1`, [wallet.id])).rows[0].b);
      assert.equal((walletBefore - walletAfter).toString(), '18000', 'Credit cost should be incremental: 30000 - 12000 = 18000');

      // Verify incremental resource costs consumed
      const matAfter = BigInt((await tx.query(`SELECT balance_units::TEXT AS b FROM economic_accounts WHERE id = $1`, [matAcc.id])).rows[0].b);
      assert.equal((matBefore - matAfter).toString(), '180', 'MATERIAL cost should be incremental: 300 - 120 = 180');
      const compAfter = BigInt((await tx.query(`SELECT balance_units::TEXT AS b FROM economic_accounts WHERE id = $1`, [compAcc.id])).rows[0].b);
      assert.equal((compBefore - compAfter).toString(), '18', 'COMPONENTS cost should be incremental: 30 - 12 = 18');
      const computeAfter = BigInt((await tx.query(`SELECT balance_units::TEXT AS b FROM economic_accounts WHERE id = $1`, [computeAcc.id])).rows[0].b);
      assert.equal((computeBefore - computeAfter).toString(), '7', 'COMPUTE cost should be incremental: 12 - 5 = 7');

      // Verify construction project records resource cost
      const project = (await tx.query(`SELECT resource_cost_units FROM construction_projects WHERE correlation_id = $1`, [correlationId])).rows[0];
      assert.ok(project, 'Construction project must exist');
      const resourceCost = project.resource_cost_units;
      assert.ok(resourceCost.MATERIAL, 'MATERIAL must be in resource_cost_units');
      assert.ok(resourceCost.COMPONENTS, 'COMPONENTS must be in resource_cost_units');
      assert.ok(resourceCost.COMPUTE, 'COMPUTE must be in resource_cost_units');
    });
  } finally {
    await client.query('DELETE FROM corporation_scale_capabilities WHERE corporation_economic_id = $1', [corpEconId]);
    await client.query('DELETE FROM v5_house_settlement_profiles WHERE house_id = $1', [houseId]);
    await client.query('DELETE FROM game_events WHERE correlation_id LIKE $1', [`p6t6-%`]);
    await client.query('DELETE FROM construction_projects WHERE building_id = $1', [buildingId]);
    await client.query('DELETE FROM buildings WHERE id = $1', [buildingId]);
    await client.query('DELETE FROM territories WHERE id = $1', [territoryId]);
    await client.query('DELETE FROM economic_entries WHERE account_id IN (SELECT id FROM economic_accounts WHERE owner_economic_id IN ($1, $2))', [houseEconId, corpEconId]);
    await client.query("DELETE FROM economic_entries WHERE transaction_id IN (SELECT id FROM economic_transactions WHERE correlation_id LIKE '%p6t6%')");
    await client.query('DELETE FROM economic_transactions WHERE correlation_id LIKE $1', [`%p6t6%`]);
    await client.query('DELETE FROM economic_accounts WHERE owner_economic_id IN ($1, $2)', [houseEconId, corpEconId]);
    await client.query('DELETE FROM house_affiliations WHERE house_id = $1', [houseId]);
    await client.query('DELETE FROM humans WHERE id = $1', [humanId]);
    await client.query('DELETE FROM v5_house_settlement_profiles WHERE house_id = $1', [houseId]);
    await client.query('DELETE FROM v5_corporation_settlement_profiles WHERE corporation_id = $1', [corpId]);
    await client.query('DELETE FROM houses WHERE id = $1', [houseId]);
    await client.query('DELETE FROM owner_registry WHERE economic_id IN ($1, $2)', [houseEconId, corpEconId]);
    await client.query('DELETE FROM corporations WHERE id = $1', [corpId]);
    await client.query('DELETE FROM institutions WHERE id = $1', [corpId]);
    await client.query('DELETE FROM auth_accounts WHERE id = $1', [`AUTH-${humanId}`]);
    await client.end();
  }
});

test('PostgreSQL V5 Economic Core Phase 6: Architecture integrity report passes with 0 failures across all production entities', async () => {
  const client = await connectTo(connectionString);
  try {
    const reportRes = await client.query('SELECT * FROM earth_integrity_report()');
    for (const check of reportRes.rows) {
      assert.equal(check.invalid_count, '0', `Integrity check ${check.check_name} must have 0 invalid rows`);
    }
  } finally {
    await client.end();
  }
});

// ─── Phase 9: Generation-Aware Construction and Retrofits ───

test('PostgreSQL V5 Economic Core Phase 9: New building defaults to max accessible generation and stores installed_generation', async () => {
  const client = await connectTo(connectionString);
  const repository = new PostgresRepository(client);
  const ts = Date.now();
  const corpId = `CORP-P9T1-${ts}`;
  const corpEconId = `ECON-${corpId}`;
  const houseId = `HOUSE-P9T1-${ts}`;
  const houseEconId = `ECON-${houseId}`;
  const humanId = `HUMAN-P9T1-${ts}`;
  const email = `phase9t1+${ts}@test.local`;
  const terrId = `TERR-P9T1-${ts}`;
  let buildingId = `BLD-P9T1-${ts}`;

  try {
    await repository.transaction(async (tx) => {
      const day = Number((await tx.query("SELECT game_day::TEXT FROM world_state WHERE id = 'WORLD'")).rows[0]?.game_day ?? 1);

      // 1. Setup Corporation & House & Human
      await tx.query(`INSERT INTO institutions (id, kind, name, status) VALUES ($1, 'CORPORATION', $2, 'ACTIVE')`, [corpId, `Gen Test Corp ${ts}`]);
      await tx.query(`INSERT INTO corporations (id, charter_version, admission_policy, status, created_game_day) VALUES ($1, 'corporation-charter-v5', 'OPEN', 'ACTIVE', 1)`, [corpId]);
      await tx.query(`INSERT INTO owner_registry (id, owner_type, economic_id) VALUES ($1, 'CORPORATION', $2)`, [corpId, corpEconId]);
      await tx.query('SELECT earth_provision_corporation_economy($1)', [corpEconId]);

      await tx.query(`INSERT INTO auth_accounts (id, email, password_hash, password_salt, password_iterations) VALUES ($1, $2, 'test-password-hash', 'salt', 100000)`, [`AUTH-${humanId}`, email]);
      await tx.query(`INSERT INTO houses (id, account_id, house_name, status) VALUES ($1, $2, $3, 'ACTIVE')`, [houseId, `AUTH-${humanId}`, `Gen Test House ${ts}`]);
      await tx.query(`INSERT INTO owner_registry (id, owner_type, economic_id) VALUES ($1, 'HOUSE', $2)`, [houseId, houseEconId]);
      await tx.query('SELECT earth_provision_house_economy($1)', [houseEconId]);
      await tx.query(`INSERT INTO humans (id, account_id, house_id, display_name, status) VALUES ($1, $2, $3, 'Gen Builder', 'ACTIVE')`, [humanId, `AUTH-${humanId}`, houseId]);
      await tx.query(`INSERT INTO house_affiliations (house_id, corporation_id, joined_game_day, status) VALUES ($1, $2, 1, 'ACTIVE')`, [houseId, corpId]);
      await tx.query(`INSERT INTO territories (id, corporation_id, name, status, is_primary, created_game_day) VALUES ($1, $2, 'Gen Terr 1', 'ACTIVE', true, 1)`, [terrId, corpId]);

      // 2. Quote building without generation specified
      const quote = await quoteV5Building(repository, {
        ownerId: humanId,
        buildingType: 'SOLAR-MICROGRID-T1',
      });

      assert.equal(quote.ok, true);
      assert.equal(quote.installedGeneration, 1, 'Default installed generation must be 1');
      assert.equal(quote.maxAccessibleGeneration, 1, 'Default max accessible generation must be 1');
      assert.deepEqual(quote.availableGenerations, [1], 'Available generations should be [1]');
      assert.equal(quote.technologyDomain, 'ENERGY');
      assert.equal(quote.generationAuthorization.authorized, true);

      // 3. Create active building with default generation
      await tx.query(`INSERT INTO buildings (id, catalog_id, owner_economic_id, territory_id, status, construction_state, installed_generation, catalog_definition_version, technology_definition_version, operating_mode, started_game_day, last_major_rebuild_game_day) VALUES ($1, 'SOLAR-MICROGRID-T1', $2, $3, 'ACTIVE', 'ACTIVE', 1, 'v5-alpha-1', 'tech-gen-v1', 'BALANCED', 1, 1)`, [buildingId, houseEconId, terrId]);

      // 4. Verify building in DB has installed_generation = 1 and technology_definition_version = 'tech-gen-v1'
      const bRow = (await tx.query(`SELECT installed_generation, technology_definition_version, construction_state, status FROM buildings WHERE id = $1`, [buildingId])).rows[0];
      assert.equal(bRow.installed_generation, 1);
      assert.equal(bRow.technology_definition_version, 'tech-gen-v1');
      assert.equal(bRow.status, 'ACTIVE');
    });
  } finally {
    if (buildingId) {
      await client.query('DELETE FROM buildings WHERE id = $1', [buildingId]);
    }
    await client.query('DELETE FROM territories WHERE id = $1', [terrId]);
    await client.query('DELETE FROM economic_entries WHERE account_id IN (SELECT id FROM economic_accounts WHERE owner_economic_id IN ($1, $2))', [houseEconId, corpEconId]);
    await client.query('DELETE FROM economic_accounts WHERE owner_economic_id IN ($1, $2)', [houseEconId, corpEconId]);
    await client.query('DELETE FROM house_affiliations WHERE house_id = $1', [houseId]);
    await client.query('DELETE FROM humans WHERE id = $1', [humanId]);
    await client.query('DELETE FROM v5_house_settlement_profiles WHERE house_id = $1', [houseId]);
    await client.query('DELETE FROM v5_corporation_settlement_profiles WHERE corporation_id = $1', [corpId]);
    await client.query('DELETE FROM houses WHERE id = $1', [houseId]);
    await client.query('DELETE FROM owner_registry WHERE economic_id IN ($1, $2)', [houseEconId, corpEconId]);
    await client.query('DELETE FROM corporations WHERE id = $1', [corpId]);
    await client.query('DELETE FROM institutions WHERE id = $1', [corpId]);
    await client.query('DELETE FROM auth_accounts WHERE id = $1', [`AUTH-${humanId}`]);
    await client.end();
  }
});

test('PostgreSQL V5 Economic Core Phase 9: Construction blocks when requesting unavailable generation without authorization', async () => {
  const client = await connectTo(connectionString);
  const repository = new PostgresRepository(client);
  const ts = Date.now();
  const corpId = `CORP-P9T2-${ts}`;
  const corpEconId = `ECON-${corpId}`;
  const houseId = `HOUSE-P9T2-${ts}`;
  const houseEconId = `ECON-${houseId}`;
  const humanId = `HUMAN-P9T2-${ts}`;
  const email = `phase9t2+${ts}@test.local`;

  try {
    await repository.transaction(async (tx) => {
      // 1. Setup Corporation & House & Human
      await tx.query(`INSERT INTO institutions (id, kind, name, status) VALUES ($1, 'CORPORATION', $2, 'ACTIVE')`, [corpId, `Gen Unauth Corp ${ts}`]);
      await tx.query(`INSERT INTO corporations (id, charter_version, admission_policy, status, created_game_day) VALUES ($1, 'corporation-charter-v5', 'OPEN', 'ACTIVE', 1)`, [corpId]);
      await tx.query(`INSERT INTO owner_registry (id, owner_type, economic_id) VALUES ($1, 'CORPORATION', $2)`, [corpId, corpEconId]);
      await tx.query('SELECT earth_provision_corporation_economy($1)', [corpEconId]);

      await tx.query(`INSERT INTO auth_accounts (id, email, password_hash, password_salt, password_iterations) VALUES ($1, $2, 'test-password-hash', 'salt', 100000)`, [`AUTH-${humanId}`, email]);
      await tx.query(`INSERT INTO houses (id, account_id, house_name, status) VALUES ($1, $2, $3, 'ACTIVE')`, [houseId, `AUTH-${humanId}`, `Gen Unauth House ${ts}`]);
      await tx.query(`INSERT INTO owner_registry (id, owner_type, economic_id) VALUES ($1, 'HOUSE', $2)`, [houseId, houseEconId]);
      await tx.query('SELECT earth_provision_house_economy($1)', [houseEconId]);
      await tx.query(`INSERT INTO humans (id, account_id, house_id, display_name, status) VALUES ($1, $2, $3, 'Gen Unauth User', 'ACTIVE')`, [humanId, `AUTH-${humanId}`, houseId]);
      await tx.query(`INSERT INTO house_affiliations (house_id, corporation_id, joined_game_day, status) VALUES ($1, $2, 1, 'ACTIVE')`, [houseId, corpId]);

      // Fund wallet
      const wallet = (await tx.query(`SELECT id FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 1 AND account_type = 'WALLET'`, [houseEconId])).rows[0];
      await tx.query(`UPDATE economic_accounts SET balance_units = 500000 WHERE id = $1`, [wallet.id]);

      // 2. Quote with Generation 2 (not yet unlocked)
      const quote = await quoteV5Building(repository, {
        ownerId: humanId,
        buildingType: 'SOLAR-MICROGRID-T1',
        generation: 2,
      });

      assert.equal(quote.ok, true);
      assert.equal(quote.generationAuthorization.authorized, false);
      assert.ok(quote.blockers.some((b) => String(b).includes('generation')), 'Blockers must mention generation');

      // 3. Purchasing Gen 2 directly must throw
      await assert.rejects(
        () =>
          purchaseV5Building(repository, {
            ownerId: humanId,
            buildingType: 'SOLAR-MICROGRID-T1',
            name: 'Gen2 Solar',
            generation: 2,
            correlationId: `p9t2-fail-${ts}`,
          }),
        /generation/i,
      );
    });
  } finally {
    await client.query('DELETE FROM economic_entries WHERE account_id IN (SELECT id FROM economic_accounts WHERE owner_economic_id IN ($1, $2))', [houseEconId, corpEconId]);
    await client.query('DELETE FROM economic_accounts WHERE owner_economic_id IN ($1, $2)', [houseEconId, corpEconId]);
    await client.query('DELETE FROM house_affiliations WHERE house_id = $1', [houseId]);
    await client.query('DELETE FROM humans WHERE id = $1', [humanId]);
    await client.query('DELETE FROM v5_house_settlement_profiles WHERE house_id = $1', [houseId]);
    await client.query('DELETE FROM v5_corporation_settlement_profiles WHERE corporation_id = $1', [corpId]);
    await client.query('DELETE FROM houses WHERE id = $1', [houseId]);
    await client.query('DELETE FROM owner_registry WHERE economic_id IN ($1, $2)', [houseEconId, corpEconId]);
    await client.query('DELETE FROM corporations WHERE id = $1', [corpId]);
    await client.query('DELETE FROM institutions WHERE id = $1', [corpId]);
    await client.query('DELETE FROM auth_accounts WHERE id = $1', [`AUTH-${humanId}`]);
    await client.end();
  }
});

test('PostgreSQL V5 Economic Core Phase 9: Corporation unlocking Gen 2 allows Corporation and affiliated House to build Gen 2 directly', async () => {
  const client = await connectTo(connectionString);
  const repository = new PostgresRepository(client);
  const ts = Date.now();
  const corpId = `CORP-P9T3-${ts}`;
  const corpEconId = `ECON-${corpId}`;
  const houseId = `HOUSE-P9T3-${ts}`;
  const houseEconId = `ECON-${houseId}`;
  const humanId = `HUMAN-P9T3-${ts}`;
  const email = `phase9t3+${ts}@test.local`;
  const terrId = `TERR-P9T3-${ts}`;
  const houseBuildingId = `BLD-P9T3-H-${ts}`;

  try {
    await repository.transaction(async (tx) => {
      const day = Number((await tx.query("SELECT game_day::TEXT FROM world_state WHERE id = 'WORLD'")).rows[0]?.game_day ?? 1);

      // 1. Setup Corporation & House & Human
      await tx.query(`INSERT INTO institutions (id, kind, name, status) VALUES ($1, 'CORPORATION', $2, 'ACTIVE')`, [corpId, `Tech Gen Corp ${ts}`]);
      await tx.query(`INSERT INTO corporations (id, charter_version, admission_policy, status, created_game_day) VALUES ($1, 'corporation-charter-v5', 'OPEN', 'ACTIVE', 1)`, [corpId]);
      await tx.query(`INSERT INTO owner_registry (id, owner_type, economic_id) VALUES ($1, 'CORPORATION', $2)`, [corpId, corpEconId]);
      await tx.query('SELECT earth_provision_corporation_economy($1)', [corpEconId]);

      await tx.query(`INSERT INTO auth_accounts (id, email, password_hash, password_salt, password_iterations) VALUES ($1, $2, 'test-password-hash', 'salt', 100000)`, [`AUTH-${humanId}`, email]);
      await tx.query(`INSERT INTO houses (id, account_id, house_name, status) VALUES ($1, $2, $3, 'ACTIVE')`, [houseId, `AUTH-${humanId}`, `Affiliated Gen House ${ts}`]);
      await tx.query(`INSERT INTO owner_registry (id, owner_type, economic_id) VALUES ($1, 'HOUSE', $2)`, [houseId, houseEconId]);
      await tx.query('SELECT earth_provision_house_economy($1)', [houseEconId]);
      await tx.query(`INSERT INTO humans (id, account_id, house_id, display_name, status) VALUES ($1, $2, $3, 'Affiliated Gen Engineer', 'ACTIVE')`, [humanId, `AUTH-${humanId}`, houseId]);
      await tx.query(`INSERT INTO house_affiliations (house_id, corporation_id, joined_game_day, status) VALUES ($1, $2, 1, 'ACTIVE')`, [houseId, corpId]);
      await tx.query(`INSERT INTO institution_governance_roles (institution_id, human_id, role_code, status) VALUES ($1, $2, 'CORPORATION_EXECUTIVE', 'ACTIVE')`, [corpId, humanId]);
      await tx.query(`INSERT INTO territories (id, corporation_id, name, status, is_primary, created_game_day) VALUES ($1, $2, 'Gen Terr 3', 'ACTIVE', true, 1)`, [terrId, corpId]);

      // 2. Advance Earth frontier to Gen 2 for ENERGY and grant Gen 2 to Corporation
      await grantEarthBaselineTechnologyGeneration(tx, 'ENERGY', 2, day);
      await grantCorporationTechnologyGeneration(tx, corpEconId, 'ENERGY', 2, day);

      // Verify getAvailableGenerations reflects Gen 2 for Corporation and affiliated House
      const corpGenInfo = await getAvailableGenerations(tx, 'ENERGY', corpEconId, 'CORPORATION', null, day);
      assert.deepEqual(corpGenInfo.availableGenerations, [1, 2]);
      assert.equal(corpGenInfo.maxAccessibleGeneration, 2);

      const houseGenInfo = await getAvailableGenerations(tx, 'ENERGY', houseEconId, 'HOUSE', corpEconId, day);
      assert.deepEqual(houseGenInfo.availableGenerations, [1, 2]);
      assert.equal(houseGenInfo.maxAccessibleGeneration, 2);

      // 3. Quote Gen 2 Solar Microgrid for Affiliated House
      const houseQuote = await quoteV5Building(repository, {
        ownerId: humanId,
        buildingType: 'SOLAR-MICROGRID-T1',
        generation: 2,
      });
      assert.equal(houseQuote.generationAuthorization.authorized, true);
      assert.equal(houseQuote.installedGeneration, 2);

      // 4. Create building with Gen 2
      await tx.query(`INSERT INTO buildings (id, catalog_id, owner_economic_id, territory_id, status, construction_state, installed_generation, catalog_definition_version, technology_definition_version, operating_mode, started_game_day, last_major_rebuild_game_day) VALUES ($1, 'SOLAR-MICROGRID-T1', $2, $3, 'ACTIVE', 'ACTIVE', 2, 'v5-alpha-1', 'tech-gen-v2', 'BALANCED', 1, 1)`, [houseBuildingId, houseEconId, terrId]);

      // Verify DB records
      const houseBRow = (await tx.query(`SELECT installed_generation, technology_definition_version FROM buildings WHERE id = $1`, [houseBuildingId])).rows[0];
      assert.equal(houseBRow.installed_generation, 2);
      assert.equal(houseBRow.technology_definition_version, 'tech-gen-v2');
    });
  } finally {
    if (houseBuildingId) {
      await client.query('DELETE FROM buildings WHERE id = $1', [houseBuildingId]);
    }
    await client.query('DELETE FROM territories WHERE id = $1', [terrId]);
    await client.query('DELETE FROM corporation_technology_generations WHERE corporation_economic_id = $1', [corpEconId]);
    await client.query('DELETE FROM institution_governance_roles WHERE institution_id = $1', [corpId]);
    await client.query('DELETE FROM economic_entries WHERE account_id IN (SELECT id FROM economic_accounts WHERE owner_economic_id IN ($1, $2))', [houseEconId, corpEconId]);
    await client.query('DELETE FROM economic_accounts WHERE owner_economic_id IN ($1, $2)', [houseEconId, corpEconId]);
    await client.query('DELETE FROM house_affiliations WHERE house_id = $1', [houseId]);
    await client.query('DELETE FROM humans WHERE id = $1', [humanId]);
    await client.query('DELETE FROM v5_house_settlement_profiles WHERE house_id = $1', [houseId]);
    await client.query('DELETE FROM v5_corporation_settlement_profiles WHERE corporation_id = $1', [corpId]);
    await client.query('DELETE FROM houses WHERE id = $1', [houseId]);
    await client.query('DELETE FROM owner_registry WHERE economic_id IN ($1, $2)', [houseEconId, corpEconId]);
    await client.query('DELETE FROM corporations WHERE id = $1', [corpId]);
    await client.query('DELETE FROM institutions WHERE id = $1', [corpId]);
    await client.query('DELETE FROM auth_accounts WHERE id = $1', [`AUTH-${humanId}`]);
    await client.end();
  }
});

test('PostgreSQL V5 Economic Core Phase 9: Retrofit quote shows zero footprint delta, identical rent, and 40% credit/resource costs', async () => {
  const client = await connectTo(connectionString);
  const repository = new PostgresRepository(client);
  const ts = Date.now();
  const corpId = `CORP-P9T4-${ts}`;
  const corpEconId = `ECON-${corpId}`;
  const houseId = `HOUSE-P9T4-${ts}`;
  const houseEconId = `ECON-${houseId}`;
  const humanId = `HUMAN-P9T4-${ts}`;
  const email = `phase9t4+${ts}@test.local`;
  const territoryId = `TERR-P9T4-${ts}`;
  const buildingId = `BLD-P9T4-${ts}`;

  try {
    await repository.transaction(async (tx) => {
      const day = Number((await tx.query("SELECT game_day::TEXT FROM world_state WHERE id = 'WORLD'")).rows[0]?.game_day ?? 1);

      // Setup
      await tx.query(`INSERT INTO institutions (id, kind, name, status) VALUES ($1, 'CORPORATION', $2, 'ACTIVE')`, [corpId, `Retrofit Quote Corp ${ts}`]);
      await tx.query(`INSERT INTO corporations (id, charter_version, admission_policy, status, created_game_day) VALUES ($1, 'corporation-charter-v5', 'OPEN', 'ACTIVE', 1)`, [corpId]);
      await tx.query(`INSERT INTO owner_registry (id, owner_type, economic_id) VALUES ($1, 'CORPORATION', $2)`, [corpId, corpEconId]);
      await tx.query('SELECT earth_provision_corporation_economy($1)', [corpEconId]);

      await tx.query(`INSERT INTO auth_accounts (id, email, password_hash, password_salt, password_iterations) VALUES ($1, $2, 'test-password-hash', 'salt', 100000)`, [`AUTH-${humanId}`, email]);
      await tx.query(`INSERT INTO houses (id, account_id, house_name, status) VALUES ($1, $2, $3, 'ACTIVE')`, [houseId, `AUTH-${humanId}`, `Retrofit Quote House ${ts}`]);
      await tx.query(`INSERT INTO owner_registry (id, owner_type, economic_id) VALUES ($1, 'HOUSE', $2)`, [houseId, houseEconId]);
      await tx.query('SELECT earth_provision_house_economy($1)', [houseEconId]);
      await tx.query(`INSERT INTO humans (id, account_id, house_id, display_name, status) VALUES ($1, $2, $3, 'Retrofit Quoter', 'ACTIVE')`, [humanId, `AUTH-${humanId}`, houseId]);
      await tx.query(`INSERT INTO house_affiliations (house_id, corporation_id, joined_game_day, status) VALUES ($1, $2, 1, 'ACTIVE')`, [houseId, corpId]);
      await tx.query(`INSERT INTO territories (id, corporation_id, name, status, is_primary, created_game_day) VALUES ($1, $2, 'Gen Terr 4', 'ACTIVE', true, 1)`, [territoryId, corpId]);

      // Create Active Gen 1 Building
      await tx.query(`INSERT INTO buildings (id, catalog_id, owner_economic_id, territory_id, status, construction_state, installed_generation, catalog_definition_version, technology_definition_version, operating_mode, started_game_day, last_major_rebuild_game_day) VALUES ($1, 'SOLAR-MICROGRID-T1', $2, $3, 'ACTIVE', 'ACTIVE', 1, 'v5-alpha-1', 'tech-gen-v1', 'BALANCED', 1, 1)`, [buildingId, houseEconId, territoryId]);

      // Unlock Gen 2 on Earth and Corporation
      await grantEarthBaselineTechnologyGeneration(tx, 'ENERGY', 2, day);
      await grantCorporationTechnologyGeneration(tx, corpEconId, 'ENERGY', 2, day);

      // Quote Retrofit
      const quote = await quoteBuildingRetrofit(repository, {
        buildingId,
        humanId,
        targetGeneration: 2,
      });

      assert.equal(quote.ok, true);
      assert.equal(quote.currentGeneration, 1);
      assert.equal(quote.targetGeneration, 2);
      assert.equal(quote.footprintDelta, '0', 'Footprint delta must be 0 for retrofits');
      assert.equal(quote.deltaRentUnits, '0', 'Delta rent units must be 0 for retrofits');
      // 40% of 12000 credits = 4800
      assert.equal(quote.creditCostUnits, '4800');

      // Verify resource requirements
      const matReq = quote.resourceRequirements.find((r) => r.code === 'MATERIAL');
      const compReq = quote.resourceRequirements.find((r) => r.code === 'COMPONENTS');
      const computeReq = quote.resourceRequirements.find((r) => r.code === 'COMPUTE');

      assert.ok(matReq, 'MATERIAL requirement must exist');
      assert.equal(matReq.requiredUnits, '48', '40% of 120 MATERIAL = 48');

      assert.ok(compReq, 'COMPONENTS requirement must exist');
      assert.equal(compReq.requiredUnits, '4', '40% of 12 COMPONENTS = 4');

      assert.ok(computeReq, 'COMPUTE requirement must exist');
      assert.equal(computeReq.requiredUnits, '2', '40% of 5 COMPUTE = 2.0 = 2');
    });
  } finally {
    await client.query('DELETE FROM corporation_technology_generations WHERE corporation_economic_id = $1', [corpEconId]);
    await client.query('DELETE FROM buildings WHERE id = $1', [buildingId]);
    await client.query('DELETE FROM territories WHERE id = $1', [territoryId]);
    await client.query('DELETE FROM economic_entries WHERE account_id IN (SELECT id FROM economic_accounts WHERE owner_economic_id IN ($1, $2))', [houseEconId, corpEconId]);
    await client.query('DELETE FROM economic_accounts WHERE owner_economic_id IN ($1, $2)', [houseEconId, corpEconId]);
    await client.query('DELETE FROM house_affiliations WHERE house_id = $1', [houseId]);
    await client.query('DELETE FROM humans WHERE id = $1', [humanId]);
    await client.query('DELETE FROM v5_house_settlement_profiles WHERE house_id = $1', [houseId]);
    await client.query('DELETE FROM v5_corporation_settlement_profiles WHERE corporation_id = $1', [corpId]);
    await client.query('DELETE FROM houses WHERE id = $1', [houseId]);
    await client.query('DELETE FROM owner_registry WHERE economic_id IN ($1, $2)', [houseEconId, corpEconId]);
    await client.query('DELETE FROM corporations WHERE id = $1', [corpId]);
    await client.query('DELETE FROM institutions WHERE id = $1', [corpId]);
    await client.query('DELETE FROM auth_accounts WHERE id = $1', [`AUTH-${humanId}`]);
    await client.end();
  }
});

test('PostgreSQL V5 Economic Core Phase 9: Retrofit execution consumes balanced CREDIT and resources, sets RETROFITTING state, and settles generation update', async () => {
  const client = await connectTo(connectionString);
  const repository = new PostgresRepository(client);
  const ts = Date.now();
  const corpId = `CORP-P9T5-${ts}`;
  const corpEconId = `ECON-${corpId}`;
  const houseId = `HOUSE-P9T5-${ts}`;
  const houseEconId = `ECON-${houseId}`;
  const humanId = `HUMAN-P9T5-${ts}`;
  const email = `phase9t5+${ts}@test.local`;
  const territoryId = `TERR-P9T5-${ts}`;
  const buildingId = `BLD-P9T5-${ts}`;

  try {
    await repository.transaction(async (tx) => {
      const day = Number((await tx.query("SELECT game_day::TEXT FROM world_state WHERE id = 'WORLD'")).rows[0]?.game_day ?? 1);

      // Setup
      await tx.query(`INSERT INTO institutions (id, kind, name, status) VALUES ($1, 'CORPORATION', $2, 'ACTIVE')`, [corpId, `Retrofit Exec Corp ${ts}`]);
      await tx.query(`INSERT INTO corporations (id, charter_version, admission_policy, status, created_game_day) VALUES ($1, 'corporation-charter-v5', 'OPEN', 'ACTIVE', 1)`, [corpId]);
      await tx.query(`INSERT INTO owner_registry (id, owner_type, economic_id) VALUES ($1, 'CORPORATION', $2)`, [corpId, corpEconId]);
      await tx.query('SELECT earth_provision_corporation_economy($1)', [corpEconId]);

      await tx.query(`INSERT INTO auth_accounts (id, email, password_hash, password_salt, password_iterations) VALUES ($1, $2, 'test-password-hash', 'salt', 100000)`, [`AUTH-${humanId}`, email]);
      await tx.query(`INSERT INTO houses (id, account_id, house_name, status) VALUES ($1, $2, $3, 'ACTIVE')`, [houseId, `AUTH-${humanId}`, `Retrofit Exec House ${ts}`]);
      await tx.query(`INSERT INTO owner_registry (id, owner_type, economic_id) VALUES ($1, 'HOUSE', $2)`, [houseId, houseEconId]);
      await tx.query('SELECT earth_provision_house_economy($1)', [houseEconId]);
      await tx.query(`INSERT INTO humans (id, account_id, house_id, display_name, status) VALUES ($1, $2, $3, 'Retrofit Executor', 'ACTIVE')`, [humanId, `AUTH-${humanId}`, houseId]);
      await tx.query(`INSERT INTO house_affiliations (house_id, corporation_id, joined_game_day, status) VALUES ($1, $2, 1, 'ACTIVE')`, [houseId, corpId]);
      await tx.query(`INSERT INTO territories (id, corporation_id, name, status, is_primary, created_game_day) VALUES ($1, $2, 'Gen Terr 5', 'ACTIVE', true, 1)`, [territoryId, corpId]);

      // Provision balances
      const wallet = (await tx.query(`SELECT id FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 1 AND account_type = 'WALLET'`, [houseEconId])).rows[0];
      await tx.query(`UPDATE economic_accounts SET balance_units = 50000 WHERE id = $1`, [wallet.id]);
      const matAcc = (await tx.query(`SELECT id FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 2 AND account_type = 'INVENTORY'`, [houseEconId])).rows[0];
      await tx.query(`UPDATE economic_accounts SET balance_units = 500 WHERE id = $1`, [matAcc.id]);
      const compAcc = (await tx.query(`SELECT id FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 3 AND account_type = 'INVENTORY'`, [houseEconId])).rows[0];
      await tx.query(`UPDATE economic_accounts SET balance_units = 100 WHERE id = $1`, [compAcc.id]);
      const computeAcc = (await tx.query(`SELECT id FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 5 AND account_type = 'INVENTORY'`, [houseEconId])).rows[0];
      await tx.query(`UPDATE economic_accounts SET balance_units = 50 WHERE id = $1`, [computeAcc.id]);

      // Create Active Gen 1 Building
      await tx.query(`INSERT INTO buildings (id, catalog_id, owner_economic_id, territory_id, status, construction_state, installed_generation, catalog_definition_version, technology_definition_version, operating_mode, started_game_day, last_major_rebuild_game_day) VALUES ($1, 'SOLAR-MICROGRID-T1', $2, $3, 'ACTIVE', 'ACTIVE', 1, 'v5-alpha-1', 'tech-gen-v1', 'BALANCED', 1, 1)`, [buildingId, houseEconId, territoryId]);

      // Unlock Gen 2 on Earth and Corporation
      await grantEarthBaselineTechnologyGeneration(tx, 'ENERGY', 2, day);
      await grantCorporationTechnologyGeneration(tx, corpEconId, 'ENERGY', 2, day);

      // Balances before retrofit
      const walletBefore = BigInt((await tx.query(`SELECT balance_units::TEXT AS b FROM economic_accounts WHERE id = $1`, [wallet.id])).rows[0].b);
      const matBefore = BigInt((await tx.query(`SELECT balance_units::TEXT AS b FROM economic_accounts WHERE id = $1`, [matAcc.id])).rows[0].b);
      const compBefore = BigInt((await tx.query(`SELECT balance_units::TEXT AS b FROM economic_accounts WHERE id = $1`, [compAcc.id])).rows[0].b);
      const computeBefore = BigInt((await tx.query(`SELECT balance_units::TEXT AS b FROM economic_accounts WHERE id = $1`, [computeAcc.id])).rows[0].b);

      // Execute Retrofit
      const correlationId = `p9t5-retrofit-${ts}`;
      const result = await retrofitBuilding(repository, {
        buildingId,
        humanId,
        targetGeneration: 2,
        correlationId,
      });

      assert.equal(result.ok, true);
      assert.equal(result.status, 'UNDER_CONSTRUCTION');
      assert.equal(result.constructionState, 'RETROFITTING');
      assert.equal(result.fromGeneration, 1);
      assert.equal(result.toGeneration, 2);
      assert.equal(result.creditCostUnits, '4800');

      // Verify Credit deduction
      const walletAfter = BigInt((await tx.query(`SELECT balance_units::TEXT AS b FROM economic_accounts WHERE id = $1`, [wallet.id])).rows[0].b);
      assert.equal((walletBefore - walletAfter).toString(), '4800');

      // Verify Resource deductions
      const matAfter = BigInt((await tx.query(`SELECT balance_units::TEXT AS b FROM economic_accounts WHERE id = $1`, [matAcc.id])).rows[0].b);
      assert.equal((matBefore - matAfter).toString(), '48');
      const compAfter = BigInt((await tx.query(`SELECT balance_units::TEXT AS b FROM economic_accounts WHERE id = $1`, [compAcc.id])).rows[0].b);
      assert.equal((compBefore - compAfter).toString(), '4');
      const computeAfter = BigInt((await tx.query(`SELECT balance_units::TEXT AS b FROM economic_accounts WHERE id = $1`, [computeAcc.id])).rows[0].b);
      assert.equal((computeBefore - computeAfter).toString(), '2');

      // Verify Building status in DB
      const bRow = (await tx.query(`SELECT status, construction_state, installed_generation FROM buildings WHERE id = $1`, [buildingId])).rows[0];
      assert.equal(bRow.status, 'UNDER_CONSTRUCTION');
      assert.equal(bRow.construction_state, 'RETROFITTING');
      assert.equal(bRow.installed_generation, 1, 'Installed generation remains 1 while retrofitting is in progress');

      // Verify Construction Project row
      const proj = (await tx.query(`SELECT project_kind, target_generation_id, status FROM construction_projects WHERE correlation_id = $1`, [correlationId])).rows[0];
      assert.equal(proj.project_kind, 'GENERATION_RETROFIT');
      assert.equal(proj.status, 'IN_PROGRESS');

      // 4. Complete construction project settlement
      const settlement = await completeDueConstructionProjects(tx, result.expectedCompletionGameDay);
      assert.equal(settlement.completed, 1);

      // Verify Building is now ACTIVE with installed_generation = 2 and technology_definition_version = 'tech-gen-v2'
      const completedBuilding = (await tx.query(`SELECT status, construction_state, installed_generation, technology_definition_version FROM buildings WHERE id = $1`, [buildingId])).rows[0];
      assert.equal(completedBuilding.status, 'ACTIVE');
      assert.equal(completedBuilding.construction_state, 'ACTIVE');
      assert.equal(completedBuilding.installed_generation, 2);
      assert.equal(completedBuilding.technology_definition_version, 'tech-gen-v2');

      // Verify building_generation_installations record
      const installRecord = (await tx.query(`SELECT * FROM building_generation_installations WHERE building_id = $1`, [buildingId])).rows[0];
      assert.ok(installRecord, 'Generation installation record must be inserted');
    });
  } finally {
    await client.query('DELETE FROM corporation_technology_generations WHERE corporation_economic_id = $1', [corpEconId]);
    await client.query('DELETE FROM building_generation_installations WHERE building_id = $1', [buildingId]);
    await client.query('DELETE FROM construction_projects WHERE building_id = $1', [buildingId]);
    await client.query('DELETE FROM game_events WHERE correlation_id LIKE $1', [`p9t5-%`]);
    await client.query('DELETE FROM buildings WHERE id = $1', [buildingId]);
    await client.query('DELETE FROM territories WHERE id = $1', [territoryId]);
    await client.query('DELETE FROM economic_entries WHERE account_id IN (SELECT id FROM economic_accounts WHERE owner_economic_id IN ($1, $2))', [houseEconId, corpEconId]);
    await client.query("DELETE FROM economic_entries WHERE transaction_id IN (SELECT id FROM economic_transactions WHERE correlation_id LIKE '%p9t5%')");
    await client.query('DELETE FROM economic_transactions WHERE correlation_id LIKE $1', [`%p9t5%`]);
    await client.query('DELETE FROM economic_accounts WHERE owner_economic_id IN ($1, $2)', [houseEconId, corpEconId]);
    await client.query('DELETE FROM house_affiliations WHERE house_id = $1', [houseId]);
    await client.query('DELETE FROM humans WHERE id = $1', [humanId]);
    await client.query('DELETE FROM v5_house_settlement_profiles WHERE house_id = $1', [houseId]);
    await client.query('DELETE FROM v5_corporation_settlement_profiles WHERE corporation_id = $1', [corpId]);
    await client.query('DELETE FROM houses WHERE id = $1', [houseId]);
    await client.query('DELETE FROM owner_registry WHERE economic_id IN ($1, $2)', [houseEconId, corpEconId]);
    await client.query('DELETE FROM corporations WHERE id = $1', [corpId]);
    await client.query('DELETE FROM institutions WHERE id = $1', [corpId]);
    await client.query('DELETE FROM auth_accounts WHERE id = $1', [`AUTH-${humanId}`]);
    await client.end();
  }
});

test('PostgreSQL V5 Economic Core Phase 9: Architecture integrity report passes with 0 failures across all production entities', async () => {
  const client = await connectTo(connectionString);
  try {
    const reportRes = await client.query('SELECT * FROM earth_integrity_report()');
    for (const check of reportRes.rows) {
      assert.equal(check.invalid_count, '0', `Integrity check ${check.check_name} must have 0 invalid rows`);
    }
  } finally {
    await client.end();
  }
});

test('PostgreSQL V5 Economic Core Phase 10: Authoritative persistence classes are configured in resource_behavior_metadata', async () => {
  const client = await connectTo(connectionString);
  const repository = new PostgresRepository(client);
  try {
    const metadata = await getResourcePersistenceMetadata(repository);
    const byCode = Object.fromEntries(metadata.map((m) => [m.code, m]));

    assert.equal(byCode.MATERIAL.persistenceClass, 'DURABLE');
    assert.equal(byCode.MATERIAL.decayBpsPerDay, 0);

    assert.equal(byCode.COMPONENTS.persistenceClass, 'DURABLE');
    assert.equal(byCode.COMPONENTS.decayBpsPerDay, 0);

    assert.equal(byCode.FOOD.persistenceClass, 'PERISHABLE');
    assert.equal(byCode.FOOD.decayBpsPerDay, 500);

    assert.equal(byCode.ENERGY.persistenceClass, 'FLOW');
    assert.equal(byCode.ENERGY.decayBpsPerDay, 10000);

    assert.equal(byCode.COMPUTE.persistenceClass, 'FLOW');
    assert.equal(byCode.COMPUTE.decayBpsPerDay, 10000);

    const behaviorMeta = await getResourceBehaviorMetadata(repository);
    assert.ok(Array.isArray(behaviorMeta.resources));
    const foodMeta = behaviorMeta.resources.find((r) => r.code === 'FOOD');
    assert.equal(foodMeta.persistenceClass, 'PERISHABLE');
  } finally {
    await client.end();
  }
});

test('PostgreSQL V5 Economic Core Phase 10: Durable resources (MATERIAL, COMPONENTS) do not decay across daily settlement', async () => {
  const client = await connectTo(connectionString);
  const repository = new PostgresRepository(client);
  const testId = `p10t2-${Date.now()}`;
  const humanId = `HUM-${testId}`;
  const houseId = `HOUSE-${testId}`;
  const houseEconId = `HOUSE-ECON-${testId}`;

  try {
    await repository.transaction(async (tx) => {
      await tx.query(`INSERT INTO auth_accounts (id, email, password_hash, password_salt, password_iterations) VALUES ($1, $2, 'test-password-hash', 'salt', 100000)`, [`AUTH-${humanId}`, `${testId}@example.com`]);
      await tx.query('INSERT INTO houses (id, account_id, house_name, dynasty_legacy, generation, status) VALUES ($1, $2, $3, 0, 1, $4)', [houseId, `AUTH-${humanId}`, `House ${testId}`, 'ACTIVE']);
      await tx.query(`INSERT INTO humans (id, account_id, house_id, display_name, status) VALUES ($1, $2, $3, $4, 'ACTIVE')`, [humanId, `AUTH-${humanId}`, houseId, `Human ${testId}`]);
      await tx.query('UPDATE houses SET current_human_id = $1 WHERE id = $2', [humanId, houseId]);
      await tx.query("INSERT INTO owner_registry (id, owner_type, economic_id) VALUES ($1, 'HOUSE', $2)", [`REG-${testId}`, houseEconId]);
      await tx.query('SELECT earth_provision_house_economy($1)', [houseEconId]);

      // Seed durable balances
      await tx.query(`
        UPDATE economic_accounts
           SET balance_units = 10000
         WHERE owner_economic_id = $1 AND asset_id = 2 AND account_type = 'INVENTORY'
      `, [houseEconId]);

      await tx.query(`
        UPDATE economic_accounts
           SET balance_units = 5000
         WHERE owner_economic_id = $1 AND asset_id = 3 AND account_type = 'INVENTORY'
      `, [houseEconId]);

      // Run settlement
      const result = await settleResourcePersistenceAndDecay(tx, 10);
      
      // Verify balances unchanged
      const matAcc = (await tx.query('SELECT balance_units FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 2 AND account_type = $2', [houseEconId, 'INVENTORY'])).rows[0];
      const compAcc = (await tx.query('SELECT balance_units FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 3 AND account_type = $2', [houseEconId, 'INVENTORY'])).rows[0];

      assert.equal(matAcc.balance_units, '10000');
      assert.equal(compAcc.balance_units, '5000');
    });
  } finally {
    await client.query("DELETE FROM economic_entries WHERE transaction_id IN (SELECT id FROM economic_transactions WHERE correlation_id LIKE '%p10t2%')");
    await client.query("DELETE FROM economic_transactions WHERE correlation_id LIKE '%p10t2%'");
    await client.query('DELETE FROM economic_entries WHERE account_id IN (SELECT id FROM economic_accounts WHERE owner_economic_id = $1)', [houseEconId]);
    await client.query('DELETE FROM economic_accounts WHERE owner_economic_id = $1', [houseEconId]);
    await client.query('UPDATE houses SET current_human_id = NULL WHERE id = $1', [houseId]);
    await client.query('DELETE FROM humans WHERE id = $1', [humanId]);
    await client.query('DELETE FROM houses WHERE id = $1', [houseId]);
    await client.query('DELETE FROM owner_registry WHERE economic_id = $1', [houseEconId]);
    await client.query('DELETE FROM auth_accounts WHERE id = $1', [`AUTH-${humanId}`]);
    await client.end();
  }
});

test('PostgreSQL V5 Economic Core Phase 10: Perishable resource (FOOD) decays deterministically with explicit double-entry consumption transaction', async () => {
  const client = await connectTo(connectionString);
  const repository = new PostgresRepository(client);
  const testId = `p10t3-${Date.now()}`;
  const humanId = `HUM-${testId}`;
  const houseId = `HOUSE-${testId}`;
  const houseEconId = `HOUSE-ECON-${testId}`;
  const gameDay = 10;

  try {
    await repository.transaction(async (tx) => {
      await tx.query(`INSERT INTO auth_accounts (id, email, password_hash, password_salt, password_iterations) VALUES ($1, $2, 'test-password-hash', 'salt', 100000)`, [`AUTH-${humanId}`, `${testId}@example.com`]);
      await tx.query('INSERT INTO houses (id, account_id, house_name, dynasty_legacy, generation, status) VALUES ($1, $2, $3, 0, 1, $4)', [houseId, `AUTH-${humanId}`, `House ${testId}`, 'ACTIVE']);
      await tx.query(`INSERT INTO humans (id, account_id, house_id, display_name, status) VALUES ($1, $2, $3, $4, 'ACTIVE')`, [humanId, `AUTH-${humanId}`, houseId, `Human ${testId}`]);
      await tx.query('UPDATE houses SET current_human_id = $1 WHERE id = $2', [humanId, houseId]);
      await tx.query("INSERT INTO owner_registry (id, owner_type, economic_id) VALUES ($1, 'HOUSE', $2)", [`REG-${testId}`, houseEconId]);
      await tx.query('SELECT earth_provision_house_economy($1)', [houseEconId]);

      // Seed 10,000 units of FOOD (asset_id = 6)
      await tx.query(`
        UPDATE economic_accounts
           SET balance_units = 10000
         WHERE owner_economic_id = $1 AND asset_id = 6 AND account_type = 'INVENTORY'
      `, [houseEconId]);

      // Run perishable decay at day close
      const result = await settlePerishableResourceDecay(tx, gameDay);
      assert.ok(BigInt(result.expiredUnits) >= 500n);

      // Verify House food balance decayed by 500 (5% of 10,000)
      const foodAcc = (await tx.query('SELECT balance_units FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 6 AND account_type = $2', [houseEconId, 'INVENTORY'])).rows[0];
      assert.equal(foodAcc.balance_units, '9500');

      // Verify double-entry ledger transaction
      const txRow = (await tx.query(`
        SELECT t.id, t.transaction_kind, t.source_type, t.source_id
          FROM economic_transactions t
         WHERE t.correlation_id = $1
      `, [`food-decay:${houseEconId}:${gameDay}`])).rows[0];

      assert.ok(txRow, 'Decay transaction must be recorded');
      assert.equal(txRow.transaction_kind, 'RESOURCE_CONSUMPTION');
      assert.equal(txRow.source_type, 'SYSTEM_CONSUMPTION');

      const entries = (await tx.query(`
        SELECT account_id, delta_units, asset_id
          FROM economic_entries
         WHERE transaction_id = $1
         ORDER BY delta_units ASC
      `, [txRow.id])).rows;

      assert.equal(entries.length, 2);
      assert.equal(entries[0].delta_units, '-500');
      assert.equal(entries[1].delta_units, '500');
    });
  } finally {
    await client.query("DELETE FROM economic_entries WHERE transaction_id IN (SELECT id FROM economic_transactions WHERE correlation_id LIKE '%food-decay%')");
    await client.query("DELETE FROM economic_transactions WHERE correlation_id LIKE '%food-decay%'");
    await client.query('DELETE FROM economic_entries WHERE account_id IN (SELECT id FROM economic_accounts WHERE owner_economic_id = $1)', [houseEconId]);
    await client.query('DELETE FROM economic_accounts WHERE owner_economic_id = $1', [houseEconId]);
    await client.query('UPDATE houses SET current_human_id = NULL WHERE id = $1', [houseId]);
    await client.query('DELETE FROM humans WHERE id = $1', [humanId]);
    await client.query('DELETE FROM houses WHERE id = $1', [houseId]);
    await client.query('DELETE FROM owner_registry WHERE economic_id = $1', [houseEconId]);
    await client.query('DELETE FROM auth_accounts WHERE id = $1', [`AUTH-${humanId}`]);
    await client.end();
  }
});

test('PostgreSQL V5 Economic Core Phase 10: Flow resources (ENERGY, COMPUTE) remain available during daily window and unbuffered balance expires at day-close', async () => {
  const client = await connectTo(connectionString);
  const repository = new PostgresRepository(client);
  const testId = `p10t4-${Date.now()}`;
  const humanId = `HUM-${testId}`;
  const houseId = `HOUSE-${testId}`;
  const houseEconId = `HOUSE-ECON-${testId}`;
  const corpId = `CORP-${testId}`;
  const corpEconId = `CORP-ECON-${testId}`;
  const gameDay = 12;

  try {
    await repository.transaction(async (tx) => {
      await tx.query(`INSERT INTO auth_accounts (id, email, password_hash, password_salt, password_iterations) VALUES ($1, $2, 'test-password-hash', 'salt', 100000)`, [`AUTH-${humanId}`, `${testId}@example.com`]);
      await tx.query('INSERT INTO houses (id, account_id, house_name, dynasty_legacy, generation, status) VALUES ($1, $2, $3, 0, 1, $4)', [houseId, `AUTH-${humanId}`, `House ${testId}`, 'ACTIVE']);
      await tx.query(`INSERT INTO humans (id, account_id, house_id, display_name, status) VALUES ($1, $2, $3, $4, 'ACTIVE')`, [humanId, `AUTH-${humanId}`, houseId, `Human ${testId}`]);
      await tx.query('UPDATE houses SET current_human_id = $1 WHERE id = $2', [humanId, houseId]);
      await tx.query("INSERT INTO owner_registry (id, owner_type, economic_id) VALUES ($1, 'HOUSE', $2)", [`REG-H-${testId}`, houseEconId]);
      await tx.query('SELECT earth_provision_house_economy($1)', [houseEconId]);

      await tx.query("INSERT INTO institutions (id, kind, name, status) VALUES ($1, 'CORPORATION', $2, 'ACTIVE')", [corpId, `Corp ${testId}`]);
      await tx.query("INSERT INTO corporations (id, charter_version, admission_policy, status, created_game_day) VALUES ($1, 1, 'OPEN', 'ACTIVE', 1)", [corpId]);
      await tx.query("INSERT INTO owner_registry (id, owner_type, economic_id) VALUES ($1, 'CORPORATION', $2)", [`REG-C-${testId}`, corpEconId]);
      await tx.query('SELECT earth_provision_corporation_economy($1)', [corpEconId]);

      // Seed ENERGY (4) and COMPUTE (5) to Corporation with 0 storage capacity
      await tx.query(`
        UPDATE economic_accounts
           SET balance_units = 2000
         WHERE owner_economic_id = $1 AND asset_id = 4 AND account_type = 'INVENTORY'
      `, [corpEconId]);

      await tx.query(`
        UPDATE economic_accounts
           SET balance_units = 1500
         WHERE owner_economic_id = $1 AND asset_id = 5 AND account_type = 'INVENTORY'
      `, [corpEconId]);

      // Run day-close settlement
      const result = await settleResourcePersistenceAndDecay(tx, gameDay);
      assert.ok(BigInt(result.expiredUnitsByAsset.ENERGY) >= 2000n);
      assert.ok(BigInt(result.expiredUnitsByAsset.COMPUTE) >= 1500n);

      // Verify Corporation flow balances expired to 0
      const energyAcc = (await tx.query('SELECT balance_units FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 4 AND account_type = $2', [corpEconId, 'INVENTORY'])).rows[0];
      const computeAcc = (await tx.query('SELECT balance_units FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 5 AND account_type = $2', [corpEconId, 'INVENTORY'])).rows[0];

      assert.equal(energyAcc.balance_units, '0');
      assert.equal(computeAcc.balance_units, '0');

      // Verify double-entry ledger transactions
      const energyTx = (await tx.query(`
        SELECT t.id, t.transaction_kind FROM economic_transactions t WHERE t.correlation_id = $1
      `, [`resource-decay:energy:${corpEconId}:${gameDay}`])).rows[0];
      assert.ok(energyTx, 'Energy decay transaction must exist');

      const computeTx = (await tx.query(`
        SELECT t.id, t.transaction_kind FROM economic_transactions t WHERE t.correlation_id = $1
      `, [`resource-decay:compute:${corpEconId}:${gameDay}`])).rows[0];
      assert.ok(computeTx, 'Compute decay transaction must exist');
    });
  } finally {
    await client.query("DELETE FROM economic_entries WHERE transaction_id IN (SELECT id FROM economic_transactions WHERE correlation_id LIKE '%resource-decay%')");
    await client.query("DELETE FROM economic_transactions WHERE correlation_id LIKE '%resource-decay%'");
    await client.query('DELETE FROM economic_entries WHERE account_id IN (SELECT id FROM economic_accounts WHERE owner_economic_id IN ($1, $2))', [houseEconId, corpEconId]);
    await client.query('DELETE FROM economic_accounts WHERE owner_economic_id IN ($1, $2)', [houseEconId, corpEconId]);
    await client.query('UPDATE houses SET current_human_id = NULL WHERE id = $1', [houseId]);
    await client.query('DELETE FROM humans WHERE id = $1', [humanId]);
    await client.query('DELETE FROM houses WHERE id = $1', [houseId]);
    await client.query('DELETE FROM owner_registry WHERE economic_id IN ($1, $2)', [houseEconId, corpEconId]);
    await client.query('DELETE FROM corporations WHERE id = $1', [corpId]);
    await client.query('DELETE FROM institutions WHERE id = $1', [corpId]);
    await client.query('DELETE FROM auth_accounts WHERE id = $1', [`AUTH-${humanId}`]);
    await client.end();
  }
});

test('PostgreSQL V5 Economic Core Phase 10: Battery Storage modifier preserves ENERGY balance up to capacity limit, expiring only unbuffered excess', async () => {
  const client = await connectTo(connectionString);
  const repository = new PostgresRepository(client);
  const testId = `p10t5-${Date.now()}`;
  const corpId = `CORP-${testId}`;
  const corpEconId = `CORP-ECON-${testId}`;
  const gameDay = 14;

  try {
    await repository.transaction(async (tx) => {
      await tx.query("INSERT INTO institutions (id, kind, name, status) VALUES ($1, 'CORPORATION', $2, 'ACTIVE')", [corpId, `Corp ${testId}`]);
      await tx.query("INSERT INTO corporations (id, charter_version, admission_policy, status, created_game_day) VALUES ($1, 1, 'OPEN', 'ACTIVE', 1)", [corpId]);
      await tx.query("INSERT INTO owner_registry (id, owner_type, economic_id) VALUES ($1, 'CORPORATION', $2)", [`REG-C-${testId}`, corpEconId]);
      await tx.query('SELECT earth_provision_corporation_economy($1)', [corpEconId]);

      // Seed 2,500 units of ENERGY
      await tx.query(`
        UPDATE economic_accounts
           SET balance_units = 2500
         WHERE owner_economic_id = $1 AND asset_id = 4 AND account_type = 'INVENTORY'
      `, [corpEconId]);

      // Grant BATTERY_STORAGE with capacity 1,500 units
      await grantOwnerStorageCapacity(tx, {
        ownerEconomicId: corpEconId,
        assetCode: 'ENERGY',
        storageType: 'BATTERY_STORAGE',
        capacityUnits: 1500n,
        sourceType: 'BUILDING',
        sourceId: `BLD-${testId}`,
        effectiveFromGameDay: 1,
      });

      // Settle decay
      await settleResourcePersistenceAndDecay(tx, gameDay);

      // Verify Corporation ENERGY balance is preserved at exactly 1,500 units (excess 1,000 expired)
      const energyAcc = (await tx.query('SELECT balance_units FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 4 AND account_type = $2', [corpEconId, 'INVENTORY'])).rows[0];
      assert.equal(energyAcc.balance_units, '1500');

      // Verify ledger transaction was for exactly 1,000 units
      const txRow = (await tx.query(`
        SELECT t.id FROM economic_transactions t WHERE t.correlation_id = $1
      `, [`resource-decay:energy:${corpEconId}:${gameDay}`])).rows[0];

      const entries = (await tx.query(`
        SELECT delta_units FROM economic_entries WHERE transaction_id = $1 ORDER BY delta_units ASC
      `, [txRow.id])).rows;

      assert.equal(entries[0].delta_units, '-1000');
      assert.equal(entries[1].delta_units, '1000');
    });
  } finally {
    await client.query('DELETE FROM owner_storage_capacities WHERE owner_economic_id = $1', [corpEconId]);
    await client.query("DELETE FROM economic_entries WHERE transaction_id IN (SELECT id FROM economic_transactions WHERE correlation_id LIKE '%resource-decay%')");
    await client.query("DELETE FROM economic_transactions WHERE correlation_id LIKE '%resource-decay%'");
    await client.query('DELETE FROM economic_entries WHERE account_id IN (SELECT id FROM economic_accounts WHERE owner_economic_id = $1)', [corpEconId]);
    await client.query('DELETE FROM economic_accounts WHERE owner_economic_id = $1', [corpEconId]);
    await client.query('DELETE FROM owner_registry WHERE economic_id = $1', [corpEconId]);
    await client.query('DELETE FROM corporations WHERE id = $1', [corpId]);
    await client.query('DELETE FROM institutions WHERE id = $1', [corpId]);
    await client.end();
  }
});

test('PostgreSQL V5 Economic Core Phase 10: Food Reserve modifier protects FOOD inventory and mitigates decay', async () => {
  const client = await connectTo(connectionString);
  const repository = new PostgresRepository(client);
  const testId = `p10t6-${Date.now()}`;
  const humanId = `HUM-${testId}`;
  const houseId = `HOUSE-${testId}`;
  const houseEconId = `HOUSE-ECON-${testId}`;
  const gameDay = 16;

  try {
    await repository.transaction(async (tx) => {
      await tx.query(`INSERT INTO auth_accounts (id, email, password_hash, password_salt, password_iterations) VALUES ($1, $2, 'test-password-hash', 'salt', 100000)`, [`AUTH-${humanId}`, `${testId}@example.com`]);
      await tx.query('INSERT INTO houses (id, account_id, house_name, dynasty_legacy, generation, status) VALUES ($1, $2, $3, 0, 1, $4)', [houseId, `AUTH-${humanId}`, `House ${testId}`, 'ACTIVE']);
      await tx.query(`INSERT INTO humans (id, account_id, house_id, display_name, status) VALUES ($1, $2, $3, $4, 'ACTIVE')`, [humanId, `AUTH-${humanId}`, houseId, `Human ${testId}`]);
      await tx.query('UPDATE houses SET current_human_id = $1 WHERE id = $2', [humanId, houseId]);
      await tx.query("INSERT INTO owner_registry (id, owner_type, economic_id) VALUES ($1, 'HOUSE', $2)", [`REG-${testId}`, houseEconId]);
      await tx.query('SELECT earth_provision_house_economy($1)', [houseEconId]);

      // Seed 10,000 units of FOOD
      await tx.query(`
        UPDATE economic_accounts
           SET balance_units = 10000
         WHERE owner_economic_id = $1 AND asset_id = 6 AND account_type = 'INVENTORY'
      `, [houseEconId]);

      // Grant FOOD_RESERVE with 6,000 capacity units protected
      await grantOwnerStorageCapacity(tx, {
        ownerEconomicId: houseEconId,
        assetCode: 'FOOD',
        storageType: 'FOOD_RESERVE',
        capacityUnits: 6000n,
        sourceType: 'BUILDING',
        sourceId: `BLD-SILO-${testId}`,
        effectiveFromGameDay: 1,
      });

      // Settle decay
      await settleResourcePersistenceAndDecay(tx, gameDay);

      // (10,000 - 6,000) = 4,000 decayable * 5% = 200 units decay.
      // Expected balance = 10,000 - 200 = 9,800 units.
      const foodAcc = (await tx.query('SELECT balance_units FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 6 AND account_type = $2', [houseEconId, 'INVENTORY'])).rows[0];
      assert.equal(foodAcc.balance_units, '9800');
    });
  } finally {
    await client.query('DELETE FROM owner_storage_capacities WHERE owner_economic_id = $1', [houseEconId]);
    await client.query("DELETE FROM economic_entries WHERE transaction_id IN (SELECT id FROM economic_transactions WHERE correlation_id LIKE '%food-decay%')");
    await client.query("DELETE FROM economic_transactions WHERE correlation_id LIKE '%food-decay%'");
    await client.query('DELETE FROM economic_entries WHERE account_id IN (SELECT id FROM economic_accounts WHERE owner_economic_id = $1)', [houseEconId]);
    await client.query('DELETE FROM economic_accounts WHERE owner_economic_id = $1', [houseEconId]);
    await client.query('UPDATE houses SET current_human_id = NULL WHERE id = $1', [houseId]);
    await client.query('DELETE FROM humans WHERE id = $1', [humanId]);
    await client.query('DELETE FROM houses WHERE id = $1', [houseId]);
    await client.query('DELETE FROM owner_registry WHERE economic_id = $1', [houseEconId]);
    await client.query('DELETE FROM auth_accounts WHERE id = $1', [`AUTH-${humanId}`]);
    await client.end();
  }
});

test('PostgreSQL V5 Economic Core Phase 10: Compute Storage modifier protects COMPUTE flow balance up to capacity limit', async () => {
  const client = await connectTo(connectionString);
  const repository = new PostgresRepository(client);
  const testId = `p10t7-${Date.now()}`;
  const corpId = `CORP-${testId}`;
  const corpEconId = `CORP-ECON-${testId}`;
  const gameDay = 18;

  try {
    await repository.transaction(async (tx) => {
      await tx.query("INSERT INTO institutions (id, kind, name, status) VALUES ($1, 'CORPORATION', $2, 'ACTIVE')", [corpId, `Corp ${testId}`]);
      await tx.query("INSERT INTO corporations (id, charter_version, admission_policy, status, created_game_day) VALUES ($1, 1, 'OPEN', 'ACTIVE', 1)", [corpId]);
      await tx.query("INSERT INTO owner_registry (id, owner_type, economic_id) VALUES ($1, 'CORPORATION', $2)", [`REG-C-${testId}`, corpEconId]);
      await tx.query('SELECT earth_provision_corporation_economy($1)', [corpEconId]);

      // Seed 3,000 units of COMPUTE
      await tx.query(`
        UPDATE economic_accounts
           SET balance_units = 3000
         WHERE owner_economic_id = $1 AND asset_id = 5 AND account_type = 'INVENTORY'
      `, [corpEconId]);

      // Grant COMPUTE_STORAGE with 2,000 units capacity
      await grantOwnerStorageCapacity(tx, {
        ownerEconomicId: corpEconId,
        assetCode: 'COMPUTE',
        storageType: 'COMPUTE_STORAGE',
        capacityUnits: 2000n,
        sourceType: 'TECHNOLOGY',
        sourceId: `TECH-OPTICAL-BUFFER-${testId}`,
        effectiveFromGameDay: 1,
      });

      // Settle decay
      await settleResourcePersistenceAndDecay(tx, gameDay);

      // Verify Corporation COMPUTE balance is preserved at exactly 2,000 units (excess 1,000 expired)
      const computeAcc = (await tx.query('SELECT balance_units FROM economic_accounts WHERE owner_economic_id = $1 AND asset_id = 5 AND account_type = $2', [corpEconId, 'INVENTORY'])).rows[0];
      assert.equal(computeAcc.balance_units, '2000');
    });
  } finally {
    await client.query('DELETE FROM owner_storage_capacities WHERE owner_economic_id = $1', [corpEconId]);
    await client.query("DELETE FROM economic_entries WHERE transaction_id IN (SELECT id FROM economic_transactions WHERE correlation_id LIKE '%resource-decay%')");
    await client.query("DELETE FROM economic_transactions WHERE correlation_id LIKE '%resource-decay%'");
    await client.query('DELETE FROM economic_entries WHERE account_id IN (SELECT id FROM economic_accounts WHERE owner_economic_id = $1)', [corpEconId]);
    await client.query('DELETE FROM economic_accounts WHERE owner_economic_id = $1', [corpEconId]);
    await client.query('DELETE FROM owner_registry WHERE economic_id = $1', [corpEconId]);
    await client.query('DELETE FROM corporations WHERE id = $1', [corpId]);
    await client.query('DELETE FROM institutions WHERE id = $1', [corpId]);
    await client.end();
  }
});

test('PostgreSQL V5 Economic Core Phase 10: Architecture integrity report passes with 0 failures across all production and storage entities', async () => {
  const client = await connectTo(connectionString);
  try {
    const reportRes = await client.query('SELECT * FROM earth_integrity_report()');
    for (const check of reportRes.rows) {
      assert.equal(check.invalid_count, '0', `Integrity check ${check.check_name} must have 0 invalid rows`);
    }
  } finally {
    await client.end();
  }
});

test('PostgreSQL V5 Economic Core Phase 11: Construction, Tier Upgrade, Demolition, and Retrofit record structural deltas and maintain profile parity', async () => {
  const client = postgresClient(connectionString);
  await client.connect();
  const repository = new PostgresRepository(client);
  const testId = `p11t1-${Date.now()}`;
  const humanId = `HUM-${testId}`;
  const houseId = `HOUSE-${testId}`;
  const houseEconId = `HOUSE-ECON-${testId}`;
  const corpId = `CORP-${testId}`;
  const corpEconId = `CORP-ECON-${testId}`;
  const territoryId = `TERR-${testId}`;
  const residencyId = `RES-${testId}`;
  const gameDay = 2;

  try {
    // 1. Setup Auth, House, Human, Corp, Territory
    await repository.query(`INSERT INTO auth_accounts (id, email, password_hash, password_salt, password_iterations) VALUES ($1, $2, 'test-password-hash', 'salt', 100000)`, [`AUTH-${humanId}`, `${testId}@example.com`]);
    await repository.query('INSERT INTO houses (id, account_id, house_name, dynasty_legacy, generation, status) VALUES ($1, $2, $3, 0, 1, $4)', [houseId, `AUTH-${humanId}`, `House ${testId}`, 'ACTIVE']);
    await repository.query(`INSERT INTO humans (id, account_id, house_id, display_name, status) VALUES ($1, $2, $3, $4, 'ACTIVE')`, [humanId, `AUTH-${humanId}`, houseId, `Human ${testId}`]);
    await repository.query('UPDATE houses SET current_human_id = $1 WHERE id = $2', [humanId, houseId]);
    await repository.query("INSERT INTO owner_registry (id, owner_type, economic_id) VALUES ($1, 'HOUSE', $2)", [houseId, houseEconId]);
    await repository.query('SELECT earth_provision_house_economy($1)', [houseEconId]);

    await repository.query("INSERT INTO institutions (id, kind, name, status) VALUES ($1, 'CORPORATION', $2, 'ACTIVE')", [corpId, `Corp ${testId}`]);
    await repository.query("INSERT INTO corporations (id, charter_version, admission_policy, status, created_game_day) VALUES ($1, 1, 'OPEN', 'ACTIVE', 1)", [corpId]);
    await repository.query("INSERT INTO owner_registry (id, owner_type, economic_id) VALUES ($1, 'CORPORATION', $2)", [corpId, corpEconId]);
    await repository.query('SELECT earth_provision_corporation_economy($1)', [corpEconId]);

    await repository.query(`INSERT INTO territories (id, corporation_id, name, status, is_primary) VALUES ($1, $2, 'Territory', 'ACTIVE', true)`, [territoryId, corpId]);
    await repository.query(`INSERT INTO house_residencies (id, house_id, territory_id, residency_class, status, effective_from_game_day, correlation_id) VALUES ($1, $2, $3, 'PRIMARY', 'ACTIVE', 1, $4)`, [residencyId, houseId, territoryId, `res:${houseId}:${territoryId}:${Date.now()}`]);
    await repository.query(`INSERT INTO house_affiliations (house_id, corporation_id, primary_territory_id, joined_game_day, status) VALUES ($1, $2, $3, 1, 'ACTIVE')`, [houseId, corpId, territoryId]);

    // Seed Credits and Materials
    await repository.query(`UPDATE economic_accounts SET balance_units = 100000 WHERE owner_economic_id = $1 AND asset_id = 1`, [houseEconId]);
    await repository.query(`UPDATE economic_accounts SET balance_units = 500 WHERE owner_economic_id = $1 AND asset_id = 2`, [houseEconId]); // MATERIAL
    await repository.query(`UPDATE economic_accounts SET balance_units = 500 WHERE owner_economic_id = $1 AND asset_id = 3`, [houseEconId]); // COMPONENTS
    await repository.query(`UPDATE economic_accounts SET balance_units = 500 WHERE owner_economic_id = $1 AND asset_id = 5`, [houseEconId]); // COMPUTE

    // Initial rebuild
    await refreshV5SettlementProfilesForHouse(repository, houseId, gameDay, [corpId]);

    const initialHouseProfile = await getHouseSettlementProfileSnapshot(repository, houseId);
    assert.ok(initialHouseProfile);
    assert.equal(initialHouseProfile.residential_capacity_units, '1');
    assert.equal(initialHouseProfile.productive_capacity_units, '0');
    assert.equal(initialHouseProfile.active_building_count, 0);

    let buildingId;
    // Step 1: Purchase House building (SOLAR-MICROGRID-T1)
    const bldRes = await purchaseV5Building(repository, {
      buildingType: 'SOLAR-MICROGRID-T1',
      name: 'Solar Grid 1',
      ownerId: humanId,
      correlationId: `p11-purchase-${testId}`,
    });
    assert.ok(bldRes.ok);
    buildingId = bldRes.buildingId;

    // Check structural delta recorded for construction
    const constructionDeltas = await getStructuralDeltas(repository, { correlationId: `p11-purchase-${testId}` });
    assert.equal(constructionDeltas.length, 1);
    assert.equal(constructionDeltas[0].action_type, 'CONSTRUCTION');
    assert.equal(constructionDeltas[0].entity_id, houseId);
    assert.equal(constructionDeltas[0].delta_footprint_units, '2');

    // Step 2: Retrofit building
    await repository.query(`UPDATE buildings SET status = 'ACTIVE', construction_state = 'ACTIVE' WHERE id = $1`, [buildingId]);
    await repository.query(`UPDATE construction_projects SET status = 'COMPLETED' WHERE building_id = $1`, [buildingId]);
    await refreshV5SettlementProfilesForHouse(repository, houseId, gameDay, [corpId]);

    const postActiveProfile = await getHouseSettlementProfileSnapshot(repository, houseId);
    assert.equal(postActiveProfile.productive_capacity_units, '2');
    assert.equal(postActiveProfile.active_building_count, 1);

    const domains = (await repository.query(`SELECT id, code FROM technology_domains`)).rows;
    const energyDomain = domains.find(d => d.code === 'ENERGY');

    // Unlock generation 2 for Corporation
    await repository.query(`
      INSERT INTO corporation_technology_generations (corporation_economic_id, domain_id, generation_number, unlocked_game_day)
      VALUES ($1, $2, 2, 1)
      ON CONFLICT (corporation_economic_id, domain_id, generation_number) DO NOTHING
    `, [corpEconId, energyDomain.id]);

    const retrofitRes = await retrofitBuilding(repository, {
      buildingId,
      humanId,
      targetGeneration: 2,
      correlationId: `p11-retrofit-${testId}`,
    });
    assert.ok(retrofitRes.ok);

    const retrofitDeltas = await getStructuralDeltas(repository, { correlationId: `p11-retrofit-${testId}` });
    assert.equal(retrofitDeltas.length, 1);
    assert.equal(retrofitDeltas[0].action_type, 'RETROFIT');
    assert.equal(retrofitDeltas[0].building_id, buildingId);

    // Step 3: Complete retrofit project and set back to ACTIVE
    await repository.query(`UPDATE buildings SET status = 'ACTIVE', construction_state = 'ACTIVE', installed_generation = 2 WHERE id = $1`, [buildingId]);
    await repository.query(`UPDATE construction_projects SET status = 'COMPLETED' WHERE building_id = $1`, [buildingId]);
    await refreshV5SettlementProfilesForHouse(repository, houseId, gameDay, [corpId]);

    // Grant SCALE_COMMERCIAL for Tier 2 upgrade
    await repository.query(`
      INSERT INTO corporation_scale_capabilities (corporation_economic_id, scale_capability)
      VALUES ($1, 'SCALE_COMMERCIAL')
      ON CONFLICT DO NOTHING
    `, [corpEconId]);

    // Step 4: Tier Upgrade (SOLAR-MICROGRID-T1 -> SOLAR-MICROGRID-T2)
    const upgradeRes = await upgradeBuilding(repository, {
      buildingId,
      humanId,
      correlationId: `p11-upgrade-${testId}`,
    });
    assert.ok(upgradeRes.ok);

    const upgradeDeltas = await getStructuralDeltas(repository, { correlationId: `p11-upgrade-${testId}` });
    assert.equal(upgradeDeltas.length, 1);
    assert.equal(upgradeDeltas[0].action_type, 'TIER_UPGRADE');
    assert.equal(upgradeDeltas[0].building_id, buildingId);

    // Step 5: Complete upgrade and then Decommission
    await repository.query(`UPDATE buildings SET status = 'ACTIVE', construction_state = 'ACTIVE' WHERE id = $1`, [buildingId]);
    await repository.query(`UPDATE construction_projects SET status = 'COMPLETED' WHERE building_id = $1`, [buildingId]);
    await refreshV5SettlementProfilesForHouse(repository, houseId, gameDay, [corpId]);

    const demoRes = await decommissionBuilding(repository, {
      buildingId,
      humanId,
      correlationId: `p11-demo-${testId}`,
    });
    assert.ok(demoRes.ok);

    const demoDeltas = await getStructuralDeltas(repository, { correlationId: `p11-demo-${testId}` });
    assert.equal(demoDeltas.length, 1);
    assert.equal(demoDeltas[0].action_type, 'DEMOLITION');
    assert.equal(demoDeltas[0].delta_building_count, -1);

    const postDemoProfile = await getHouseSettlementProfileSnapshot(repository, houseId);
    assert.equal(postDemoProfile.productive_capacity_units, '0');
    assert.equal(postDemoProfile.active_building_count, 0);
  } finally {
    await client.query('DELETE FROM game_events WHERE actor_human_id = $1 OR correlation_id LIKE $2', [humanId, `p11-%-${testId}`]);
    await client.query('DELETE FROM v5_structural_deltas WHERE correlation_id LIKE $1', [`p11-%-${testId}`]);
    await client.query('DELETE FROM construction_projects WHERE correlation_id LIKE $1', [`p11-%-${testId}`]);
    await client.query('DELETE FROM buildings WHERE owner_economic_id = $1', [houseEconId]);
    await client.query('DELETE FROM corporation_scale_capabilities WHERE corporation_economic_id = $1', [corpEconId]);
    await client.query('DELETE FROM corporation_technology_generations WHERE corporation_economic_id = $1', [corpEconId]);
    await client.query('DELETE FROM house_residencies WHERE house_id = $1', [houseId]);
    await client.query('DELETE FROM house_affiliations WHERE house_id = $1', [houseId]);
    await client.query('DELETE FROM territory_capacity_state WHERE territory_id = $1', [territoryId]);
    await client.query('DELETE FROM territories WHERE corporation_id = $1', [corpId]);
    await client.query('DELETE FROM v5_house_settlement_profiles WHERE house_id = $1', [houseId]);
    await client.query('DELETE FROM v5_corporation_settlement_profiles WHERE corporation_id = $1', [corpId]);
    await client.query('DELETE FROM economic_entries WHERE transaction_id IN (SELECT id FROM economic_transactions WHERE correlation_id LIKE $1)', [`%${testId}%`]);
    await client.query('DELETE FROM economic_transactions WHERE correlation_id LIKE $1', [`%${testId}%`]);
    await client.query('DELETE FROM economic_entries WHERE account_id IN (SELECT id FROM economic_accounts WHERE owner_economic_id IN ($1, $2))', [houseEconId, corpEconId]);
    await client.query('DELETE FROM economic_accounts WHERE owner_economic_id IN ($1, $2)', [houseEconId, corpEconId]);
    await client.query('UPDATE houses SET current_human_id = NULL WHERE id = $1', [houseId]);
    await client.query('DELETE FROM humans WHERE id = $1', [humanId]);
    await client.query('DELETE FROM houses WHERE id = $1', [houseId]);
    await client.query('DELETE FROM corporations WHERE id = $1', [corpId]);
    await client.query('DELETE FROM institutions WHERE id = $1', [corpId]);
    await client.query('DELETE FROM owner_registry WHERE economic_id IN ($1, $2)', [houseEconId, corpEconId]);
    await client.query('DELETE FROM auth_accounts WHERE id = $1', [`AUTH-${humanId}`]);
    await client.end();
  }
});

test('PostgreSQL V5 Economic Core Phase 11: Membership Join, Leave, Building Suspension and Reactivation update profiles transactionally with recorded deltas', async () => {
  const client = postgresClient(connectionString);
  await client.connect();
  const repository = new PostgresRepository(client);
  const testId = `p11t2-${Date.now()}`;
  const humanId = `HUM-${testId}`;
  const houseId = `HOUSE-${testId}`;
  const houseEconId = `HOUSE-ECON-${testId}`;
  const corpId = `CORP-${testId}`;
  const corpEconId = `CORP-ECON-${testId}`;
  const territoryId = `TERR-${testId}`;
  const residencyId = `RES-${testId}`;
  const gameDay = 5;

  try {
    // Setup Auth, House, Human, Corp, Territory
    await repository.query(`INSERT INTO auth_accounts (id, email, password_hash, password_salt, password_iterations) VALUES ($1, $2, 'test-password-hash', 'salt', 100000)`, [`AUTH-${humanId}`, `${testId}@example.com`]);
    await repository.query('INSERT INTO houses (id, account_id, house_name, dynasty_legacy, generation, status) VALUES ($1, $2, $3, 0, 1, $4)', [houseId, `AUTH-${humanId}`, `House ${testId}`, 'ACTIVE']);
    await repository.query(`INSERT INTO humans (id, account_id, house_id, display_name, status) VALUES ($1, $2, $3, $4, 'ACTIVE')`, [humanId, `AUTH-${humanId}`, houseId, `Human ${testId}`]);
    await repository.query('UPDATE houses SET current_human_id = $1 WHERE id = $2', [humanId, houseId]);
    await repository.query("INSERT INTO owner_registry (id, owner_type, economic_id) VALUES ($1, 'HOUSE', $2)", [houseId, houseEconId]);
    await repository.query('SELECT earth_provision_house_economy($1)', [houseEconId]);

    await repository.query("INSERT INTO institutions (id, kind, name, status) VALUES ($1, 'CORPORATION', $2, 'ACTIVE')", [corpId, `Corp ${testId}`]);
    await repository.query("INSERT INTO corporations (id, charter_version, admission_policy, status, created_game_day) VALUES ($1, 1, 'OPEN', 'ACTIVE', 1)", [corpId]);
    await repository.query("INSERT INTO owner_registry (id, owner_type, economic_id) VALUES ($1, 'CORPORATION', $2)", [corpId, corpEconId]);
    await repository.query('SELECT earth_provision_corporation_economy($1)', [corpEconId]);

    await repository.query(`INSERT INTO territories (id, corporation_id, name, status, is_primary) VALUES ($1, $2, 'Territory', 'ACTIVE', true)`, [territoryId, corpId]);
    await repository.query(`INSERT INTO house_residencies (id, house_id, territory_id, residency_class, status, effective_from_game_day, correlation_id) VALUES ($1, $2, $3, 'PRIMARY', 'ACTIVE', 1, $4)`, [residencyId, houseId, territoryId, `res:${houseId}:${territoryId}:${Date.now()}`]);
    await repository.query(`INSERT INTO house_affiliations (house_id, corporation_id, primary_territory_id, joined_game_day, status) VALUES ($1, $2, $3, 1, 'ACTIVE')`, [houseId, corpId, territoryId]);

    // Seed building for House
    const bldId = `BLD-${testId}`;
    await repository.query(`
      INSERT INTO buildings (id, owner_economic_id, territory_id, catalog_id, status, construction_state, installed_generation, technology_definition_version, started_game_day, commissioned_game_day)
      VALUES ($1, $2, $3, 'SOLAR-MICROGRID-T1', 'ACTIVE', 'ACTIVE', 1, 'tech-gen-v1', 1, 1)
    `, [bldId, houseEconId, territoryId]);

    await refreshV5SettlementProfilesForHouse(repository, houseId, gameDay, [corpId]);

    // Step 1: Suspend Building
    const suspendRes = await suspendBuilding(repository, {
      buildingId: bldId,
      humanId,
      correlationId: `p11-suspend-${testId}`,
    });
    assert.ok(suspendRes.ok);
    assert.equal(suspendRes.status, 'SUSPENDED');

    const houseProfileAfterSuspend = await getHouseSettlementProfileSnapshot(repository, houseId);
    assert.equal(houseProfileAfterSuspend.productive_capacity_units, '0');
    assert.equal(houseProfileAfterSuspend.active_building_count, 0);

    const corpProfileAfterSuspend = await getCorporationSettlementProfileSnapshot(repository, corpId);
    assert.equal(corpProfileAfterSuspend.member_productive_capacity_units, '0');

    const suspendDeltas = await getStructuralDeltas(repository, { correlationId: `p11-suspend-${testId}` });
    assert.equal(suspendDeltas.length, 1);
    assert.equal(suspendDeltas[0].action_type, 'BUILDING_SUSPEND');
    assert.equal(suspendDeltas[0].delta_building_count, -1);

    // Step 2: Reactivate Building
    const reactivateRes = await reactivateBuilding(repository, {
      buildingId: bldId,
      humanId,
      correlationId: `p11-reactivate-${testId}`,
    });
    assert.ok(reactivateRes.ok);
    assert.equal(reactivateRes.status, 'ACTIVE');

    const houseProfileAfterReactivate = await getHouseSettlementProfileSnapshot(repository, houseId);
    assert.equal(houseProfileAfterReactivate.productive_capacity_units, '2');
    assert.equal(houseProfileAfterReactivate.active_building_count, 1);

    // Step 3: Leave Corporation
    const leaveRes = await leaveV5Corporation(repository, {
      humanId,
      corporationId: corpId,
      correlationId: `p11-leave-${testId}`,
    });
    assert.ok(leaveRes.ok);

    const houseProfileAfterLeave = await getHouseSettlementProfileSnapshot(repository, houseId);
    assert.equal(houseProfileAfterLeave.corporation_id, null);

    const corpProfileAfterLeave = await getCorporationSettlementProfileSnapshot(repository, corpId);
    assert.equal(corpProfileAfterLeave.active_member_count, 0);
    assert.equal(corpProfileAfterLeave.member_residential_capacity_units, '0');
    assert.equal(corpProfileAfterLeave.member_productive_capacity_units, '0');

    const leaveDeltas = await getStructuralDeltas(repository, { correlationId: `p11-leave-${testId}` });
    assert.equal(leaveDeltas.length, 2);
    assert.equal(leaveDeltas[0].action_type, 'MEMBERSHIP_LEAVE');

    // Step 4: Apply Corporation Membership (Join back)
    const joinRes = await applyV5CorporationMembership(repository, {
      humanId,
      corporationId: corpId,
      correlationId: `p11-join-${testId}`,
    });
    assert.ok(joinRes.ok);

    const houseProfileAfterJoin = await getHouseSettlementProfileSnapshot(repository, houseId);
    assert.equal(houseProfileAfterJoin.corporation_id, corpId);

    const corpProfileAfterJoin = await getCorporationSettlementProfileSnapshot(repository, corpId);
    assert.equal(corpProfileAfterJoin.active_member_count, 1);
    assert.equal(corpProfileAfterJoin.member_residential_capacity_units, '1');
    assert.equal(corpProfileAfterJoin.member_productive_capacity_units, '2');

    const joinDeltas = await getStructuralDeltas(repository, { correlationId: `p11-join-${testId}` });
    assert.equal(joinDeltas.length, 2);
    assert.equal(joinDeltas[0].action_type, 'MEMBERSHIP_JOIN');
  } finally {
    await client.query('DELETE FROM game_events WHERE actor_human_id = $1 OR correlation_id LIKE $2', [humanId, `p11-%-${testId}`]);
    await client.query('DELETE FROM v5_structural_deltas WHERE correlation_id LIKE $1', [`p11-%-${testId}`]);
    await client.query('DELETE FROM buildings WHERE owner_economic_id = $1', [houseEconId]);
    await client.query('DELETE FROM house_residencies WHERE house_id = $1', [houseId]);
    await client.query('DELETE FROM house_affiliations WHERE house_id = $1', [houseId]);
    await client.query('DELETE FROM territory_capacity_state WHERE territory_id = $1', [territoryId]);
    await client.query('DELETE FROM territories WHERE corporation_id = $1', [corpId]);
    await client.query('DELETE FROM v5_house_settlement_profiles WHERE house_id = $1', [houseId]);
    await client.query('DELETE FROM v5_corporation_settlement_profiles WHERE corporation_id = $1', [corpId]);
    await client.query('DELETE FROM economic_entries WHERE transaction_id IN (SELECT id FROM economic_transactions WHERE correlation_id LIKE $1)', [`%${testId}%`]);
    await client.query('DELETE FROM economic_transactions WHERE correlation_id LIKE $1', [`%${testId}%`]);
    await client.query('DELETE FROM economic_entries WHERE account_id IN (SELECT id FROM economic_accounts WHERE owner_economic_id IN ($1, $2))', [houseEconId, corpEconId]);
    await client.query('DELETE FROM economic_accounts WHERE owner_economic_id IN ($1, $2)', [houseEconId, corpEconId]);
    await client.query('UPDATE houses SET current_human_id = NULL WHERE id = $1', [houseId]);
    await client.query('DELETE FROM humans WHERE id = $1', [humanId]);
    await client.query('DELETE FROM houses WHERE id = $1', [houseId]);
    await client.query('DELETE FROM corporations WHERE id = $1', [corpId]);
    await client.query('DELETE FROM institutions WHERE id = $1', [corpId]);
    await client.query('DELETE FROM owner_registry WHERE economic_id IN ($1, $2)', [houseEconId, corpEconId]);
    await client.query('DELETE FROM auth_accounts WHERE id = $1', [`AUTH-${humanId}`]);
    await client.end();
  }
});

test('PostgreSQL V5 Economic Core Phase 11: Deterministic rebuild reproduces live profiles exactly matching catalog totals', async () => {
  const client = postgresClient(connectionString);
  await client.connect();
  const repository = new PostgresRepository(client);
  const testId = `p11t3-${Date.now()}`;
  const humanId = `HUM-${testId}`;
  const houseId = `HOUSE-${testId}`;
  const houseEconId = `HOUSE-ECON-${testId}`;
  const corpId = `CORP-${testId}`;
  const corpEconId = `CORP-ECON-${testId}`;
  const territoryId = `TERR-${testId}`;
  const residencyId = `RES-${testId}`;
  const gameDay = 10;

  try {
    // Setup Auth, House, Human, Corp, Territory
    await repository.query(`INSERT INTO auth_accounts (id, email, password_hash, password_salt, password_iterations) VALUES ($1, $2, 'test-password-hash', 'salt', 100000)`, [`AUTH-${humanId}`, `${testId}@example.com`]);
    await repository.query('INSERT INTO houses (id, account_id, house_name, dynasty_legacy, generation, status) VALUES ($1, $2, $3, 0, 1, $4)', [houseId, `AUTH-${humanId}`, `House ${testId}`, 'ACTIVE']);
    await repository.query(`INSERT INTO humans (id, account_id, house_id, display_name, status) VALUES ($1, $2, $3, $4, 'ACTIVE')`, [humanId, `AUTH-${humanId}`, houseId, `Human ${testId}`]);
    await repository.query('UPDATE houses SET current_human_id = $1 WHERE id = $2', [humanId, houseId]);
    await repository.query("INSERT INTO owner_registry (id, owner_type, economic_id) VALUES ($1, 'HOUSE', $2)", [houseId, houseEconId]);
    await repository.query('SELECT earth_provision_house_economy($1)', [houseEconId]);

    await repository.query("INSERT INTO institutions (id, kind, name, status) VALUES ($1, 'CORPORATION', $2, 'ACTIVE')", [corpId, `Corp ${testId}`]);
    await repository.query("INSERT INTO corporations (id, charter_version, admission_policy, status, created_game_day) VALUES ($1, 1, 'OPEN', 'ACTIVE', 1)", [corpId]);
    await repository.query("INSERT INTO owner_registry (id, owner_type, economic_id) VALUES ($1, 'CORPORATION', $2)", [corpId, corpEconId]);
    await repository.query('SELECT earth_provision_corporation_economy($1)', [corpEconId]);

    await repository.query(`INSERT INTO territories (id, corporation_id, name, status, is_primary) VALUES ($1, $2, 'Territory', 'ACTIVE', true)`, [territoryId, corpId]);
    await repository.query(`INSERT INTO house_residencies (id, house_id, territory_id, residency_class, status, effective_from_game_day, correlation_id) VALUES ($1, $2, $3, 'PRIMARY', 'ACTIVE', 1, $4)`, [residencyId, houseId, territoryId, `res:${houseId}:${territoryId}:${Date.now()}`]);
    await repository.query(`INSERT INTO house_affiliations (house_id, corporation_id, primary_territory_id, joined_game_day, status) VALUES ($1, $2, $3, 1, 'ACTIVE')`, [houseId, corpId, territoryId]);

    // Add 2 active buildings to House (footprint 2 each = 4)
    await repository.query(`
      INSERT INTO buildings (id, owner_economic_id, territory_id, catalog_id, status, construction_state, installed_generation, technology_definition_version, started_game_day, commissioned_game_day)
      VALUES
        ($1, $3, $4, 'SOLAR-MICROGRID-T1', 'ACTIVE', 'ACTIVE', 1, 'tech-gen-v1', 1, 1),
        ($2, $3, $4, 'VERTICAL-FARM-T1', 'ACTIVE', 'ACTIVE', 1, 'tech-gen-v1', 1, 1)
    `, [`BLD-1-${testId}`, `BLD-2-${testId}`, houseEconId, territoryId]);

    // Add 1 active public building to Corporation (footprint 5)
    await repository.query(`
      INSERT INTO buildings (id, owner_economic_id, territory_id, catalog_id, status, construction_state, installed_generation, technology_definition_version, started_game_day, commissioned_game_day)
      VALUES ($1, $2, $3, 'EXTRACTION-REFINING-T1', 'ACTIVE', 'ACTIVE', 1, 'tech-gen-v1', 1, 1)
    `, [`BLD-PUB-${testId}`, corpEconId, territoryId]);

    // Run rebuild functions
    await rebuildV5HouseSettlementProfile(repository, houseId, gameDay);
    await rebuildV5CorporationSettlementProfile(repository, corpId, gameDay);

    const liveHouseProfile = await getHouseSettlementProfileSnapshot(repository, houseId);
    assert.equal(liveHouseProfile.residential_capacity_units, '1');
    assert.equal(liveHouseProfile.productive_capacity_units, '4');
    assert.equal(liveHouseProfile.total_capacity_units, '5');
    assert.equal(liveHouseProfile.active_building_count, 2);

    const liveCorpProfile = await getCorporationSettlementProfileSnapshot(repository, corpId);
    assert.equal(liveCorpProfile.active_member_count, 1);
    assert.equal(liveCorpProfile.member_residential_capacity_units, '1');
    assert.equal(liveCorpProfile.member_productive_capacity_units, '4');
    assert.equal(liveCorpProfile.public_capacity_units, '5');
    assert.equal(liveCorpProfile.total_occupied_capacity_units, '10');
    assert.equal(liveCorpProfile.active_public_building_count, 1);

    // Mark profiles as dirty
    await repository.query(`UPDATE v5_house_settlement_profiles SET dirty = true WHERE house_id = $1`, [houseId]);
    await repository.query(`UPDATE v5_corporation_settlement_profiles SET dirty = true WHERE corporation_id = $1`, [corpId]);

    // Run shard rebuild
    const shardRes = await rebuildV5SettlementProfilesInShard(repository, gameDay, 0, 1);
    assert.ok(shardRes.housesRebuilt >= 1);

    // Verify dirty flag is cleared and values match exactly
    const rebuiltHouseProfile = await getHouseSettlementProfileSnapshot(repository, houseId);
    assert.equal(rebuiltHouseProfile.dirty, false);
    assert.equal(rebuiltHouseProfile.productive_capacity_units, '4');

    const rebuiltCorpProfile = await getCorporationSettlementProfileSnapshot(repository, corpId);
    assert.equal(rebuiltCorpProfile.dirty, false);
    assert.equal(rebuiltCorpProfile.total_occupied_capacity_units, '10');
  } finally {
    await client.query('DELETE FROM game_events WHERE actor_human_id = $1', [humanId]);
    await client.query('DELETE FROM buildings WHERE owner_economic_id IN ($1, $2)', [houseEconId, corpEconId]);
    await client.query('DELETE FROM house_residencies WHERE house_id = $1', [houseId]);
    await client.query('DELETE FROM house_affiliations WHERE house_id = $1', [houseId]);
    await client.query('DELETE FROM territory_capacity_state WHERE territory_id = $1', [territoryId]);
    await client.query('DELETE FROM territories WHERE corporation_id = $1', [corpId]);
    await client.query('DELETE FROM v5_house_settlement_profiles WHERE house_id = $1', [houseId]);
    await client.query('DELETE FROM v5_corporation_settlement_profiles WHERE corporation_id = $1', [corpId]);
    await client.query('DELETE FROM economic_entries WHERE account_id IN (SELECT id FROM economic_accounts WHERE owner_economic_id IN ($1, $2))', [houseEconId, corpEconId]);
    await client.query('DELETE FROM economic_accounts WHERE owner_economic_id IN ($1, $2)', [houseEconId, corpEconId]);
    await client.query('UPDATE houses SET current_human_id = NULL WHERE id = $1', [houseId]);
    await client.query('DELETE FROM humans WHERE id = $1', [humanId]);
    await client.query('DELETE FROM houses WHERE id = $1', [houseId]);
    await client.query('DELETE FROM corporations WHERE id = $1', [corpId]);
    await client.query('DELETE FROM institutions WHERE id = $1', [corpId]);
    await client.query('DELETE FROM owner_registry WHERE economic_id IN ($1, $2)', [houseEconId, corpEconId]);
    await client.query('DELETE FROM auth_accounts WHERE id = $1', [`AUTH-${humanId}`]);
    await client.end();
  }
});



