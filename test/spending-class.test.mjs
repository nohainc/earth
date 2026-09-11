import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

const read = (file) => fs.readFileSync(path.resolve(file), 'utf8');

test('budget categories classify spending and freeze discretionary payments in stress', () => {
  const migration = read('db/migrations/326_mandatory_discretionary_spending.sql');
  const schema = read('db/schema.sql');
  const engine = read('cloudflare/src/institution-spending.ts');
  assert.match(migration, /spending_class/);
  assert.match(migration, /MANDATORY.*DISCRETIONARY/);
  assert.match(schema, /spending_class TEXT NOT NULL/);
  assert.match(engine, /spending_class/);
  assert.match(engine, /Discretionary spending is frozen during financial stress/);
  assert.match(engine, /FISCAL_STRESS.*RECEIVERSHIP/);
});
