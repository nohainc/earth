import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const read = (file) => fs.readFileSync(file, 'utf8');

test('succession uses a short House transition window instead of probate', () => {
  const migration = read('db/migrations/308_house_succession_transition_window.sql');
  const lifecycle = read('cloudflare/src/lifecycle-postgres.ts');
  const schema = read('db/schema.sql');

  assert.match(migration, /succession_transition_until_game_day BIGINT/);
  assert.match(migration, /earth_house_in_succession_transition/);
  assert.match(lifecycle, /successionTransitionDays/);
  assert.match(lifecycle, /day \+ successionCost\.transitionDays/);
  assert.match(lifecycle, /life_status, activation_game_day/);
  assert.match(schema, /succession_transition_until_game_day BIGINT/);
  assert.doesNotMatch(lifecycle.slice(lifecycle.indexOf('export async function processHouseMortality'), lifecycle.indexOf('export async function activatePendingHouseSuccessors')), /estate_period_days/);
});
