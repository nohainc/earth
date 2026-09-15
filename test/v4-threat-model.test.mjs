import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

test('V4 threat model covers the required economic attack classes', () => {
  const doc = fs.readFileSync('docs/V4_THREAT_MODEL.md', 'utf8');
  for (const term of ['Replay', 'Race', 'Stale quote', 'Self-dealing', 'Sybil', 'Privilege escalation', 'Circular funding', 'Unbalanced issuance', 'Historical reinterpretation']) assert.match(doc, new RegExp(term, 'i'));
  assert.match(doc, /PostgreSQL constraints, locks, and the canonical ledger/);
});

test('required V4 settlement adapters do not open nested transactions', () => {
  for (const file of ['territory-rights-postgres.ts', 'commons-dividends-postgres.ts', 'tax-settlement-postgres.ts']) {
    const source = fs.readFileSync(`cloudflare/src/${file}`, 'utf8');
    const marker = file === 'tax-settlement-postgres.ts'
      ? 'export async function settlePublicTaxesInTransaction'
      : 'export async function settle';
    const settlement = source.slice(source.indexOf(marker), source.indexOf('\nexport async function', source.indexOf(marker) + marker.length) === -1 ? undefined : source.indexOf('\nexport async function', source.indexOf(marker) + marker.length));
    assert.doesNotMatch(settlement, /repository\.transaction\(/, `${file} must use the scheduler-owned phase transaction`);
  }
});
