import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

test('baseline seed order is dependency-safe and contains no demo actors', () => {
  const baseline = fs.readFileSync('db/migrations/001_baseline.sql', 'utf8');
  assert.match(baseline, /SECTION 1: SCHEMA/);
  assert.match(baseline, /SECTION 3: REFERENCE DATA/);
  assert.match(baseline, /SECTION 4: INITIAL WORLD/);
  assert.doesNotMatch(baseline, /H-0044|fake|demo/i);
});
