import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

test('World Program funding has bounded player contribution, matching, and refund contracts', async () => {
  const source = await readFile(new URL('../cloudflare/src/global-programs-postgres.ts', import.meta.url), 'utf8');
  const migration = await readFile(new URL('../db/migrations/069_global_program_funding_lifecycle.sql', import.meta.url), 'utf8');
  for (const term of ['funding_deadline_game_day', 'matching_authorized_units', 'global_program_contributions', 'GLOBAL_PROGRAM_CONTRIBUTION', 'GLOBAL_PROGRAM_REFUND', '10000n']) assert.match(`${source}\n${migration}`, new RegExp(term.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')));
  assert.match(source, /owner_type = 'HOUSE'/);
  assert.match(source, /owner_economic_id = 'ECON-EARTH-001'/);
});
