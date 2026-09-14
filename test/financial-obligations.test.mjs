import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const migration = fs.readFileSync('db/migrations/013_financial_obligations.sql', 'utf8');
const service = fs.readFileSync('cloudflare/src/credit-settlement-postgres.ts', 'utf8');

test('generic financial obligations support the required categories and lifecycle', () => {
  for (const type of ['TAX', 'ROYALTY', 'LICENSE_PAYMENT', 'LOAN_PAYMENT', 'SERVICE_INVOICE', 'FINE_FEE']) assert.match(migration, new RegExp(`'${type}'`));
  for (const status of ['DUE', 'PARTIAL', 'PAID', 'ARREARS', 'CANCELLED']) assert.match(migration, new RegExp(`'${status}'`));
  for (const operation of ['createFinancialObligation', 'settleObligation', 'cancelFinancialObligation', 'markFinancialObligationsInArrears']) assert.match(service, new RegExp(`export async function ${operation}`));
});

test('obligation settlement remains separate from immediate market purchases', () => {
  assert.match(service, /OBLIGATION_PAYMENT/);
  assert.match(service, /tax_obligations|financial_obligations/);
  assert.doesNotMatch(service, /market_orders|market_fills|MARKET_TRADE/);
});
