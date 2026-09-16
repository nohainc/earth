import test from 'node:test';
import assert from 'node:assert/strict';
import { getHouseOnboarding } from '../cloudflare/src/house-onboarding-postgres.ts';

test('House onboarding tolerates an empty adapter result for optional read facts', async () => {
  const repository = {
    async query(sql) {
      if (sql.includes('FROM house_onboarding_progress')) return { rows: [] };
      if (sql.includes("FROM world_state WHERE id = 'WORLD'")) return { rows: [{ game_day: '7' }] };
      if (sql.includes('FROM economic_assets')) return { rows: [] };
      if (sql.includes("asset.code = 'CREDIT'")) return { rows: [{ balance_units: '25' }] };
      if (sql.includes('FROM buildings')) return { rows: [{ count: '0' }] };
      if (sql.includes('FROM market_orders')) return { rows: [{ count: '0' }] };
      if (sql.includes('FROM house_residencies')) return undefined;
      throw new Error(`Unexpected onboarding query: ${sql}`);
    },
  };

  const result = await getHouseOnboarding(repository, 'HOUSE-TEST');

  assert.equal(result.currentGameDay, 7);
  assert.equal(result.status, 'ACTIVE');
  assert.deepEqual(result.facts.resourceBalances, []);
  assert.equal(result.facts.residence, null);
});
