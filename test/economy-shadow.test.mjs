import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

test('Economy V2 shadow reconciliation records legacy and V2 balances without mutating either authority', () => {
  const shadow = fs.readFileSync(path.resolve('cloudflare/src/economy-shadow.ts'), 'utf8');

  assert.match(shadow, /legacy_units/);
  assert.match(shadow, /v2_units/);
  assert.match(shadow, /legacy_delta_units/);
  assert.match(shadow, /v2_delta_units/);
  assert.match(shadow, /difference_units/);
  assert.match(shadow, /difference_kind/);
  assert.doesNotMatch(shadow, /UPDATE\s+economic_accounts/i);
  assert.doesNotMatch(shadow, /UPDATE\s+account_balances/i);
  assert.doesNotMatch(shadow, /UPDATE\s+resource_balances/i);
});

test('shadow reconciliation surrounds resumable settlement', () => {
  const scheduler = fs.readFileSync(path.resolve('cloudflare/src/scheduler-postgres.ts'), 'utf8');
  const capture = scheduler.indexOf('await captureEconomyShadowOpening');
  const settle = scheduler.indexOf('await runResumableSettlementDay(repository, pendingResumableSettlementDay');
  const reconcile = scheduler.indexOf('await reconcileEconomyShadowDay');

  assert.ok(capture >= 0 && settle >= 0 && reconcile >= 0);
  assert.ok(capture < settle, 'opening must be captured before settlement');
  assert.ok(settle < reconcile, 'reconciliation must run after settlement');
});
