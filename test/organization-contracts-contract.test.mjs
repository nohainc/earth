import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

test('Organization contracts require approved templates and both signatures before liability', async () => {
  const source = await readFile(new URL('../cloudflare/src/contracts-postgres.ts', import.meta.url), 'utf8');
  const migration = await readFile(new URL('../db/migrations/037_typed_organization_contracts.sql', import.meta.url), 'utf8');
  assert.match(source, /Approved contract template/);
  assert.match(source, /COUNT\(\*\).*organization_contract_signatures/);
  assert.match(source, /financial_obligations/);
  assert.match(source, /status = 'PENDING_SIGNATURE'/);
  assert.match(migration, /organization_contract_signatures/);
  assert.match(migration, /contract_templates/);
});
