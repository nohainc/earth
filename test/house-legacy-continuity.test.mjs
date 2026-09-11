import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const read = (file) => fs.readFileSync(file, 'utf8');

test('succession separates personal standing from House legacy', () => {
  const lifecycle = read('cloudflare/src/lifecycle-postgres.ts');

  const houseMortality = lifecycle.slice(
    lifecycle.indexOf('export async function processHouseMortality'),
    lifecycle.indexOf('export async function activatePendingHouseSuccessors'),
  );
  assert.match(houseMortality, /legacyContribution = Math\.max\(0, Math\.floor\(Number\(human\.legacy\) \* 0\.25\)\)/);
  assert.match(houseMortality, /UPDATE houses SET dynasty_legacy = dynasty_legacy \+ \$1/);
  assert.match(houseMortality, /legacy_score = \$3/);
  assert.match(houseMortality, /standing, legacy, life_status/);
  assert.match(houseMortality, /successorName, emergency \? -100 : 0, 0,/);
  assert.match(houseMortality, /houseLegacyContribution: legacyContribution/);
});
