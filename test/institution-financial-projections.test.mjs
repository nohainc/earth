import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const migration = fs.readFileSync(new URL('../db/migrations/337_institution_financial_projections.sql', import.meta.url), 'utf8');
const schema = fs.readFileSync(new URL('../db/schema.sql', import.meta.url), 'utf8');
const scheduler = fs.readFileSync(new URL('../cloudflare/src/scheduler-postgres.ts', import.meta.url), 'utf8');
const routes = fs.readFileSync(new URL('../cloudflare/src/finance-routes.ts', import.meta.url), 'utf8');

test('institution financial projections expose fast city and corporation read models', () => {
  for (const source of [migration, schema]) {
    assert.match(source, /institution_financial_summary/);
    assert.match(source, /period_revenue_units/);
    assert.match(source, /budget_authorized_units/);
    assert.match(source, /mandatory_commitments_units/);
    assert.match(source, /liquidity_days/);
    assert.match(source, /institution_financial_projections/);
  }
  for (const field of ['cash_treasury_units', 'cash_operations_units', 'cash_reserve_units', 'tax_receivable_units', 'surplus_deficit_units', 'financial_state']) {
    assert.match(schema, new RegExp(field));
  }
  for (const field of ['research_commitments_units', 'city_support_commitments_units', 'dividend_capacity_units']) {
    assert.match(migration, new RegExp(field));
  }
});

test('financial projections refresh after the canonical daily projection step', () => {
  assert.match(scheduler, /earth_refresh_daily_financial_projections/);
  assert.match(scheduler, /earth_refresh_institution_financial_projection_fields/);
  assert.match(routes, /institution_financial_projections/);
});
