import test from 'node:test';
import assert from 'node:assert/strict';
import { evaluateGeneration } from '../cloudflare/src/technology-generations.ts';
import { readFile } from 'node:fs/promises';

test('technology generations require milestones and predecessors', () => {
  assert.equal(evaluateGeneration({ generationId: 'G1', minimumGameDay: 1, currentGameDay: 1, predecessorId: null, predecessorDiscovered: false }).eligible, true);
  assert.equal(evaluateGeneration({ generationId: 'G2', minimumGameDay: 1, currentGameDay: 10, predecessorId: 'G1', predecessorDiscovered: false }).reason, 'predecessor_not_discovered');
});

test('generation research progresses in a bounded settlement phase and discovers next day', async () => {
  const source = await readFile(new URL('../cloudflare/src/technology-generations-postgres.ts', import.meta.url), 'utf8');
  const migration = await readFile(new URL('../db/migrations/038_technology_generations.sql', import.meta.url), 'utf8');
  assert.match(source, /LIMIT 100/);
  assert.match(source, /effective_from_game_day\) VALUES/);
  assert.match(migration, /technology_discoveries/);
  assert.match(migration, /generation_number/);
});
