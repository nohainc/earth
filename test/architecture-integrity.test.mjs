import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const read = (file) => fs.readFileSync(file, 'utf8');
const reference = read('db/baseline/03_reference_data.sql');
const schema = read('db/baseline/01_schema.sql');
const baselineFunctions = read('db/baseline/02_functions.sql');
const migration = read('db/migrations/005_architecture_integrity_report.sql');
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
