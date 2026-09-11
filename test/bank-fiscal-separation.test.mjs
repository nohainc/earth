import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const migration = fs.readFileSync(new URL('../db/migrations/213_separate_ouc_and_global_bank.sql', import.meta.url), 'utf8');
const bank = fs.readFileSync(new URL('../cloudflare/src/global-bank-settlement-engine.ts', import.meta.url), 'utf8');

test('OUC fiscal accounts and Global Bank reserve are separate V2 owners', () => {
  assert.match(migration, /SYSTEM-GLOBAL-BANK/);
  assert.match(migration, /BANK_RESERVE/);
  assert.match(migration, /account-ouc-treasury/);
  assert.match(migration, /account-global-corporate-bank/);
  assert.match(migration, /account-global-bank-operations/);
  assert.match(migration, /o\.id = 'OUC'/);
  assert.match(migration, /o\.id = 'SYSTEM-GLOBAL-BANK'/);
  assert.match(bank, /BANK_ACCOUNT = 'account-global-corporate-bank'/);
  assert.doesNotMatch(migration, /UPDATE\s+(cities|corporations)\s+SET\s+treasury/);
});
