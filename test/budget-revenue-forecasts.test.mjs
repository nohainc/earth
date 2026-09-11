import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const migration = fs.readFileSync('db/migrations/328_budget_revenue_forecasts.sql', 'utf8');
const schema = fs.readFileSync('db/schema.sql', 'utf8');

test('budget revenue forecasts are advisory fiscal-period projections', () => {
  for (const column of ['opening_cash_units', 'forecast_revenue_units', 'minimum_closing_reserve_units', 'recommended_spending_ceiling_units', 'authorized_spending_units', 'actual_revenue_units', 'actual_spending_units', 'planned_deficit_units', 'fiscal_surplus_deficit_units']) {
    assert.match(migration, new RegExp(column));
    assert.match(schema, new RegExp(column));
  }
  assert.match(migration, /v_opening_cash_units \+ p_forecast_revenue_units - p_minimum_closing_reserve_units/);
  assert.match(migration, /earth_set_budget_revenue_forecast/);
  assert.match(migration, /p_authorized_spending_units - p_forecast_revenue_units/);
  assert.match(migration, /actual_revenue_units - v_actual_spending_units/);
  assert.match(migration, /earth_refresh_fiscal_budget_forecast/);
  assert.match(migration, /deficits are reporting values/);
  assert.doesNotMatch(migration, /UPDATE institution_budget_lines/);
});
