import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const read = (file) => fs.readFileSync(file, 'utf8');

test('House perks persist while deceased Human heirloom equipment is cleared', () => {
  const migration = read('db/migrations/307_clear_deceased_heirloom_equipment.sql');
  const lifecycle = read('cloudflare/src/lifecycle-postgres.ts');
  const schema = read('db/schema.sql');

  assert.match(migration, /UPDATE house_heirlooms/);
  assert.match(migration, /equipped_by_human_id = NULL/);
  assert.match(lifecycle, /UPDATE house_heirlooms SET equipped_by_human_id = NULL/);
  assert.doesNotMatch(lifecycle, /UPDATE house_heirlooms SET equipped_by_human_id = \$1 WHERE house_id/);
  assert.match(schema, /house_perks/);
  assert.match(schema, /house_heirlooms/);
});
