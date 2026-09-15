import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const schema = fs.readFileSync('db/baseline/01_schema.sql', 'utf8');
const functions = fs.readFileSync('db/baseline/02_functions.sql', 'utf8');
const migration = fs.readFileSync('db/migrations/016_house_daily_statements.sql', 'utf8');
const scheduler = fs.readFileSync('cloudflare/src/scheduler-postgres.ts', 'utf8');
const summary = fs.readFileSync('cloudflare/src/house-daily-summary-postgres.ts', 'utf8');

test('daily House statement has canonical balances and reconciliation components', () => {
  for (const column of ['opening_assets', 'closing_assets', 'production', 'consumption', 'market_activity', 'obligations', 'exceptions', 'net_credit_units']) {
    assert.match(schema, new RegExp(`${column} JSONB|${column} BIGINT`));
    assert.match(migration, new RegExp(column));
  }
  assert.match(functions, /earth_refresh_house_daily_statements/);
  assert.match(migration, /economic_entries/);
  assert.match(migration, /market_fills/);
  assert.match(migration, /tax_obligations/);
  assert.match(migration, /personal_life_maintenance/);
});

test('daily House statements are refreshed only after required settlement work', () => {
  assert.match(scheduler, /refreshHouseDailyStatementsInTransaction/);
  assert.match(summary, /earth_refresh_house_daily_statements/);
  assert.match(scheduler, /endOfDaySnapshots:[\s\S]*refreshHouseDailyStatementsInTransaction/);
});
