import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

test('House succession has no implicit inheritance tax', () => {
  const lifecycle = fs.readFileSync('cloudflare/src/lifecycle-postgres.ts', 'utf8');

  assert.doesNotMatch(lifecycle, /taxToCents/);
  assert.doesNotMatch(lifecycle, /inheritance_tax|late_inheritance_tax/);
  assert.match(lifecycle, /successionLevy: 0/);
});
