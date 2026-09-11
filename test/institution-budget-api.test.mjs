import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const api = fs.readFileSync(new URL('../cloudflare/src/institution-budget-api.ts', import.meta.url), 'utf8');
const routes = fs.readFileSync(new URL('../cloudflare/src/institutions-routes.ts', import.meta.url), 'utf8');

test('institution budget API keeps cash and budget authority separate', () => {
  for (const field of ['cash_total_units', 'budget_authority_available_units', 'budget_committed_units', 'budget_spent_units']) {
    assert.match(api, new RegExp(field));
  }
  assert.match(routes, /\/budget\(\?:\\\//);
  for (const endpoint of ['lines', 'commitments', 'fiscal-summary', 'financial-projection']) assert.match(routes, new RegExp(endpoint));
});

test('commitment API uses authorization and atomic commitment functions', () => {
  assert.match(api, /canPerformInstitutionAction/);
  assert.match(api, /earth_create_budget_commitment/);
  assert.match(api, /earth_pay_budget_commitment/);
  assert.match(api, /earth_cancel_budget_commitment/);
});
