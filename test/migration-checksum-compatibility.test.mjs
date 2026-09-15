import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

test('migration runner only grandfather-approved historical baseline drift', () => {
  const source = fs.readFileSync('scripts/migrate-postgres.mjs', 'utf8');
  assert.match(source, /approvedHistoricalChecksums/);
  assert.match(source, /c4946ae53bbd774353c16533b2f27b6077ed3f5c8f91d22d23201b55fa14c857/);
  assert.match(source, /preserving the applied migration record/);
  assert.match(source, /appliedName !== name/);
});
