import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const source = fs.readFileSync('cloudflare/src/credit-flows.ts', 'utf8');

test('canonical CREDIT flow adapters cover private and institutional payment directions', () => {
  for (const name of ['payHouseService', 'payCorporationGrant', 'payEarthGrant', 'payCorporationDividend', 'payLicenseFee']) {
    assert.match(source, new RegExp(`export async function ${name}`));
  }
  assert.equal((source.match(/externalTransfer\(repository/g) ?? []).length, 5);
});

test('canonical flows make payer and beneficiary account purposes explicit', () => {
  assert.match(source, /accountPurpose: 'WALLET'/);
  assert.match(source, /accountPurpose: 'TREASURY'/);
  assert.match(source, /recipientAccountPurpose/);
  assert.match(source, /beneficiaryAccountPurpose/);
  assert.match(source, /reasonId: input\.licenseId/);
});

test('City dividend engine is removed from active source', () => {
  assert.equal(fs.existsSync('cloudflare/src/civic-dividend-engine.ts'), false);
  assert.doesNotMatch(source, /city|civic/i);
});
