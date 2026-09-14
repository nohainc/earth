import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const read = (file) => fs.readFileSync(file, 'utf8');
const functions = read('db/baseline/02_functions.sql');
const initialWorld = read('db/baseline/04_initial_world.sql');
const auth = read('cloudflare/src/auth-postgres.ts');
const institutions = read('cloudflare/src/institutions-postgres.ts');

test('canonical provisioning functions define deterministic principal account topologies', () => {
  for (const functionName of [
    'earth_provision_house_economy',
    'earth_provision_corporation_economy',
    'earth_provision_earth_economy',
    'earth_provision_bank_economy',
  ]) assert.match(functions, new RegExp(`CREATE OR REPLACE FUNCTION ${functionName}`));

  assert.match(functions, /earth_provision_house_economy[\s\S]*?WHERE asset_kind = 'CREDIT'[\s\S]*?'WALLET'/);
  assert.match(functions, /earth_provision_house_economy[\s\S]*?WHERE asset_kind = 'RESOURCE'[\s\S]*?'INVENTORY'/);
  assert.match(functions, /earth_provision_corporation_economy[\s\S]*?'TREASURY'[\s\S]*?'OPERATIONS'[\s\S]*?'RESERVE'/);
  assert.match(functions, /earth_provision_bank_economy[\s\S]*?'OPERATIONS'[\s\S]*?'RESERVE'/);
  assert.match(functions, /ON CONFLICT \(owner_economic_id, asset_id, account_type\) DO NOTHING/);
});

test('genesis and services delegate account structure to canonical provisioning', () => {
  assert.match(initialWorld, /SELECT earth_provision_earth_economy\('ECON-EARTH-001'\)/);
  assert.match(initialWorld, /SELECT earth_provision_bank_economy\('ECON-GLOBAL-BANK-001'\)/);
  assert.match(auth, /SELECT earth_provision_house_economy\(\$1\)/);
  assert.match(institutions, /SELECT earth_provision_corporation_economy\(\$1\)/);
  assert.doesNotMatch(auth, /INSERT INTO economic_accounts/);
  assert.doesNotMatch(institutions, /INSERT INTO economic_accounts/);
});
