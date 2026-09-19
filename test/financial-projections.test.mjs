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

test('House projections include the canonical V5 capacity fiscal read model', () => {
  assert.match(source, /getV5HouseCapacity/);
  assert.match(source, /capacitySource/);
  assert.match(source, /unavailable-canonical-capacity-read-model/);
});

test('House next-settlement projection is separate from historical ledger totals', () => {
  assert.match(source, /getHouseNextSettlementProjection/);
  assert.match(source, /KNOWN_OBLIGATIONS_AND_PREDICTABLE_FLOWS/);
  for (const table of ['financial_obligations', 'v5_capacity_obligations', 'bank_loan_schedules', 'technology_license_contracts', 'bank_deposits']) {
    assert.match(source, new RegExp(table));
  }
  assert.match(source, /BUILDING_OPERATING_EXPENSE/);
  assert.match(source, /otherObligations/);
});
