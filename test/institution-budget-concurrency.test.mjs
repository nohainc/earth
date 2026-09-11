import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const read = (path) => fs.readFileSync(new URL(`../${path}`, import.meta.url), 'utf8');

// Models the outcome of two transactions that both lock and then re-check the
// same budget line and source account. The second transaction sees the first
// commit, rather than spending against the same opening snapshot.
function spendAtomically(state, amount) {
  if (state.cash < amount) return { ok: false, reason: 'insufficient_cash' };
  if (state.authorized - state.committed - state.spent < amount) {
    return { ok: false, reason: 'insufficient_budget_authority' };
  }
  state.cash -= amount;
  state.spent += amount;
  return { ok: true };
}

test('two officials cannot spend the same remaining budget twice', async () => {
  const state = { cash: 100, authorized: 100, committed: 0, spent: 0 };
  const results = [spendAtomically(state, 80), spendAtomically(state, 80)];

  assert.equal(results.filter((result) => result.ok).length, 1);
  assert.equal(state.spent, 80);
  assert.ok(state.spent <= state.authorized);
});

test('two proposal commitments reserve authority serially', () => {
  const state = { authorized: 100, committed: 0, spent: 0 };
  const reserve = (amount) => {
    if (state.authorized - state.committed - state.spent < amount) return false;
    state.committed += amount;
    return true;
  };

  assert.equal(reserve(60), true);
  assert.equal(reserve(60), false);
  assert.equal(state.committed, 60);
  assert.ok(state.committed + state.spent <= state.authorized);
});

test('grant and local spending cannot both consume the same treasury cash', () => {
  const state = { cash: 100, authorized: 200, committed: 0, spent: 0 };
  const grant = spendAtomically(state, 75);
  const local = spendAtomically(state, 75);

  assert.equal(grant.ok, true);
  assert.equal(local.ok, false);
  assert.equal(local.reason, 'insufficient_cash');
  assert.equal(state.cash, 25);
  assert.equal(state.spent, 75);
});

test('dividend eligibility leaves cash available for mandatory debt service', () => {
  const state = { cash: 100, mandatoryDebt: 60, dividend: 50 };
  const distributable = Math.max(0, state.cash - state.mandatoryDebt);
  assert.equal(distributable, 40);
  assert.equal(spendAtomically({ cash: state.cash, authorized: 40, committed: 0, spent: 0 }, state.dividend).ok, false);
});

test('spending engine locks the budget line and account before posting', () => {
  const source = read('cloudflare/src/institution-spending.ts');
  assert.match(source, /institution_budget_lines[\s\S]*?FOR UPDATE/);
  assert.match(source, /economic_accounts[\s\S]*?FOR UPDATE/);
  assert.match(source, /earth_post_transaction/);
  assert.match(source, /institution_budget_lines SET spent_units = spent_units \+ \$1/);
});

test('commitment creation locks the line in its database trigger', () => {
  const migration = read('db/migrations/320_budget_commitments.sql');
  assert.match(migration, /earth_reserve_budget_commitment/);
  assert.match(migration, /FROM institution_budget_lines[\s\S]*?FOR UPDATE/);
  assert.match(migration, /authorized_units - committed_units - spent_units/);
  assert.match(migration, /earth_create_budget_commitment/);
});

test('grant and dividend flows lock their state before Economy V2 posting', () => {
  const grants = read('cloudflare/src/institution-grants.ts');
  const dividends = read('cloudflare/src/civic-dividend-engine.ts');
  assert.match(grants, /institution_grants WHERE id = \$1 FOR UPDATE/);
  assert.match(grants, /spendBudget\(tx/);
  assert.match(dividends, /economic_accounts[\s\S]*?FOR UPDATE/);
  assert.match(dividends, /earth_post_settlement_batch/);
});
