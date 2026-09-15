import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

test('Organization authority is office-scoped and Human-active, not membership-scoped', async () => {
  const resolver = await readFile(new URL('../cloudflare/src/organization-authority.ts', import.meta.url), 'utf8');
  const migration = await readFile(new URL('../db/migrations/034_organization_offices.sql', import.meta.url), 'utf8');
  assert.match(resolver, /h\.status = 'ACTIVE'/);
  assert.match(resolver, /effective_to_game_day/);
  assert.match(resolver, /authority_rules/);
  assert.match(migration, /principal_type TEXT NOT NULL CHECK \(principal_type IN \('HUMAN','HOUSE'\)/);
  assert.match(migration, /organization_offices_one_human_holder_idx/);
});
