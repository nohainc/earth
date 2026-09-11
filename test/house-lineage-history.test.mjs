import assert from 'node:assert/strict';
import test from 'node:test';
import fs from 'node:fs';

const read = (path) => fs.readFileSync(path, 'utf8');

test('House lineage records form an explicit predecessor/successor history', () => {
  const schema = read('db/schema.sql');
  const migration = read('db/migrations/312_house_lineage_successor_links.sql');
  const lifecycle = read('cloudflare/src/lifecycle-postgres.ts');

  assert.match(schema, /predecessor_human_id TEXT REFERENCES humans\(id\)/);
  assert.match(schema, /successor_human_id TEXT REFERENCES humans\(id\)/);
  assert.match(migration, /successor_human_id TEXT REFERENCES humans\(id\)/);
  assert.match(migration, /successor\.generation = predecessor\.generation \+ 1/);
  assert.match(lifecycle, /successor_human_id = \$5/);
  assert.match(lifecycle, /predecessor_human_id, successor_human_id, generation/);
});
