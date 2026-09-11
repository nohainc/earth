import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const institutions = fs.readFileSync(new URL('../cloudflare/src/institutions-postgres.ts', import.meta.url), 'utf8');
const spending = fs.readFileSync(new URL('../cloudflare/src/institution-spending.ts', import.meta.url), 'utf8');
const grants = fs.readFileSync(new URL('../cloudflare/src/institution-grants.ts', import.meta.url), 'utf8');

test('institution finance uses Economy V2 accounts and transactions only', () => {
  for (const source of [institutions, spending, grants]) {
    assert.doesNotMatch(source, /account_balances|account-city-|account-corporation-|cities\.treasury|corporations\.treasury|continuous-budget-engine/i);
  }
  assert.match(institutions, /earth_post_transaction/);
  assert.match(spending, /economic_accounts/);
});
