import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

test('baseline seed order is dependency-safe and contains no demo actors', () => {
  const baseline = fs.readFileSync('db/migrations/001_baseline.sql', 'utf8');
  assert.match(baseline, /SECTION 1: SCHEMA/);
  assert.match(baseline, /SECTION 3: REFERENCE DATA/);
  assert.match(baseline, /SECTION 4: INITIAL WORLD/);
  assert.doesNotMatch(baseline, /H-0044|fake|demo/i);
});

test('temporary forward migrations are numbered, marked active, and contiguous', () => {
  const migrationDir = 'db/migrations';
  const files = fs.readdirSync(migrationDir)
    .filter((name) => /^\d+_.+\.sql$/.test(name))
    .sort((a, b) => Number(a.match(/^\d+/)[0]) - Number(b.match(/^\d+/)[0]));
  const active = files.filter((name) => fs.readFileSync(path.join(migrationDir, name), 'utf8').includes('-- EARTH ACTIVE MIGRATION:'));
  assert.equal(active[0], '001_baseline.sql');
  const versions = active.map((name) => Number(name.match(/^\d+/)[0]));
  versions.forEach((version, index) => assert.equal(version, index + 1));
  assert.ok(active.length >= 1);
});
