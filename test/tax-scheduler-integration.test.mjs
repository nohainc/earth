import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const scheduler = fs.readFileSync(new URL('../cloudflare/src/scheduler-postgres.ts', import.meta.url), 'utf8');
const settlement = fs.readFileSync(new URL('../cloudflare/src/tax-settlement-postgres.ts', import.meta.url), 'utf8');
const corporationSettlement = fs.readFileSync(new URL('../cloudflare/src/corporation-tax-settlement-postgres.ts', import.meta.url), 'utf8');

test('daily tax phases assess obligations before invoking batched payment', () => {
  assert.match(scheduler, /settlePublicTaxesInTransaction/);
  assert.match(scheduler, /publicTaxAssessment/);
  assert.match(settlement, /INSERT INTO tax_obligations/);
  assert.match(settlement, /financial_obligations/);
  assert.match(settlement, /assessedDay = day - 1/);
  assert.match(settlement, /ON CONFLICT \(correlation_id\) DO NOTHING/);
});

test('settlement prepares and repairs prior-day Corporation tax snapshots', () => {
  assert.match(scheduler, /const snapshotDays/);
  assert.match(scheduler, /day - 1, day/);
  assert.match(scheduler, /authorityType: 'CORPORATION'.*gameDay: snapshotDay/);
  assert.match(corporationSettlement, /materializeResolvedConstitutionSnapshot/);
  assert.match(corporationSettlement, /historical rule snapshot/);
  assert.match(corporationSettlement, /c\.created_game_day <= \$1/);
  assert.match(corporationSettlement, /rule\.rule_code = 'CORPORATION\.TAX\.CORPORATE_RATE'/);
});

test('capacity settlement excludes Corporations created after the assessed day', () => {
  const capacity = fs.readFileSync(new URL('../cloudflare/src/v5-capacity-settlement-postgres.ts', import.meta.url), 'utf8');
  assert.match(capacity, /corp\.created_game_day <= \$1/);
  assert.match(capacity, /c\.created_game_day <= \$1/);
});
