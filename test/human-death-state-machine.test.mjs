import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

const read = (file) => fs.readFileSync(path.resolve(file), 'utf8');

test('death uses an explicit atomic Human state machine while the House stays active', () => {
  const migration = read('db/migrations/298_human_death_state_machine.sql');
  const lifecycle = read('cloudflare/src/lifecycle-postgres.ts');
  const scheduler = read('cloudflare/src/scheduler-postgres.ts');
  const schema = read('db/schema.sql');

  assert.match(migration, /ACTIVE','DEATH_CONFIRMED','DECEASED/);
  assert.match(migration, /humans_death_state_trigger/);
  assert.match(migration, /must be death-confirmed/);
  assert.match(lifecycle, /processHouseMortality/);
  assert.match(lifecycle, /mortality_state/);
  assert.match(scheduler, /processHouseMortality/);
  assert.match(schema, /mortality_state TEXT NOT NULL DEFAULT 'ACTIVE'/);
  assert.match(schema, /life_status TEXT NOT NULL DEFAULT 'active' CHECK \(life_status IN \('active','pending','deceased','estate'\)\)/);
  assert.match(lifecycle, /activation_game_day/);
  assert.match(lifecycle, /activatePendingHouseSuccessors/);
});
