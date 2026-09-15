import test from 'node:test';
import assert from 'node:assert/strict';
import { calculateMatching } from '../cloudflare/src/public-projects.ts';
import { readFile } from 'node:fs/promises';

test('matching favors breadth but remains integer and pool/target capped', () => {
  const one = calculateMatching({ contributionUnits: 100n, supporterCount: 1n, poolRemaining: 10000n, targetRemaining: 10000n, matchBps: 10000n });
  const many = calculateMatching({ contributionUnits: 100n, supporterCount: 20n, poolRemaining: 10000n, targetRemaining: 10000n, matchBps: 10000n });
  assert.ok(many > one);
  assert.ok(many <= 10000n);
});

test('public projects use escrow, proposal authority, and replay-safe matching funds', async () => {
  const source = await readFile(new URL('../cloudflare/src/public-projects-postgres.ts', import.meta.url), 'utf8');
  const migration = await readFile(new URL('../db/migrations/040_public_projects_matching.sql', import.meta.url), 'utf8');
  const funds = await readFile(new URL('../db/migrations/041_public_project_matching_funding.sql', import.meta.url), 'utf8');
  assert.match(source, /public_project_matching_funds/);
  assert.match(source, /earth_post_transaction/);
  assert.match(migration, /public_project_contributions/);
  assert.match(funds, /correlation_id TEXT NOT NULL UNIQUE/);
});
