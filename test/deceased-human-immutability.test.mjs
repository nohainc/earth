import assert from 'node:assert/strict';
import test from 'node:test';
import fs from 'node:fs';

const read = (path) => fs.readFileSync(path, 'utf8');

test('deceased Humans are preserved as immutable historical profiles', () => {
  const migration = read('db/migrations/311_immutable_deceased_humans.sql');
  const lifecycle = read('cloudflare/src/lifecycle-postgres.ts');
  const schema = read('db/schema.sql');

  assert.match(migration, /BEFORE UPDATE ON humans/);
  assert.match(migration, /Deceased Human % is immutable historical data/);
  assert.match(migration, /final_age_years/);
  assert.match(migration, /major_titles JSONB/);
  assert.match(migration, /achievements JSONB/);
  assert.match(lifecycle, /final_age_years, final_standing, final_legacy/);
  assert.match(lifecycle, /JSON\.stringify\(majorTitles\)/);
  assert.match(schema, /final_age_years INTEGER/);
  assert.match(schema, /major_titles JSONB NOT NULL/);
});
