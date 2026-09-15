import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

test('shared ownership dilutes the legal owner and preserves a fixed cap table', async () => {
  const source = await readFile(new URL('../cloudflare/src/ownership-postgres.ts', import.meta.url), 'utf8');
  const migration = await readFile(new URL('../db/migrations/035_shared_ownership.sql', import.meta.url), 'utf8');
  assert.match(source, /TOTAL_OWNERSHIP_UNITS = 10000n/);
  assert.match(source, /Ownership conservation invariant failed before subscription/);
  assert.match(source, /status = 'SUPERSEDED'/);
  assert.match(source, /effectiveFromGameDay: day \+ 1/);
  assert.match(migration, /asset_ownership_positions/);
  assert.match(migration, /capitalization_events/);
});
