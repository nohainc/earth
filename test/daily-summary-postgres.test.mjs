import test from 'node:test';
import assert from 'node:assert/strict';
import { getHouseDailySummary } from '../cloudflare/src/house-daily-summary-postgres.ts';

test('House Daily Summary derives deterministic values from V2 records', async () => {
  const repository = {
    async query(sql) {
      const normalized = sql.toLowerCase();
      if (normalized.includes('earth_get_current_game_time')) return { rows: [{ game_day: 5, game_minute: 0, total_game_minutes: 5 * 1440, genesis_at: '2026-01-01T00:00:00Z', server_now: '2026-01-01T00:00:00Z', real_seconds_per_game_minute: 1 }] };
      if (normalized.includes('from house_daily_statements')) return { rows: [{ opening_assets: { CREDIT: '40' }, closing_assets: { CREDIT: '100' }, production: { FOOD: '2' }, consumption: { FOOD: '1' }, market_activity: {}, obligations: {}, exceptions: {}, net_credit_units: '60' }] };
      if (normalized.includes('as income')) return { rows: [{ income: '100', expenses: '40' }] };
      if (normalized.includes('as taxes')) return { rows: [{ taxes: '5' }] };
      if (normalized.includes('from market_fills')) return { rows: [{ commodity: 'ENERGY', purchases: '20', sales: '30', volume: '50' }] };
      if (normalized.includes('from game_events')) return { rows: [{ id: 'event-1', event_type: 'BUILDING_CONSTRUCTION_COMPLETED', title: 'Building completed', details: 'null', game_day: 4, game_minute: 20, category: 'BUILDING' }] };
      if (normalized.includes('from notifications')) return { rows: [{ id: 'notification-1', notification_type: 'INFO', title: 'Completed', body: 'Building completed', game_day: 4, game_minute: 20, read_at: null }] };
      if (normalized.includes('from buildings')) return { rows: [{ count: '2' }] };
      throw new Error(`Unexpected query: ${sql}`);
    },
  };

  const result = await getHouseDailySummary(repository, 'HOUSE-1');
  assert.equal(result.version, 2);
  assert.equal(result.currentGameDay, 5);
  assert.equal(result.summaryDay, 4);
  assert.deepEqual(result.financial, {
    incomeUnits: '100',
    expensesUnits: '40',
    netCashflowUnits: '60',
    taxesUnits: '5',
    marketPurchasesUnits: '20',
    marketSalesUnits: '30',
  });
  assert.deepEqual(result.statement?.openingAssets, { CREDIT: '40' });
  assert.equal(result.statement?.netCreditUnits, '60');
  assert.equal(result.buildings.completed.length, 1);
  assert.equal(result.alerts[0].read, false);
  assert.deepEqual(result.highlights, []);
  assert.deepEqual(result.resources.deltas, [{ resource: 'FOOD', produced: '2', consumed: '1', net: '1' }]);
  assert.equal(result.buildings.operatedBuildingCount, 2);
  assert.equal(result.resourceShortfallCount, 0);
  assert.equal(result.governance.eventCount, 0);
});

test('House Daily Summary returns clean default summary when statement row is missing', async () => {
  const repository = {
    async query(sql) {
      if (sql.toLowerCase().includes('earth_get_current_game_time')) return { rows: [{ game_day: 5, game_minute: 0, total_game_minutes: 5 * 1440, genesis_at: '2026-01-01T00:00:00Z', server_now: '2026-01-01T00:00:00Z', real_seconds_per_game_minute: 1 }] };
      if (sql.toLowerCase().includes('from house_daily_statements')) return { rows: [] };
      return { rows: [] };
    },
  };

  const result = await getHouseDailySummary(repository, 'HOUSE-1');
  assert.equal(result.version, 2);
  assert.equal(result.currentGameDay, 5);
  assert.equal(result.summaryDay, 4);
  assert.equal(result.financial.incomeUnits, '0');
  assert.equal(result.financial.expensesUnits, '0');
  assert.equal(result.financial.netCashflowUnits, '0');
  assert.deepEqual(result.statement?.openingAssets, {});
  assert.deepEqual(result.statement?.closingAssets, {});
  assert.deepEqual(result.resources.deltas, []);
});

test('House Daily Summary preserves large fixed-point units exactly', async () => {
  const repository = {
    async query(sql) {
      const normalized = sql.toLowerCase();
      if (normalized.includes('earth_get_current_game_time')) return { rows: [{ game_day: 8, game_minute: 0, total_game_minutes: 8 * 1440, genesis_at: '2026-01-01T00:00:00Z', server_now: '2026-01-01T00:00:00Z', real_seconds_per_game_minute: 1 }] };
      if (normalized.includes('from house_daily_statements')) return { rows: [{ opening_assets: {}, closing_assets: {}, production: { COMPUTE: '9007199254740993' }, consumption: { COMPUTE: '2' }, market_activity: {}, obligations: {}, exceptions: {}, net_credit_units: '9007199254740991' }] };
      if (normalized.includes('as income')) return { rows: [{ income: '9007199254740993', expenses: '2' }] };
      if (normalized.includes('as taxes')) return { rows: [{ taxes: '0' }] };
      if (normalized.includes('from market_fills')) return { rows: [] };
      if (normalized.includes('from game_events')) return { rows: [] };
      if (normalized.includes('from notifications')) return { rows: [] };
      if (normalized.includes('from buildings')) return { rows: [{ count: '1' }] };
      throw new Error(`Unexpected query: ${sql}`);
    },
  };

  const result = await getHouseDailySummary(repository, 'HOUSE-1');
  assert.equal(result.financial.incomeUnits, '9007199254740993');
  assert.equal(result.financial.netCashflowUnits, '9007199254740991');
  assert.deepEqual(result.resources.deltas, [{ resource: 'COMPUTE', produced: '9007199254740993', consumed: '2', net: '9007199254740991' }]);
});

test('House Daily Summary returns clean genesis summary for Day 0 before first settlement', async () => {
  const repository = {
    async query(sql) {
      const normalized = sql.toLowerCase();
      if (normalized.includes('earth_get_current_game_time')) return { rows: [{ game_day: 1, game_minute: 0, total_game_minutes: 1 * 1440, genesis_at: '2026-01-01T00:00:00Z', server_now: '2026-01-01T00:00:00Z', real_seconds_per_game_minute: 1 }] };
      if (normalized.includes('from house_daily_statements')) return { rows: [] };
      if (normalized.includes('as income')) return { rows: [{ income: '0', expenses: '0' }] };
      if (normalized.includes('as taxes')) return { rows: [{ taxes: '0' }] };
      if (normalized.includes('from market_fills')) return { rows: [] };
      if (normalized.includes('from game_events')) return { rows: [] };
      if (normalized.includes('from notifications')) return { rows: [] };
      if (normalized.includes('from house_capacity_statements_v5')) return { rows: [] };
      if (normalized.includes('from buildings')) return { rows: [{ count: '0' }] };
      throw new Error(`Unexpected query: ${sql}`);
    },
  };

  const result = await getHouseDailySummary(repository, 'HOUSE-1');
  assert.equal(result.version, 2);
  assert.equal(result.currentGameDay, 1);
  assert.equal(result.summaryDay, 0);
  assert.equal(result.financial.incomeUnits, '0');
  assert.equal(result.financial.expensesUnits, '0');
  assert.equal(result.financial.netCashflowUnits, '0');
  assert.deepEqual(result.statement?.openingAssets, {});
  assert.deepEqual(result.statement?.closingAssets, {});
  assert.deepEqual(result.resources.deltas, []);
});
