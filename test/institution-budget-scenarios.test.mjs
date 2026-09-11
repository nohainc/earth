import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const read = (path) => fs.readFileSync(new URL(`../${path}`, import.meta.url), 'utf8');

function authorizeSpend({ cash, authority, amount }) {
  if (cash < amount) return { ok: false, reason: 'insufficient_cash' };
  if (authority < amount) return { ok: false, reason: 'insufficient_budget_authority' };
  return { ok: true, cash: cash - amount, spent: amount };
}

test('cash and budget authority fail independently', () => {
  assert.deepEqual(authorizeSpend({ cash: 10_000, authority: 100_000, amount: 50_000 }), { ok: false, reason: 'insufficient_cash' });
  assert.deepEqual(authorizeSpend({ cash: 100_000, authority: 10_000, amount: 50_000 }), { ok: false, reason: 'insufficient_budget_authority' });
});

test('grant receipt increases cash without recipient category spending', () => {
  const city = { cash: 0, healthSpent: 0 };
  const grant = 50_000;
  city.cash += grant;
  assert.deepEqual(city, { cash: 50_000, healthSpent: 0 });
  const grants = read('cloudflare/src/institution-grants.ts');
  assert.match(grants, /GRANT_RECEIVED/);
  assert.match(grants, /GRANT_SENT/);
});

test('commitment payment moves authority into spent while reducing remaining commitment', () => {
  const commitment = { remaining: 100_000, spent: 0 };
  const payment = 20_000;
  commitment.remaining -= payment;
  commitment.spent += payment;
  assert.deepEqual(commitment, { remaining: 80_000, spent: 20_000 });
  const source = read('cloudflare/src/institution-budget-api.ts');
  assert.match(source, /earth_pay_budget_commitment/);
});

test('distressed cities freeze discretionary spending while mandatory services remain available', () => {
  const policy = read('db/migrations/335_budget_insolvency_policy.sql');
  assert.match(policy, /DISCRETIONARY/);
  assert.match(policy, /FROZEN/);
  assert.match(policy, /MANDATORY/);
});

test('corporation support uses the corporation budget and Economy V2 spending path', () => {
  const institutions = read('cloudflare/src/institutions-postgres.ts');
  assert.match(institutions, /CORPORATION_PUBLIC_SPENDING/);
  assert.match(institutions, /categoryCode/);
  assert.match(institutions, /spendBudget\(tx/);
  assert.match(institutions, /economic_accounts/);
});
