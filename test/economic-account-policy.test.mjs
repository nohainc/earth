import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

const root = path.resolve('.');
const read = (file) => fs.readFileSync(path.join(root, file), 'utf8');

test('economic account policy is database-enforced and ESCROW is removed', () => {
  const schema = read('db/baseline/01_schema.sql');
  const reference = read('db/baseline/03_reference_data.sql');
  const functions = read('db/baseline/02_functions.sql');

  assert.match(schema, /CREATE TABLE economic_account_policies/);
  assert.match(functions, /earth_validate_economic_account_capability/);
  assert.match(functions, /CREATE TRIGGER economic_accounts_capability_integrity/);
  assert.match(reference, /\('MARKET_ESCROW'\)/);
  assert.doesNotMatch(reference, /\bESCROW\b/);
  assert.doesNotMatch(schema, /\bESCROW\b/);
});

test('seeded capabilities allow House resources and institutional CREDIT only', () => {
  const reference = read('db/baseline/03_reference_data.sql');
  for (const row of [
    "('HOUSE', 'INVENTORY', 'RESOURCE'",
    "('HOUSE', 'MARKET_ESCROW', 'ANY'",
    "('CORPORATION', 'TREASURY', 'CREDIT'",
    "('EARTH', 'RESERVE', 'CREDIT'",
    "('BANK', 'OPERATIONS', 'CREDIT'",
    "('SYSTEM', 'SYSTEM_ACCOUNT', 'ANY'",
  ]) assert.match(reference, new RegExp(row.replace(/[()]/g, '\\$&')));
  assert.doesNotMatch(reference, /\('CORPORATION', 'INVENTORY'/);
  assert.doesNotMatch(reference, /\('EARTH', 'INVENTORY'/);
  assert.doesNotMatch(reference, /\('BANK', 'INVENTORY'/);
});

test('integrity reports detect invalid account capabilities and resource market owners', () => {
  const functions = read('db/baseline/02_functions.sql');
  assert.match(functions, /invalid_economic_account_capabilities/);
  assert.match(functions, /invalid_market_order_owners/);
  assert.match(functions, /market orders are House-only/);
  assert.match(functions, /market_orders_house_owner_integrity/);
});
