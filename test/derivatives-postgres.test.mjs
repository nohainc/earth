import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

test('derivatives projection is read-only and Economy V2-backed', () => {
  const source = fs.readFileSync(new URL('../cloudflare/src/derivatives-postgres.ts', import.meta.url), 'utf8');
  assert.match(source, /market_candles/);
  assert.match(source, /market_orders/);
  assert.match(source, /derivative_obligations/);
  assert.doesNotMatch(source, /account_balances|resource_balances|ledger_entries|resource_ledger_entries|transferCredits|mutateResourceBalance/i);
  assert.doesNotMatch(source, /INSERT INTO|UPDATE |DELETE FROM/i);
});
