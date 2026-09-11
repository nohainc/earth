import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const read = (file) => fs.readFileSync(file, 'utf8');

test('budget lines reference configurable fiscal periods', () => {
  const migration = read('db/migrations/317_fiscal_periods.sql');
  const schema = read('db/schema.sql');
  const source = [
    read('cloudflare/src/finance-postgres.ts'),
    read('cloudflare/src/institutions-postgres.ts'),
    read('cloudflare/src/civic-dividend-engine.ts'),
    read('cloudflare/src/engines/institutions-engine.ts'),
    read('cloudflare/src/read-postgres.ts'),
  ].join('\n');

  assert.match(migration, /CREATE TABLE IF NOT EXISTS fiscal_periods/);
  assert.match(migration, /earth_fiscal_period_for_day/);
  assert.match(migration, /standard_length_game_days/);
  assert.match(migration, /DROP COLUMN IF EXISTS game_period/);
  assert.match(schema, /CREATE TABLE IF NOT EXISTS fiscal_periods/);
  assert.match(schema, /fiscal_period_id BIGINT NOT NULL REFERENCES fiscal_periods/);
  assert.doesNotMatch(schema, /institution_budget_lines[\s\S]{0,300}game_period/);
  assert.doesNotMatch(source, /institution_budget_lines[^\n]*game_period|game_period[^\n]*institution_budget_lines/);
  assert.match(source, /earth_fiscal_period_for_day/);
});
