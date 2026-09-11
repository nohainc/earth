import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

const read = (file) => fs.readFileSync(path.resolve(file), 'utf8');

test('Building V2 settles House-owned assets without Human succession gating', () => {
  const building = read('cloudflare/src/building-settlement-v2.ts');
  const lifecycle = read('cloudflare/src/lifecycle-postgres.ts');
  const houseMortality = lifecycle.slice(lifecycle.indexOf('export async function processHouseMortality'), lifecycle.indexOf('export async function activatePendingHouseSuccessors'));
  const automation = read('cloudflare/src/daily-automation.ts');

  assert.match(building, /FROM buildings b[\s\S]*WHERE b\.status = 'active'/);
  assert.match(building, /b\.owner_economic_id/);
  assert.match(building, /building\.private_owner_id \?\? building\.owner_id/);
  assert.doesNotMatch(building, /JOIN humans[\s\S]*WHERE h\.life_status = 'active'[\s\S]*FROM buildings/);
  assert.doesNotMatch(houseMortality, /UPDATE buildings SET (status|operating_policy|condition) =/);
  assert.match(automation, /status = 'active'/);
});
