import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const scheduler = fs.readFileSync(new URL('../cloudflare/src/scheduler-postgres.ts', import.meta.url), 'utf8');
const settlement = fs.readFileSync(new URL('../cloudflare/src/tax-settlement-postgres.ts', import.meta.url), 'utf8');

test('daily tax phases assess obligations before invoking batched payment', () => {
  assert.match(scheduler, /settlePublicTaxesInTransaction/);
  assert.match(scheduler, /publicTaxAssessment/);
  assert.match(settlement, /INSERT INTO tax_obligations/);
  assert.match(settlement, /financial_obligations/);
  assert.match(settlement, /assessedDay = day - 1/);
  assert.match(settlement, /ON CONFLICT \(correlation_id\) DO NOTHING/);
});
