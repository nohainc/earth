import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

const read = (file) => fs.readFileSync(path.resolve(file), 'utf8');

test('city spending keeps its explicit treasury source while respecting optional parent ceilings', () => {
  const spending = read('cloudflare/src/institution-spending.ts');
  const allocation = read('db/migrations/324_institution_budget_allocations.sql');
  assert.match(spending, /sourceAccountId/);
  assert.match(spending, /institution_budget_allocations/);
  assert.match(spending, /Spending exceeds the corporation allocation ceiling/);
  assert.match(allocation, /parent_institution_id/);
  assert.match(allocation, /child_institution_id/);
  assert.doesNotMatch(spending, /account-corporation|account_balances|corporations\.treasury/);
});
