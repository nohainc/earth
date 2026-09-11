import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const read = (file) => fs.readFileSync(file, 'utf8');

test('community membership follows House while Human authority ends', () => {
  const migration = read('db/migrations/306_house_community_membership.sql');
  const lifecycle = read('cloudflare/src/lifecycle-postgres.ts');
  const communities = read('cloudflare/src/communities-postgres.ts');
  const schema = read('db/schema.sql');

  assert.match(migration, /ADD COLUMN IF NOT EXISTS house_id/);
  assert.match(migration, /PRIMARY KEY \(community_id, house_id\)/);
  assert.match(lifecycle, /UPDATE community_members SET role = 'member'/);
  assert.match(lifecycle, /UPDATE community_members SET human_id = \$1 WHERE house_id = \$2/);
  assert.match(communities, /INSERT INTO community_members \(community_id, house_id, human_id/);
  assert.match(communities, /ON CONFLICT \(community_id, house_id\)/);
  assert.match(schema, /house_id TEXT NOT NULL REFERENCES houses\(id\)/);
  assert.match(schema, /PRIMARY KEY \(community_id, house_id\)/);
});
