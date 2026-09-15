import test from 'node:test';
import assert from 'node:assert/strict';
import { getHouseDailySummary } from '../cloudflare/src/house-daily-summary-postgres.ts';

test('House Daily Summary derives deterministic values from V2 records', async () => {
  const repository = {
    async query(sql) {
      const normalized = sql.toLowerCase();
      if (normalized.includes('from world_state')) return { rows: [{ game_day: 5 }] };
      if (normalized.includes('from house_daily_statements')) return { rows: [{ opening_assets: { CREDIT: '40' }, closing_assets: { CREDIT: '100' }, production: { FOOD: '2' }, consumption: { FOOD: '1' }, market_activity: {}, obligations: {}, exceptions: {}, net_credit_units: '60' }] };
      if (normalized.includes('as income')) return { rows: [{ income: '100', expenses: '40' }] };
      if (normalized.includes('as taxes')) return { rows: [{ taxes: '5' }] };
      if (normalized.includes('from market_fills')) return { rows: [{ commodity: 'ENERGY', purchases: '20', sales: '30', volume: '50' }] };
      if (normalized.includes('from game_events')) return { rows: [{ id: 'event-1', event_type: 'BUILDING_CONSTRUCTION_COMPLETED', title: 'Building completed', details: 'null', game_day: 4, game_minute: 20, category: 'BUILDING' }] };
      if (normalized.includes('from notifications')) return { rows: [{ id: 'notification-1', notification_type: 'INFO', title: 'Completed', body: 'Building completed', game_day: 4, game_minute: 20, read_at: null }] };
      throw new Error(`Unexpected query: ${sql}`);
    },
  };

  const result = await getHouseDailySummary(repository, 'HOUSE-1');
  assert.equal(result.version, 1);
  assert.equal(result.currentGameDay, 5);
  assert.equal(result.summaryDay, 4);
  assert.deepEqual(result.financial, {
    income: 100,
    expenses: 40,
    net: 60,
    taxes: 5,
    marketPurchases: 20,
    marketSales: 30,
  });
  assert.deepEqual(result.statement?.openingAssets, { CREDIT: '40' });
  assert.equal(result.statement?.netCreditUnits, '60');
  assert.equal(result.buildings.completed.length, 1);
  assert.equal(result.alerts[0].read, false);
  assert.deepEqual(result.highlights, [{ code: 'taxes_paid', reason: 'Recorded tax payments totaled 5 CREDIT on game day 4.' }]);
});
