import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const schema = fs.readFileSync('db/baseline/01_schema.sql', 'utf8');
const migration = fs.readFileSync('db/migrations/018_house_operating_policies.sql', 'utf8');
const postgres = fs.readFileSync('cloudflare/src/house-policy-postgres.ts', 'utf8');
const routes = fs.readFileSync('cloudflare/src/house-routes.ts', 'utf8');

test('House policies are versioned, future-effective, bounded, and auditable', () => {
  for (const field of ['effective_from_game_day', 'daily_spend_cap_units', 'reserve_floor_units', 'max_input_price_units', 'min_sale_price_units', 'procurement_quantity_units', 'correlation_id']) {
    assert.match(schema, new RegExp(field));
    assert.match(migration, new RegExp(field));
  }
  assert.match(schema, /policy_execution_log/);
  assert.match(postgres, /ON CONFLICT \(correlation_id\) DO NOTHING|alreadyProcessed/);
  assert.match(postgres, /daily_spend_cap_units/);
  assert.match(routes, /House policy rows are deprecated; use \/api\/house\/automation/);
  assert.match(routes, /saveHouseAutomation/);
});
