import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const building = fs.readFileSync('cloudflare/src/corporation-building-research-postgres.ts', 'utf8');
const technology = fs.readFileSync('cloudflare/src/technology-postgres.ts', 'utf8');

test('building research is always Corporation-funded', () => {
  assert.match(building, /owner_type = 'CORPORATION'/);
  assert.match(building, /payer\.account_type = 'OPERATIONS'/);
  assert.match(building, /institution_budget_commitments/);
  assert.match(building, /funding_transaction_id/);
  assert.doesNotMatch(building, /payerOwnerId = isPrivate|owner_type = 'HOUSE'.*WALLET/s);
});

test('technology research uses Corporation budget authority and funding', () => {
  assert.match(technology, /category_code='RESEARCH'/);
  assert.match(technology, /institution_budget_commitments/);
  assert.match(technology, /fundingTransactionId/);
  assert.match(technology, /payer\.account_type = 'OPERATIONS'/);
});
