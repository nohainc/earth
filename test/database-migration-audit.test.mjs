import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

test('migration runner uses numeric ordering and deployment serialization', () => {
  const source = fs.readFileSync('scripts/migrate-postgres.mjs', 'utf8');
  assert.match(source, /sort\(\(a, b\) => Number\(a\.match/);
  assert.match(source, /pg_advisory_lock/);
  assert.match(source, /BEGIN|begin/);
  assert.match(source, /checksum/);
});

test('migration audit validates the canonical schema head', () => {
  const source = fs.readFileSync('scripts/verify-migration-order.mjs', 'utf8');
  assert.match(source, /duplicate migration version/);
  assert.match(source, /manifest\.migrationVersion/);
  assert.match(source, /reconciled through migration/);
});

test('high-volume persistence has explicit indexes and uniqueness checks', () => {
  const manifest = JSON.parse(fs.readFileSync('db/schema-manifest.json', 'utf8'));
  for (const index of ['market_orders', 'economic_entries', 'daily_settlement_runs']) {
    assert.ok(Object.keys(manifest.requiredTables).includes(index) || manifest.requiredIndexes.some((name) => name.includes(index)), `manifest covers ${index}`);
  }
  assert.ok(manifest.requiredUniqueConstraints.some(([table]) => table === 'economic_transactions'));
  assert.ok(manifest.requiredIndexes.some((name) => name === 'market_batch_instruments_lease_idx'));
});
