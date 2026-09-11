import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

const read = (file) => fs.readFileSync(path.resolve(file), 'utf8');

test('House is the persistent principal and every Human has one House', () => {
  const migration = read('db/migrations/293_house_persistent_principal.sql');
  const schema = read('db/schema.sql');
  const manifest = JSON.parse(read('db/schema-manifest.json'));
  const auth = read('cloudflare/src/auth-postgres.ts');

  assert.match(migration, /ADD COLUMN IF NOT EXISTS account_id TEXT/);
  assert.match(migration, /ADD COLUMN IF NOT EXISTS current_human_id TEXT/);
  assert.match(migration, /ADD COLUMN IF NOT EXISTS dynasty_legacy BIGINT/);
  assert.match(migration, /ADD COLUMN IF NOT EXISTS generation INTEGER/);
  assert.match(migration, /ALTER COLUMN house_id SET NOT NULL/);
  assert.match(migration, /humans_one_active_per_house_idx/);
  assert.match(migration, /earth_validate_house_incumbent/);
  assert.match(migration, /House % already has active Human/);

  assert.match(schema, /house_id TEXT NOT NULL/);
  assert.match(schema, /account_id TEXT NOT NULL UNIQUE/);
  assert.match(schema, /current_human_id TEXT REFERENCES humans/);
  assert.ok(manifest.requiredTables.humans.includes('house_id'));
  assert.ok(manifest.requiredTables.houses.includes('account_id'));
  assert.ok(manifest.requiredTables.houses.includes('generation'));
  assert.ok(manifest.requiredTables.houses.includes('status'));

  assert.match(auth, /INSERT INTO houses \(id,account_id,email/);
  assert.match(auth, /INSERT INTO humans \(id,account_id,house_id/);
  assert.match(auth, /UPDATE houses SET current_human_id/);
  assert.match(auth, /SELECT id, house_name FROM houses WHERE account_id/);
});

test('seed fixtures attach all Humans to explicit Houses', () => {
  const seed = read('db/seed.sql');
  const humanInserts = [...seed.matchAll(/insert into humans \(([^)]+)\)/gi)].map((match) => match[1]);
  assert.ok(humanInserts.length > 0);
  for (const columns of humanInserts) assert.match(columns, /house_id/);
  assert.match(seed, /insert into houses \(id, account_id, email/);
});
