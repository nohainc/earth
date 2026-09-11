import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const read = (file) => fs.readFileSync(file, 'utf8');

test('succession switches the House representative and generation atomically', () => {
  const lifecycle = read('cloudflare/src/lifecycle-postgres.ts');
  const scheduler = read('cloudflare/src/scheduler-postgres.ts');
  const mortality = lifecycle.slice(lifecycle.indexOf('export async function processHouseMortality'), lifecycle.indexOf('export async function activatePendingHouseSuccessors'));

  assert.match(scheduler, /if \(day % 365 === 0\) await processHouseMortality\(tx, day\)/);
  assert.match(mortality, /UPDATE humans SET mortality_state = 'DEATH_CONFIRMED', life_status = 'deceased'/);
  assert.match(mortality, /INSERT INTO humans \(id, account_id, house_id/);
  assert.match(mortality, /generation = GREATEST\(generation, \$2\), current_human_id = \$3/);
  assert.match(mortality, /UPDATE succession_events SET status = \\'COMPLETED\\'/);
  assert.match(mortality, /INSERT INTO notifications/);
  assert.doesNotMatch(mortality, /UPDATE houses SET current_human_id = NULL/);
});
