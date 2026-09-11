import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const scheduler = fs.readFileSync(new URL('../cloudflare/src/scheduler-postgres.ts', import.meta.url), 'utf8');

test('daily tax phases assess obligations before invoking batched payment', () => {
  assert.match(scheduler, /INSERT INTO tax_obligations/);
  assert.match(scheduler, /earth_settle_v2_tax_obligations/);
  assert.match(scheduler, /city_economic_id/);
  assert.match(scheduler, /corporation_economic_id/);
  assert.match(scheduler, /tax_type, tax_base_units, rate_bps, amount_units/);
});
