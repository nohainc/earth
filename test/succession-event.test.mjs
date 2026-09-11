import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const read = (file) => fs.readFileSync(file, 'utf8');

test('succession has one auditable event identity across the lifecycle', () => {
  const migration = read('db/migrations/309_succession_events.sql');
  const lifecycle = read('cloudflare/src/lifecycle-postgres.ts');
  const schema = read('db/schema.sql');

  assert.match(migration, /CREATE TABLE IF NOT EXISTS succession_events/);
  assert.match(migration, /status TEXT NOT NULL DEFAULT 'PREPARED'/);
  assert.match(lifecycle, /succession:\$\{human\.house_id\}:\$\{nextGeneration\}/);
  assert.match(lifecycle, /INSERT INTO succession_events/);
  assert.match(lifecycle, /house_legacy_before/);
  assert.match(lifecycle, /status = \\'COMPLETED\\'/);
  assert.match(schema, /succession_events/);
});
