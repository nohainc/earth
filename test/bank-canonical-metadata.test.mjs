import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const bank = fs.readFileSync('cloudflare/src/global-bank-postgres.ts', 'utf8');
const settlement = fs.readFileSync('cloudflare/src/global-bank-settlement-engine.ts', 'utf8');
const metadata = fs.readFileSync('cloudflare/src/bank-transaction-metadata.ts', 'utf8');

test('bank mutations use exact CREDIT parsing and canonical metadata', () => {
  assert.match(bank, /parseCreditAmount/);
  assert.match(bank, /BANK_DEPOSIT_FUNDING/);
  assert.match(bank, /BANK_DEPOSIT_PAYOUT/);
  assert.doesNotMatch(bank, /moneyToCents/);
});

test('bank metadata covers balance-sheet activity without treating the Bank as a normal payer', () => {
  for (const kind of ['BANK_LOAN_ORIGINATION', 'BANK_LOAN_PAYMENT', 'BANK_INTEREST_ACCRUAL', 'BANK_DAILY_SETTLEMENT']) assert.match(metadata, new RegExp(kind));
  assert.match(metadata, /sourceType: 'GLOBAL_BANK'/);
  assert.match(metadata, /actorId: 'GLOBAL-BANK'/);
  assert.match(settlement, /GLOBAL_BANK_DAILY_SETTLEMENT_METADATA/);
  assert.match(settlement, /earth_settle_v2_global_bank/);
});
