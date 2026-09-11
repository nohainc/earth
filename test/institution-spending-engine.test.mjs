import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

const read = (file) => fs.readFileSync(path.resolve(file), 'utf8');

test('institution spending uses one atomic Economy V2 engine', () => {
  const source = read('cloudflare/src/institution-spending.ts');
  const migration = read('db/migrations/321_institution_spending_engine.sql');
  assert.match(source, /export async function spendInstitutionBudget/);
  for (const field of ['institutionId', 'budgetLineId', 'sourceAccountId', 'recipientAccountId', 'amountUnits', 'purpose', 'sourceType', 'sourceId', 'correlationId']) assert.match(source, new RegExp(field));
  assert.match(source, /FOR UPDATE/);
  assert.match(source, /earth_post_transaction/);
  assert.match(source, /earth_pay_budget_commitment/);
  assert.match(source, /SET spent_units = spent_units \+ \$1/);
  assert.match(source, /institution_spending_journals/);
  assert.match(migration, /economic_transaction_id BIGINT NOT NULL REFERENCES economic_transactions\(id\)/);
  assert.match(migration, /correlation_id TEXT NOT NULL UNIQUE/);
});

test('city and corporation spending delegate to the shared engine', () => {
  const finance = read('cloudflare/src/finance-postgres.ts');
  const institutions = read('cloudflare/src/institutions-postgres.ts');
  assert.match(finance, /spendBudget\(tx/);
  assert.match(institutions, /spendBudget\(tx/);
  const corporationSpending = institutions.slice(institutions.indexOf('export async function spendCorporationTreasury'), institutions.indexOf('export async function contributeToCorporation'));
  assert.doesNotMatch(corporationSpending, /account_balances/);
});

test('budget authorization is separate from budget execution', () => {
  const authorization = read('cloudflare/src/budget-authorization.ts');
  const spending = read('cloudflare/src/institution-spending.ts');
  const institutions = read('cloudflare/src/institutions-postgres.ts');
  assert.match(authorization, /export async function setBudgetAuthorization/);
  assert.match(authorization, /authorized_units/);
  assert.doesNotMatch(authorization, /earth_post_transaction|spent_units = spent_units/);
  assert.match(spending, /export const spendBudget = spendInstitutionBudget/);
  assert.match(institutions, /setBudgetAuthorization\(tx/);
});
