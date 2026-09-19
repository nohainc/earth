import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const read = (path) => fs.readFileSync(path, 'utf8');
const settlement = read('cloudflare/src/credit-settlement-postgres.ts');
const obligations = read('db/migrations/013_financial_obligations.sql');
const construction = read('cloudflare/src/territory-capacity-postgres.ts');
const research = `${read('cloudflare/src/technology-postgres.ts')}\n${read('cloudflare/src/corporation-building-research-postgres.ts')}`;
const transfer = read('cloudflare/src/financial-postgres.ts');
const bank = read('cloudflare/src/global-bank-postgres.ts');
const source = `${settlement}\n${transfer}\n${bank}`;

test('normal obligations are CREDIT-only and cannot name resource assets', () => {
  assert.match(obligations, /principal_due_units BIGINT/);
  assert.match(obligations, /interest_due_units BIGINT/);
  assert.doesNotMatch(obligations, /asset_id|resource|MATERIAL|ENERGY|FOOD|COMPUTE|COMPONENTS/i);
  assert.match(settlement, /parseCreditAmount/);
});

test('research funding and construction use CREDIT, with no implicit EARTH destination', () => {
  assert.match(research, /asset_id.?[:= ]+1/);
  assert.doesNotMatch(research, /INVENTORY/);
  assert.match(construction, /PRIVATE_CONSTRUCTION|PUBLIC_INFRASTRUCTURE_CONSTRUCTION/);
  assert.doesNotMatch(construction, /o\.id\s*=\s*'EARTH'|earthTreasury/);
});

test('normal external transfers require explicit principals and canonical settlement', () => {
  assert.match(transfer, /externalTransfer\(repository/);
  assert.match(transfer, /payer: \{ principalId/);
  assert.match(transfer, /beneficiary: \{ principalId/);
  assert.match(transfer, /require payer and beneficiary principals/);
  assert.doesNotMatch(source, /account-ouc|account-global-bank/);
  assert.doesNotMatch(source, /account_type\s*=\s*[123456789]/);
});

test('budget accounting separates internal allocation from actual spending', () => {
  const fiscal = read('cloudflare/src/corporation-fiscal-postgres.ts');
  const spending = read('cloudflare/src/institution-spending.ts');
  assert.match(fiscal, /CORPORATION_INTERNAL/);
  assert.match(spending, /spent_units = spent_units \+ \$1/);
  assert.match(spending, /postEconomicTransaction/);
});

test('idempotency and integer CREDIT units are present at the canonical boundary', () => {
  assert.match(settlement, /correlationId/);
  assert.match(settlement, /already_processed/);
  assert.match(settlement, /CreditUnits/);
  assert.match(bank, /parseCreditAmount/);
});

test('legacy City finance module and public-spending route are absent', () => {
  assert.equal(fs.existsSync('cloudflare/src/finance-postgres.ts'), false);
  assert.doesNotMatch(read('cloudflare/src/finance-routes.ts'), /public-spending|cityId|OUC/);
});
