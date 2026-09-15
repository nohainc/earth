import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

test('EARTH global programs have proposal, cash, and bounded-progress controls', async () => {
  const migration = await readFile(new URL('../db/migrations/033_global_programs.sql', import.meta.url), 'utf8');
  const service = await readFile(new URL('../cloudflare/src/global-programs-postgres.ts', import.meta.url), 'utf8');
  assert.match(migration, /authorization_proposal_id/);
  assert.match(migration, /global_program_progress/);
  assert.match(service, /EARTH public-project proposal/);
  assert.match(service, /ECON-EARTH-001/);
  assert.match(service, /LIMIT 100/);
  assert.doesNotMatch(migration, /resource_ledger/);
});
