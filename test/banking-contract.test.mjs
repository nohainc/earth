import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { quoteLoan } from '../cloudflare/src/banking.ts';

test('loan underwriting is integer, reserve-backed, and bounded by risk inputs', () => {
  const quote = quoteLoan({ requestedUnits: 500n, termDays: 30, collateralUnits: 800n, guaranteedUnits: 200n, borrowerCashflowUnits: 1000n, availableReserveUnits: 1000n, baseRateBps: 700n, maxLoanToCollateralBps: 5000n, maxLoanToCashflowBps: 6000n, minimumReserveRatioBps: 2000n });
  assert.equal(quote.eligible, true);
  assert.equal(quote.approvedUnits, 500n);
  assert.equal(quote.rateBps, 700n);
  const denied = quoteLoan({ requestedUnits: 500n, termDays: 30, collateralUnits: 0n, guaranteedUnits: 0n, borrowerCashflowUnits: 0n, availableReserveUnits: 1000n, baseRateBps: 700n, maxLoanToCollateralBps: 5000n, maxLoanToCashflowBps: 6000n, minimumReserveRatioBps: 2000n });
  assert.equal(denied.eligible, false);
});

test('banking migration preserves collateral, guarantees, payments, and resolution history', () => {
  const migration = fs.readFileSync('db/migrations/042_banking_credit_risk.sql', 'utf8');
  for (const table of ['bank_credit_policies', 'bank_loan_collateral', 'bank_loan_guarantees', 'bank_loan_payments', 'bank_loan_resolutions']) assert.match(migration, new RegExp(`CREATE TABLE IF NOT EXISTS ${table}`));
  assert.match(migration, /bank_loan_resolutions.*resolution_type/s);
  assert.match(migration, /bank_credit_policies_one_active_idx/);
  assert.match(migration, /BANK-POLICY-GLOBAL-V1/);
});

test('bank loan origination is exposed as a protected, idempotent canonical path', () => {
  const service = fs.readFileSync('cloudflare/src/banking-postgres.ts', 'utf8');
  const routes = fs.readFileSync('cloudflare/src/api-registry.ts', 'utf8');
  assert.match(service, /earth_post_transaction/);
  assert.match(service, /WHERE correlation_id = \$1/);
  assert.match(routes, /POST.*\/api\/finance\/bank\/loan/);
  assert.match(routes, /getBankLoanQuote/);
  assert.match(service, /bank_loan_payments/);
  assert.match(routes, /POST.*\/api\/finance\/bank\/loan\/\{id\}\/repay/);
  assert.match(routes, /POST.*\/api\/finance\/bank\/loan\/\{id\}\/guarantee/);
  assert.match(service, /settleBankLoanRisk/);
  assert.match(service, /resolution_type/);
  assert.match(service, /getBankRiskProjection/);
  assert.match(routes, /GET.*\/api\/finance\/bank\/risk/);
});
