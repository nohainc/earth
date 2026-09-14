import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const read = (file) => fs.readFileSync(file, 'utf8');

test('authoritative CREDIT services use exact CreditUnits parsing', () => {
  const money = read('cloudflare/src/money.ts');
  assert.match(money, /export type CreditUnits = bigint/);
  assert.match(money, /export function parseCreditAmount/);
  assert.match(money, /export function formatCreditUnits/);
  for (const file of ['cloudflare/src/financial-postgres.ts', 'cloudflare/src/corporation-building-research-postgres.ts']) {
    const source = read(file);
    assert.doesNotMatch(source, /Number\([^\n]*amount[^\n]*\)\s*\*\s*100/);
    assert.doesNotMatch(source, /Math\.round\([^\n]*cost[^\n]*\*\s*100/);
  }
});

test('financial ownership resolves explicit principals and purposes', () => {
  const finance = read('cloudflare/src/financial-postgres.ts');
  const resolver = read('cloudflare/src/economic-account-resolver.ts');
  assert.match(resolver, /export async function resolveEconomicAccount/);
  assert.match(resolver, /principalId/);
  assert.match(resolver, /accountPurpose/);
  assert.match(resolver, /asset\.code=\$3/);
  assert.doesNotMatch(finance, /account-ouc-treasury|account-global-bank|startsWith\('account-'/);
});
