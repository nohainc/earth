import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const read = (file) => fs.readFileSync(file, 'utf8');
const schema = read('db/baseline/01_schema.sql');
const functions = read('db/baseline/02_functions.sql');
const reference = read('db/baseline/03_reference_data.sql');
const world = read('db/baseline/04_initial_world.sql');
const resourceLedger = read('cloudflare/src/resource-ledger-postgres.ts');

test('ledger catalogs explicit transaction and source semantics', () => {
  assert.match(schema, /CREATE TABLE economic_transaction_kinds/);
  assert.match(schema, /CREATE TABLE economic_source_types/);
  for (const kind of ['ASSET_TRANSFER', 'CREDIT_ISSUANCE', 'CREDIT_RETIREMENT', 'RESOURCE_PRODUCTION', 'RESOURCE_CONSUMPTION']) {
    assert.match(reference, new RegExp(`'${kind}'`));
  }
  for (const source of ['SYSTEM_ISSUANCE', 'SYSTEM_RETIREMENT', 'SYSTEM_PRODUCTION', 'SYSTEM_CONSUMPTION']) {
    assert.match(reference, new RegExp(`'${source}'`));
  }
});

test('posting validates account assets and balances independently per asset', () => {
  assert.match(functions, /economic entry asset does not match account asset/);
  assert.match(functions, /GROUP BY \(value->>'asset_id'\)::INTEGER/);
  assert.match(functions, /asset transfer is not balanced for asset/);
  assert.match(functions, /CREDIT issuance must create a positive CREDIT amount/);
  assert.match(functions, /CREDIT retirement must destroy a positive CREDIT amount/);
  assert.match(functions, /earth_daily_asset_flow/);
});

test('resource ledger uses dedicated production and consumption system accounts', () => {
  assert.match(world, /ECON-RESOURCE-PRODUCTION/);
  assert.match(world, /ECON-RESOURCE-CONSUMPTION/);
  assert.doesNotMatch(world, /SELECT 'ECON-MONETARY-RETIREMENT', id/);
  assert.match(resourceLedger, /ECON-RESOURCE-PRODUCTION/);
  assert.match(resourceLedger, /ECON-RESOURCE-CONSUMPTION/);
  assert.match(resourceLedger, /RESOURCE_PRODUCTION/);
  assert.match(resourceLedger, /RESOURCE_CONSUMPTION/);
});
