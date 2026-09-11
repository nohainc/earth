import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const read = (file) => fs.readFileSync(file, 'utf8');

test('budget categories are canonical and institution-scoped', () => {
  const migration = read('db/migrations/318_budget_categories.sql');
  const schema = read('db/schema.sql');
  const source = [
    read('cloudflare/src/finance-postgres.ts'),
    read('cloudflare/src/institutions-postgres.ts'),
    read('cloudflare/src/engines/institutions-engine.ts'),
  ].join('\n');

  assert.match(migration, /CREATE TABLE IF NOT EXISTS budget_categories/);
  assert.match(migration, /FOREIGN KEY \(institution_kind, category_code\)/);
  assert.match(migration, /earth_validate_budget_line_institution_kind/);
  assert.match(schema, /CREATE TABLE IF NOT EXISTS budget_categories/);
  assert.match(schema, /category_code TEXT NOT NULL/);
  assert.doesNotMatch(source, /institution_budget_lines[^\n]*category =/);
  assert.match(source, /category_code/);
});
