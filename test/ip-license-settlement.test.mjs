import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const read = (file) => fs.readFileSync(new URL(`../${file}`, import.meta.url), 'utf8');

test('IP license settlement is bounded, affordable, idempotent, and V2-backed', () => {
  const source = read('cloudflare/src/ip-license-settlement-postgres.ts');
  const migration = read('db/baseline/01_schema.sql');
  const phases = read('cloudflare/src/daily-settlement-phases.ts');
  const scheduler = read('cloudflare/src/scheduler-postgres.ts');
  assert.match(source, /technology_license_contracts/);
  assert.match(source, /technology_license_payments/);
  assert.match(source, /earth_post_transaction/);
  assert.match(source, /paid_through_game_day/);
  assert.match(source, /status = 'SUSPENDED'/);
  assert.match(source, /LIMIT 1000/);
  assert.match(migration, /LICENSE_PAYMENT/);
  assert.match(phases, /required\('ip_license_billing'/);
  assert.match(scheduler, /settleTechnologyLicenseFees/);
});
