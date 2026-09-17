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

test('PostgreSQL V5 Economic Core: Schema version is 120 and migration history is valid', async () => {
  const client = await connectTo(connectionString);
  try {
    const res = await client.query('SELECT MAX(version) AS max_version, COUNT(*)::int AS count FROM earth_schema_migrations');
    assert.equal(Number(res.rows[0].max_version), 120, 'Max migration version must be 120');
    assert.equal(Number(res.rows[0].count), 120, 'Total applied migrations count must be 120');

    const v118 = await client.query('SELECT name FROM earth_schema_migrations WHERE version = 118');
    assert.equal(v118.rows[0]?.name, '118_v5_economic_core_schema.sql');

    const v119 = await client.query('SELECT name FROM earth_schema_migrations WHERE version = 119');
    assert.equal(v119.rows[0]?.name, '119_v5_building_catalog_v5_alpha.sql');

    const v120 = await client.query('SELECT name FROM earth_schema_migrations WHERE version = 120');
    assert.equal(v120.rows[0]?.name, '120_v5_corporation_resource_accounts.sql');
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

