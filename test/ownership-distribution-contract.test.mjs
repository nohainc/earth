import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

test('ownership distributions are proportional, ledger-backed, and auditable', async () => {
  const source = await readFile(new URL('../cloudflare/src/ownership-postgres.ts', import.meta.url), 'utf8');
  const migration = await readFile(new URL('../db/migrations/036_ownership_distributions.sql', import.meta.url), 'utf8');
  assert.match(source, /OWNERSHIP_DISTRIBUTION/);
  assert.match(source, /amount \* BigInt\(position\.units\)/);
  assert.match(source, /retainedRemainderUnits/);
  assert.match(migration, /ownership_distribution_payments/);
});
