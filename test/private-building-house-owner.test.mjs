import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

const read = (file) => fs.readFileSync(path.resolve(file), 'utf8');

test('private buildings keep House economic ownership across succession', () => {
  const migration = read('db/migrations/296_private_buildings_house_owner.sql');
  const schema = read('db/schema.sql');
  const lifecycle = read('cloudflare/src/lifecycle-postgres.ts');
  const settlement = read('cloudflare/src/building-settlement-v2.ts');

  assert.match(migration, /ADD COLUMN IF NOT EXISTS owner_economic_id BIGINT/);
  assert.match(migration, /buildings_private_house_owner_ck/);
  assert.match(migration, /earth_sync_private_building_house_owner/);
  assert.match(schema, /owner_economic_id BIGINT REFERENCES owner_registry\(economic_id\)/);
  assert.match(schema, /managed_by_human_id TEXT REFERENCES humans/);
  assert.doesNotMatch(lifecycle, /UPDATE buildings SET owner_id = \$1 WHERE owner_id = \$2/);
  assert.match(settlement, /private_owner_id/);
  assert.doesNotMatch(lifecycle, /UPDATE buildings SET owner_id/);
});
