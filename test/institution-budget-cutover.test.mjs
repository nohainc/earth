import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const read = (path) => fs.readFileSync(new URL(`../${path}`, import.meta.url), 'utf8');

test('active V4 baseline has generic budget authority and no legacy budget table', () => {
  const schema = read('db/baseline/01_schema.sql');
  assert.match(schema, /CREATE TABLE institution_budget_lines/);
  assert.match(schema, /CREATE TABLE institution_budget_commitments/);
  assert.doesNotMatch(schema, /CREATE TABLE .*\bbudgets\b/);
});

test('institution spending has one generic Economy V2 entry point', () => {
  const spending = read('cloudflare/src/institution-spending.ts');
  const grants = read('cloudflare/src/institution-grants.ts');

  assert.match(spending, /export async function spendInstitutionBudget/);
  assert.match(grants, /spendBudget\(tx/);
  assert.doesNotMatch(spending, /account_balances|resource_balances|ledger_entries/i);
});

test('institution cash remains Economy V2 and is not a scalar treasury authority', () => {
  const schema = read('db/baseline/01_schema.sql');
  const spending = read('cloudflare/src/institution-spending.ts');

  assert.match(schema, /CREATE TABLE economic_accounts/);
  assert.match(schema, /CREATE TABLE economic_transactions/);
  assert.match(spending, /FROM economic_accounts/);
  assert.match(spending, /earth_post_transaction/);
});

test('Territory capacity is a rebuildable V4 projection', () => {
  const capacity = read('db/baseline/01_schema.sql');
  const functions = read('db/baseline/02_functions.sql');
  const scheduler = read('cloudflare/src/scheduler-postgres.ts');

  assert.match(capacity, /CREATE TABLE territory_capacity_state/);
  assert.match(functions, /earth_refresh_territory_capacity/);
  assert.match(scheduler, /territoryCapacityProjections/);
  assert.doesNotMatch(scheduler, /city_service_capacity_daily/);
});

test('legacy budget and direct treasury paths are absent from current institutional modules', () => {
  const source = [
    read('cloudflare/src/institutions-postgres.ts'),
    read('cloudflare/src/institution-budget-api.ts'),
  ].join('\n');

  assert.doesNotMatch(source, /FROM budgets|UPDATE budgets|INTO budgets/i);
  assert.doesNotMatch(source, /UPDATE\s+(cities|corporations)\s+SET\s+treasury/i);
  assert.doesNotMatch(source, /continuous-budget-engine/i);
  assert.match(source, /institution_budget_lines/);
  assert.doesNotMatch(source, /institution_financial_projections/);
});
