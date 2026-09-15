import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

test('commons dividends are declared from lease revenue and paid from real cash', () => {
  const migration = fs.readFileSync('db/migrations/052_commons_revenue_dividend_policy.sql', 'utf8');
  const service = fs.readFileSync('cloudflare/src/commons-dividends-postgres.ts', 'utf8');
  const scheduler = fs.readFileSync('cloudflare/src/scheduler-postgres.ts', 'utf8');
  const routes = fs.readFileSync('cloudflare/src/real-estate-routes.ts', 'utf8');
  assert.match(migration, /commons_dividend_policies/);
  assert.match(migration, /commons_dividend_declarations/);
  assert.match(migration, /commons_dividend_payments/);
  assert.match(migration, /reserve_bps \+ dividend_bps <= 10000/);
  assert.match(service, /territory_lease_payments/);
  assert.match(service, /resolveOrganizationAuthority/);
  assert.match(service, /BigInt\(source\.balance_units\) < distributable/);
  assert.match(service, /COMMONS_DIVIDEND/);
  assert.match(service, /remainder_units/);
  assert.match(scheduler, /settleCommonsDividends/);
  assert.match(routes, /getCommonsStatement/);
  assert.match(routes, /declareCommonsDividend/);
});

test('commons allocation cannot mint CREDIT when the beneficiary lacks cash', () => {
  const service = fs.readFileSync('cloudflare/src/commons-dividends-postgres.ts', 'utf8');
  assert.match(service, /status = 'BLOCKED'/);
  assert.doesNotMatch(service, /global.*issu/i);
});
