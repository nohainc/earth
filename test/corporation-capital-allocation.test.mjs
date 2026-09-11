import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

const read = (file) => fs.readFileSync(path.resolve(file), 'utf8');

test('corporation dividend capacity subtracts obligations and reserve from cash', () => {
  const migration = read('db/migrations/325_corporation_capital_allocation.sql');
  const schema = read('db/schema.sql');
  assert.match(migration, /'CORPORATION', 'RESERVE'/);
  assert.match(migration, /earth_corporation_distributable_surplus/);
  assert.match(migration, /mandatory_commitments/);
  assert.match(migration, /tax_due/);
  assert.match(migration, /loan_due/);
  assert.match(migration, /required_reserve_units/);
  assert.match(migration, /GREATEST\(0, cash_units - mandatory_commitments - tax_due - loan_due - required_reserve_units\)/);
  assert.match(schema, /'CORPORATION', 'RESERVE'/);
});
