import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const migration = fs.readFileSync(new URL('../db/migrations/335_budget_insolvency_policy.sql', import.meta.url), 'utf8');
const schema = fs.readFileSync(new URL('../db/schema.sql', import.meta.url), 'utf8');
const spending = fs.readFileSync(new URL('../cloudflare/src/institution-spending.ts', import.meta.url), 'utf8');
const scheduler = fs.readFileSync(new URL('../cloudflare/src/scheduler-postgres.ts', import.meta.url), 'utf8');

test('financial stress freezes discretionary budget lines while preserving mandatory lines', () => {
  assert.match(migration, /'FROZEN'/);
  assert.match(migration, /spending_class = 'DISCRETIONARY'/);
  assert.match(migration, /spending_class = 'MANDATORY'/);
  assert.match(schema, /status IN \('DRAFT', 'ACTIVE', 'FROZEN'/);
  assert.match(spending, /Budget line is/);
});

test('commitments receive category priority and corporations liquidate separately', () => {
  assert.match(migration, /priority_class/);
  assert.match(migration, /earth_set_budget_commitment_priority/);
  assert.match(scheduler, /target === 'liquidation'/);
});
