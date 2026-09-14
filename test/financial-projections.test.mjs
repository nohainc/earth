import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const source = fs.readFileSync('cloudflare/src/financial-projections.ts', 'utf8');
const routes = fs.readFileSync('cloudflare/src/finance-routes.ts', 'utf8');

test('financial projections derive cash flow from the economic ledger', () => {
  assert.match(source, /economic_transactions/);
  assert.match(source, /economic_entries/);
  assert.match(source, /delta_units/);
  for (const field of ['cashBalanceUnits', 'incomeUnits', 'expenseUnits', 'taxUnits', 'loanUnits', 'netCashFlowUnits']) assert.match(source, new RegExp(field));
});

test('institution projections expose budget authority and ledger flow categories', () => {
  for (const field of ['authorizedUnits', 'committedUnits', 'spentUnits', 'availableUnits', 'revenueUnits', 'expenseUnits', 'byTransactionKind']) assert.match(source, new RegExp(field));
  assert.match(source, /owner_type IN/);
});

test('projection API exposes House, Corporation, and EARTH scopes', () => {
  assert.match(routes, /\/api\/finance\/projection/);
  for (const scope of ['HOUSE', 'CORPORATION', 'EARTH']) assert.match(routes, new RegExp(`scope === '${scope}'`));
});
