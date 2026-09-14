import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const service = fs.readFileSync('cloudflare/src/credit-settlement-postgres.ts', 'utf8');
const financial = fs.readFileSync('cloudflare/src/financial-postgres.ts', 'utf8');

test('canonical CREDIT settlement exposes only explicit normal mutations', () => {
  for (const operation of ['externalTransfer', 'internalTransfer', 'reserve', 'release', 'settleObligation']) assert.match(service, new RegExp(`export async function ${operation}`));
  assert.match(service, /earth_post_transaction/);
  for (const field of ['correlationId', 'transactionKind', 'actor', 'purpose', 'ruleVersion']) assert.match(service, new RegExp(field));
  assert.doesNotMatch(financial, /account-ouc-treasury|account-global-bank|startsWith\('account-'/);
});

test('financial transfer facade delegates principal transfers to the canonical service', () => {
  assert.match(financial, /externalTransfer\(repository/);
  assert.match(financial, /accountPurpose/);
});
