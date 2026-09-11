import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const read = (path) => fs.readFileSync(new URL(`../${path}`, import.meta.url), 'utf8');

test('budget authorization and commitment creation are non-monetary operations', () => {
  const authorization = read('cloudflare/src/budget-authorization.ts');
  const commitments = read('cloudflare/src/institution-budget-api.ts');
  const commitmentSql = read('db/migrations/320_budget_commitments.sql');
  assert.doesNotMatch(authorization, /earth_post_transaction|UPDATE\s+economic_accounts|INSERT\s+INTO\s+economic_entries/);
  assert.doesNotMatch(commitments.slice(0, commitments.indexOf('export async function payInstitutionCommitment')), /earth_post_transaction|UPDATE\s+economic_accounts|INSERT\s+INTO\s+economic_entries/);
  assert.doesNotMatch(commitmentSql.slice(0, commitmentSql.indexOf('CREATE OR REPLACE FUNCTION earth_pay_budget_commitment')), /earth_post_transaction|UPDATE\s+economic_accounts|INSERT\s+INTO\s+economic_entries/);
});

test('only payment paths post balanced Economy V2 transfers', () => {
  const spending = read('cloudflare/src/institution-spending.ts');
  const grants = read('cloudflare/src/institution-grants.ts');
  assert.match(spending, /earth_post_transaction/);
  assert.match(grants, /spendBudget\(tx/);
  assert.match(spending, /delta: \(-input\.amountUnits\)/);
  assert.match(spending, /delta: input\.amountUnits/);
  const entries = [{ delta: -12500n }, { delta: 12500n }];
  assert.equal(entries.reduce((total, entry) => total + entry.delta, 0n), 0n, 'a CREDIT transfer must balance');
});

test('budget amendments are explicitly non-monetary while reserve transfers are auditable', () => {
  const authorization = read('cloudflare/src/budget-authorization.ts');
  const integrity = read('db/migrations/338_budget_integrity_checks.sql');
  assert.doesNotMatch(authorization, /economic_transaction|posting|balance/);
  assert.match(integrity, /reserve_transfer_unbalanced/);
  assert.match(integrity, /transaction_kind = 'RESERVE_TRANSFER'/);
});
