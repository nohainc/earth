import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const migration = fs.readFileSync('db/migrations/341_human_daily_needs_v2.sql', 'utf8');
const schema = fs.readFileSync('db/schema.sql', 'utf8');
const scheduler = fs.readFileSync('cloudflare/src/scheduler-postgres.ts', 'utf8');

test('Human Life & Needs V2 stores five aggregate daily need dimensions', () => {
  for (const field of ['food_satisfaction', 'housing_satisfaction', 'energy_satisfaction', 'healthcare_access', 'connectivity_access', 'life_quality']) {
    assert.match(migration, new RegExp(field));
    assert.match(schema, new RegExp(field));
  }
  assert.match(migration, /PRIMARY KEY \(human_id, game_day\)/);
});

test('daily needs are derived in bulk and refreshed with life maintenance', () => {
  assert.match(migration, /CREATE OR REPLACE FUNCTION earth_refresh_human_daily_needs/);
  assert.match(migration, /WHERE h\.life_status = 'active'/);
  assert.match(migration, /ON CONFLICT \(human_id, game_day\)/);
  assert.match(scheduler, /earth_refresh_human_daily_needs/);
});

test('needs remain aggregate gameplay state rather than manual purchase actions', () => {
  assert.doesNotMatch(scheduler, /buyFood|buyHousing|buyEnergy|buyHealthcare|buyConnectivity/);
  assert.match(migration, /PRIMARY KEY \(human_id, game_day\)/);
});
