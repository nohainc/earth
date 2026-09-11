import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

test('annual mortality follows finance and refreshes access after succession', () => {
  const source = fs.readFileSync('cloudflare/src/daily-settlement-phases.ts', 'utf8');
  const phase = (id) => Number(source.match(new RegExp(`id: '${id}', order: (\\d+)`))?.[1]);

  assert.ok(phase('building_settlement') < phase('city_corporate_income_tax'));
  assert.ok(phase('city_corporate_income_tax') < phase('global_bank'));
  assert.ok(phase('bank_health') < phase('life_maintenance'));
  assert.ok(phase('life_maintenance') < phase('financial_states'));
  assert.ok(phase('financial_states') < phase('lifecycle'));
  assert.ok(phase('lifecycle') < phase('post_succession_access_refresh'));
  assert.ok(phase('post_succession_access_refresh') < phase('end_of_day_snapshots'));
});
