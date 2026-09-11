import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const actions = fs.readFileSync('cloudflare/src/proposal-actions.ts', 'utf8');
const execution = fs.readFileSync('cloudflare/src/proposal-finance-actions.ts', 'utf8');
const governance = fs.readFileSync('cloudflare/src/governance-postgres.ts', 'utf8');

test('financial proposals use typed snapshots and existing Budget V2 services', () => {
  for (const action of ['APPROVE_BUDGET', 'AMEND_BUDGET', 'AUTHORIZE_MAJOR_PROJECT', 'AUTHORIZE_GRANT', 'CHANGE_TAX_CHARTER', 'TRANSFER_RESERVE', 'DECLARE_DIVIDEND', 'APPROVE_BAILOUT']) assert.match(actions, new RegExp(action));
  assert.match(governance, /financialActionType/);
  assert.match(governance, /\.\.\.\(input\.targetValue/);
  assert.match(governance, /executeProposalFinancialAction/);
  assert.match(execution, /setBudgetAuthorization/);
  assert.match(execution, /approveInstitutionGrant/);
  assert.match(execution, /spendInstitutionBudget/);
  assert.doesNotMatch(execution, /UPDATE economic_accounts\s+SET\s+balance/i);
});
