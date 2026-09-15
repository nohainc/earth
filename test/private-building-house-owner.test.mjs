import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

const read = (file) => fs.readFileSync(path.resolve(file), 'utf8');

test('private buildings keep House economic ownership across succession', () => {
  const schema = read('db/baseline/01_schema.sql');
  const lifecycle = read('cloudflare/src/lifecycle-postgres.ts');
  const settlement = read('cloudflare/src/building-settlement-v2.ts');

  assert.match(schema, /owner_economic_id TEXT NOT NULL REFERENCES owner_registry\(economic_id\)/);
  assert.doesNotMatch(schema, /private_owner_id/);
  assert.doesNotMatch(lifecycle, /UPDATE buildings SET owner_id = \$1 WHERE owner_id = \$2/);
  assert.match(settlement, /owner_economic_id/);
  assert.doesNotMatch(settlement, /private_owner_id/);
  assert.doesNotMatch(lifecycle, /UPDATE buildings SET owner_id/);
});
