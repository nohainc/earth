import test from 'node:test';
import assert from 'node:assert/strict';
import { calculateMatching } from '../cloudflare/src/public-projects.ts';
import { readFile } from 'node:fs/promises';

test('matching favors breadth but remains integer and pool/target capped', () => {
  const one = calculateMatching({ contributionUnits: 100n, supporterCount: 1n, poolRemaining: 10000n, targetRemaining: 10000n, matchBps: 10000n, policy: 'BREADTH_MATCH', breadthBonusBpsPerSupporter: 25n, breadthSupporterCap: 100n });
  const many = calculateMatching({ contributionUnits: 100n, supporterCount: 20n, poolRemaining: 10000n, targetRemaining: 10000n, matchBps: 10000n, policy: 'BREADTH_MATCH', breadthBonusBpsPerSupporter: 25n, breadthSupporterCap: 100n });
  assert.ok(many > one);
  assert.ok(many <= 10000n);
});

test('matching policies are explicit and breadth matching has no supporter-101 discontinuity', () => {
  const atCap = calculateMatching({ contributionUnits: 1000n, supporterCount: 100n, poolRemaining: 100000n, targetRemaining: 100000n, matchBps: 10000n, policy: 'BREADTH_MATCH', breadthBonusBpsPerSupporter: 25n, breadthSupporterCap: 100n });
  const afterCap = calculateMatching({ contributionUnits: 1000n, supporterCount: 101n, poolRemaining: 100000n, targetRemaining: 100000n, matchBps: 10000n, policy: 'BREADTH_MATCH', breadthBonusBpsPerSupporter: 25n, breadthSupporterCap: 100n });
  const linear = calculateMatching({ contributionUnits: 1000n, supporterCount: 101n, poolRemaining: 100000n, targetRemaining: 100000n, matchBps: 10000n, policy: 'LINEAR_MATCH' });
  const none = calculateMatching({ contributionUnits: 1000n, supporterCount: 101n, poolRemaining: 100000n, targetRemaining: 100000n, matchBps: 10000n, policy: 'NONE' });
  assert.equal(atCap, afterCap);
  assert.equal(linear, 1000n);
  assert.equal(none, 0n);
});

test('Initiatives use canonical escrow contributions and versioned matching policies', async () => {
  const source = await readFile(new URL('../cloudflare/src/initiatives-postgres.ts', import.meta.url), 'utf8');
  const migration = await readFile(new URL('../db/migrations/153_v5_initiative_financial_lifecycle.sql', import.meta.url), 'utf8');
  const policy = await readFile(new URL('../db/migrations/155_initiative_funding_policies.sql', import.meta.url), 'utf8');
  assert.match(source, /initiative_contributions/);
  assert.match(source, /initiative_funding_policies/);
  assert.match(source, /postEconomicTransaction/);
  assert.match(migration, /correlation_id TEXT NOT NULL UNIQUE/);
  assert.match(policy, /BREADTH_MATCH/);
  assert.match(policy, /max_house_contribution_units/);
});
