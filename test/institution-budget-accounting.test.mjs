import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const fiscal = fs.readFileSync('cloudflare/src/corporation-fiscal-postgres.ts', 'utf8');
const budget = fs.readFileSync('cloudflare/src/institution-budget-api.ts', 'utf8');
const spending = fs.readFileSync('cloudflare/src/institution-spending.ts', 'utf8');

test('internal Corporation allocation does not count as external spending', () => {
  assert.match(fiscal, /'ASSET_TRANSFER', 'CORPORATION_INTERNAL'/);
  assert.match(fiscal, /internalAllocation: true/);
  assert.doesNotMatch(fiscal, /UPDATE institution_budget_lines SET spent_units/);
  assert.match(spending, /spent_units = spent_units \+ \$1/);
});

test('budget read models expose authority, cash, commitments, and spending', () => {
  for (const field of ['available_authority', 'available_cash', 'committed', 'spent']) assert.match(budget, new RegExp(field));
});
