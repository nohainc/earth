import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

test('V4 governance method endpoint is transactional and uses separate Voice storage', async () => {
  const source = await readFile(new URL('../cloudflare/src/governance-v4-postgres.ts', import.meta.url), 'utf8');
  const route = await readFile(new URL('../cloudflare/src/governance-routes.ts', import.meta.url), 'utf8');
  const migration = await readFile(new URL('../db/migrations/031_governance_voice_delegation.sql', import.meta.url), 'utf8');
  assert.match(source, /setOrganizationVotingSettings/);
  assert.match(source, /repository\.transaction/);
  assert.match(route, /governance-v4-postgres/);
  assert.match(route, /methodMatch/);
  assert.match(migration, /governance_voice_cycles/);
  assert.doesNotMatch(migration, /economic_accounts/);
});
