import test from 'node:test';
import assert from 'node:assert/strict';
import { Client } from 'pg';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { postgresClient } from './postgres-connection.mjs';

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

test('PostgreSQL V5 Economic Core: Schema version is 119 and migration history is valid', async () => {
  const client = await connectTo(connectionString);
  try {
    const res = await client.query('SELECT MAX(version) AS max_version, COUNT(*)::int AS count FROM earth_schema_migrations');
    assert.equal(Number(res.rows[0].max_version), 119, 'Max migration version must be 119');
    assert.equal(Number(res.rows[0].count), 119, 'Total applied migrations count must be 119');

    const v118 = await client.query('SELECT name FROM earth_schema_migrations WHERE version = 118');
    assert.equal(v118.rows[0]?.name, '118_v5_economic_core_schema.sql');

    const v119 = await client.query('SELECT name FROM earth_schema_migrations WHERE version = 119');
    assert.equal(v119.rows[0]?.name, '119_v5_building_catalog_v5_alpha.sql');
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
