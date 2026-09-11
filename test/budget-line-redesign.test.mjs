import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

const read = (file) => fs.readFileSync(path.resolve(file), 'utf8');

test('budget line redesign has stable IDs, category references, lifecycle state, and creation day', () => {
  const migration = read('db/migrations/319_budget_line_redesign.sql');
  const schema = read('db/schema.sql');
  assert.match(migration, /ADD COLUMN IF NOT EXISTS id BIGINT GENERATED ALWAYS AS IDENTITY/);
  assert.match(migration, /ADD COLUMN IF NOT EXISTS category_id BIGINT/);
  assert.match(migration, /ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'ACTIVE'/);
  assert.match(migration, /ADD COLUMN IF NOT EXISTS created_game_day BIGINT/);
  assert.match(migration, /authorized_units >= committed_units \+ spent_units/);
  assert.match(migration, /DROP COLUMN IF EXISTS category/);
  const lineBlock = schema.match(/CREATE TABLE IF NOT EXISTS institution_budget_lines \((?:.|\n)*?\n\);/s)?.[0] ?? '';
  assert.match(lineBlock, /id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY/);
  assert.match(lineBlock, /category_id BIGINT NOT NULL REFERENCES budget_categories\(id\)/);
  assert.match(lineBlock, /created_game_day BIGINT NOT NULL/);
  assert.doesNotMatch(lineBlock, /institution_kind|category_code|\bcategory\b/);
});

test('budget spending treats committed units as outstanding authority and spent units as paid', () => {
  const institutions = read('cloudflare/src/institutions-postgres.ts');
  const finance = read('cloudflare/src/finance-postgres.ts');
  assert.match(institutions, /authorized_units\) - BigInt\(budget\.rows\[0\]\.committed_units\) - BigInt\(budget\.rows\[0\]\.spent_units\)/);
  assert.match(finance, /authorized_units\) - BigInt\(budget\.rows\[0\]\.committed_units\) - BigInt\(budget\.rows\[0\]\.spent_units\)/);
  const spendingEngine = fs.readFileSync(path.resolve('cloudflare/src/institution-spending.ts'), 'utf8');
  assert.match(spendingEngine, /SET spent_units = spent_units \+ \$1/);
  assert.doesNotMatch(spendingEngine, /SET committed_units = committed_units \+ \$1, spent_units = spent_units \+ \$1/);
  assert.doesNotMatch(finance, /SET committed_units = committed_units \+ \$1, spent_units = spent_units \+ \$1/);
});
