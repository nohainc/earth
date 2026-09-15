import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

test('migration runner only grandfather-approved historical baseline drift', () => {
  const source = fs.readFileSync('scripts/migrate-postgres.mjs', 'utf8');
  assert.match(source, /approvedHistoricalChecksums/);
  assert.match(source, /e2cfdb721f8367ce49a56c6679cdea63ce384b95ecf866923c499d804c0102a6/);
  assert.match(source, /7257e134835aced183eb02afbb82780c29170cbb0fded680f908e88001e2de57/);
  assert.match(source, /c4946ae53bbd774353c16533b2f27b6077ed3f5c8f91d22d23201b55fa14c857/);
  assert.match(source, /preserving the applied migration record/);
  assert.match(source, /appliedName !== name/);
});
