import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

test('dynasty fixture seed is safe before the canonical human seed', () => {
  const migration = fs.readFileSync('db/migrations/028_dynasty_lineage_and_heirlooms.sql', 'utf8');
  assert.match(migration, /IF EXISTS \(SELECT 1 FROM humans WHERE id = 'H-0044'\)/);
  assert.match(migration, /END\s*\$seed\$;/);
});
