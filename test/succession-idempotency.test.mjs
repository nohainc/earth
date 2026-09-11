import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const read = (file) => fs.readFileSync(file, 'utf8');

test('mortality and succession use deterministic idempotency keys', () => {
  const migration = read('db/migrations/310_succession_idempotency.sql');
  const lifecycle = read('cloudflare/src/lifecycle-postgres.ts');

  assert.match(lifecycle, /death:\$\{human\.id\}:\$\{day\}/);
  assert.match(lifecycle, /succession:\$\{human\.house_id\}:\$\{nextGeneration\}/);
  assert.match(lifecycle, /status === 'COMPLETED'/);
  assert.match(lifecycle, /H-\$\{human\.house_id\}-\$\{nextGeneration\}/);
  assert.match(lifecycle, /LINEAGE-\$\{human\.house_id\}-\$\{nextGeneration\}/);
  assert.match(lifecycle, /NOTIFICATION-\$\{successionCorrelation\}/);
  assert.match(migration, /house_lineage_records_house_generation_idx/);
});
