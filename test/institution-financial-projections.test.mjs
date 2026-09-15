import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const read = (file) => fs.readFileSync(new URL(`../${file}`, import.meta.url), 'utf8');

test('institution financial projections derive from active V4 Economy V2 facts', () => {
  const projection = read('cloudflare/src/financial-projections.ts');
  const schema = read('db/baseline/01_schema.sql');
  assert.match(projection, /economic_transactions/);
  assert.match(projection, /economic_entries/);
  assert.match(projection, /economic_accounts/);
  assert.match(projection, /institution_budget_lines/);
  assert.match(schema, /CREATE TABLE institution_budget_lines/);
  assert.doesNotMatch(projection, /institution_financial_projections/);
});

test('institution finance routes use the canonical projection service', () => {
  const routes = read('cloudflare/src/finance-routes.ts');
  const budget = read('cloudflare/src/institution-budget-api.ts');
  assert.match(routes, /getInstitutionFinancialProjection\(repository, institutionId\)/);
  assert.match(budget, /getInstitutionFinancialProjection/);
  assert.doesNotMatch(routes, /FROM institution_financial_projections/);
  assert.doesNotMatch(budget, /FROM institution_financial_projections/);
});
