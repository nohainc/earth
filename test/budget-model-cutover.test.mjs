import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const read = (file) => fs.readFileSync(file, 'utf8');

test('institution budget lines are the sole current budget model', () => {
  const migration = read('db/migrations/316_remove_legacy_budgets.sql');
  const schema = read('db/schema.sql');
  const source = [
    read('cloudflare/src/engines/institutions-engine.ts'),
    read('cloudflare/src/finance-postgres.ts'),
    read('cloudflare/src/institutions-postgres.ts'),
    read('cloudflare/src/civic-dividend-engine.ts'),
    read('cloudflare/src/read-postgres.ts'),
  ].join('\n');

  assert.match(migration, /institution_budget_lines/);
  assert.match(migration, /DROP TABLE budgets/);
  assert.match(migration, /ROUND\(b\.amount \* 100\)/);
  assert.match(schema, /CREATE TABLE IF NOT EXISTS institution_budget_lines/);
  assert.doesNotMatch(schema, /CREATE TABLE IF NOT EXISTS budgets/);
  assert.doesNotMatch(source, /FROM budgets|UPDATE budgets|INTO budgets/);
  assert.match(source, /institution_budget_lines/);
});
