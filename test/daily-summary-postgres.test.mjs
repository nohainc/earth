import test from 'node:test';
import assert from 'node:assert/strict';
import { getHouseDailySummary } from '../cloudflare/src/house-daily-summary-postgres.ts';

test('House Daily Summary derives deterministic values from V2 records', async () => {
  const repository = {
    async query(sql) {
      const normalized = sql.toLowerCase();
      if (normalized.includes('earth_get_current_game_time')) return { rows: [{ game_day: 5, game_minute: 0, total_game_minutes: 5 * 1440, genesis_at: '2026-01-01T00:00:00Z', server_now: '2026-01-01T00:00:00Z', real_seconds_per_game_minute: 1 }] };
      if (normalized.includes('from house_daily_statements')) return { rows: [{ opening_assets: { CREDIT: '40' }, closing_assets: { CREDIT: '100' }, production: { FOOD: '2' }, consumption: { FOOD: '1' }, market_activity: {}, obligations: {}, exceptions: {}, net_credit_units: '60', settlement_status: 'completed', rules_version: 'daily-settlement-v1', finalized_at: '2026-01-05T00:00:00Z', statement_created_at: '2026-01-05T00:01:00Z', statement_updated_at: '2026-01-05T00:01:00Z' }] };
      if (normalized.includes('from economic_transactions')) return { rows: [
        { transaction_kind: 'ASSET_TRANSFER', source_type: 'TAX', inflow_units: '0', outflow_units: '5' },
        { transaction_kind: 'MARKET_TRADE', source_type: 'MARKET', inflow_units: '30', outflow_units: '20' },
        { transaction_kind: 'ASSET_TRANSFER', source_type: 'PRIVATE_BUILDING_OPERATION', inflow_units: '70', outflow_units: '15' },
      ] };
      if (normalized.includes('from market_fills')) return { rows: [{ commodity: 'ENERGY', bought_units: '4', sold_units: '6', credit_spent_units: '20', credit_received_units: '30', volume_units: '10' }] };
      if (normalized.includes('from game_events')) return { rows: [{ id: 'event-1', event_type: 'BUILDING_CONSTRUCTION_COMPLETED', title: 'Building completed', details: 'null', game_day: 4, game_minute: 80, category: 'BUILDING' }] };
      if (normalized.includes('from notifications')) return { rows: [{ id: 'notification-1', notification_type: 'INFO', title: 'Completed', body: 'Building completed', game_day: 4, game_minute: 20, read_at: null }] };
      if (normalized.includes('from building_settlement_journals')) return { rows: [{ count: '2' }] };
      if (normalized.includes('from house_capacity_statements_v5')) return { rows: [{ assessed: '10', paid: '10', arrears: '0', status: 'CURRENT' }] };
      if (normalized.includes('from house_need_assessments')) return { rows: [] };
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
    capacityRent: { assessed: '10', paid: '10', arrears: '0', status: 'CURRENT' },
    cashflowBreakdown: [
      { category: 'BUILDING_OPERATIONS', inflowUnits: '70', outflowUnits: '15' },
      { category: 'MARKET', inflowUnits: '30', outflowUnits: '20' },
      { category: 'TAX', inflowUnits: '0', outflowUnits: '5' },
    ],
  });
  assert.deepEqual(result.statement?.openingAssets, { CREDIT: '40' });
  assert.equal(result.statement?.netCreditUnits, '60');
  assert.equal(result.buildings.completed.length, 1);
  assert.equal(result.alerts[0].read, false);
  assert.deepEqual(result.highlights, []);
  assert.deepEqual(result.resources.deltas, [{ resource: 'FOOD', producedUnits: '2', consumedUnits: '1', netUnits: '1' }]);
  assert.equal(result.buildings.operatedBuildingCount, 2);
  assert.equal(result.resourceShortfallCount, 0);
  assert.equal(result.governance.eventCount, 0);
  assert.equal(result.statementMetadata.immutable, true);
  assert.equal(result.statementMetadata.rulesVersion, 'daily-settlement-v1');
  assert.equal(result.timeline.length, 2);
  assert.equal(result.timeline[0].source, 'NOTIFICATION');
  assert.equal(result.timeline[1].source, 'GAME_EVENT');
  assert.deepEqual(result.marketActivity, [{ commodity: 'ENERGY', boughtUnits: '4', soldUnits: '6', creditSpentUnits: '20', creditReceivedUnits: '30', volumeUnits: '10' }]);
  assert.equal(result.financial.cashflowBreakdown.find((row) => row.category === 'MARKET').outflowUnits, '20');
  assert.equal(result.marketActivity[0].boughtUnits, '4');
  assert.equal(result.marketActivity[0].creditSpentUnits, '20');
  assert.deepEqual(result, await getHouseDailySummary(repository, 'HOUSE-1'));
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
      if (normalized.includes('from economic_transactions')) return { rows: [{ transaction_kind: 'ASSET_TRANSFER', source_type: 'PRIVATE_BUILDING_OPERATION', inflow_units: '9007199254740993', outflow_units: '2' }] };
      if (normalized.includes('from market_fills')) return { rows: [] };
      if (normalized.includes('from game_events')) return { rows: [] };
      if (normalized.includes('from notifications')) return { rows: [] };
      if (normalized.includes('from building_settlement_journals')) return { rows: [{ count: '1' }] };
      if (normalized.includes('from house_capacity_statements_v5')) return { rows: [{ assessed: '0', paid: '0', arrears: '0', status: 'CURRENT' }] };
      if (normalized.includes('from house_need_assessments')) return { rows: [] };
      throw new Error(`Unexpected query: ${sql}`);
    },
  };

  const result = await getHouseDailySummary(repository, 'HOUSE-1');
  assert.equal(result.financial.incomeUnits, '9007199254740993');
  assert.equal(result.financial.netCashflowUnits, '9007199254740991');
  assert.deepEqual(result.resources.deltas, [{ resource: 'COMPUTE', producedUnits: '9007199254740993', consumedUnits: '2', netUnits: '9007199254740991' }]);
});

test('House Daily Summary returns clean genesis summary for Day 0 before first settlement', async () => {
  const repository = {
    async query(sql) {
      const normalized = sql.toLowerCase();
      if (normalized.includes('earth_get_current_game_time')) return { rows: [{ game_day: 1, game_minute: 0, total_game_minutes: 1 * 1440, genesis_at: '2026-01-01T00:00:00Z', server_now: '2026-01-01T00:00:00Z', real_seconds_per_game_minute: 1 }] };
      if (normalized.includes('from house_daily_statements')) return { rows: [] };
      if (normalized.includes('from economic_transactions')) return { rows: [] };
      if (normalized.includes('from market_fills')) return { rows: [] };
      if (normalized.includes('from game_events')) return { rows: [] };
      if (normalized.includes('from notifications')) return { rows: [] };
      if (normalized.includes('from house_capacity_statements_v5')) return { rows: [] };
      if (normalized.includes('from house_need_assessments')) return { rows: [] };
      if (normalized.includes('from building_settlement_journals')) return { rows: [{ count: '0' }] };
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

test('House Daily Summary keeps historical operated count after current building status changes', async () => {
  const repository = {
    async query(sql) {
      const normalized = sql.toLowerCase();
      if (normalized.includes('earth_get_current_game_time')) return { rows: [{ game_day: 12, game_minute: 0 }] };
      if (normalized.includes('from house_daily_statements')) return { rows: [{ opening_assets: {}, closing_assets: {}, production: {}, consumption: {}, market_activity: {}, obligations: {}, exceptions: {}, net_credit_units: '0', settlement_status: 'completed', rules_version: 'v5', finalized_at: '2026-01-12T00:00:00Z' }] };
      if (normalized.includes('from building_settlement_journals') && normalized.includes('count(distinct')) return { rows: [{ count: '3' }] };
      if (normalized.includes('from buildings')) throw new Error('Historical summary must not read current building status');
      return { rows: [] };
    },
  };

  const result = await getHouseDailySummary(repository, 'HOUSE-1', 11);
  assert.equal(result.buildings.operatedBuildingCount, 3);
  assert.equal(result.statementMetadata.immutable, true);
});

test('House Daily Summary keeps read notifications in the historical timeline and formats CREDIT narratives exactly', async () => {
  const largeExpense = '9007199254740993';
  const repository = {
    async query(sql) {
      const normalized = sql.toLowerCase();
      if (normalized.includes('earth_get_current_game_time')) return { rows: [{ game_day: 4, game_minute: 0 }] };
      if (normalized.includes('from house_daily_statements')) return { rows: [{ opening_assets: {}, closing_assets: {}, production: {}, consumption: {}, market_activity: {}, obligations: {}, exceptions: {}, net_credit_units: `-${largeExpense}`, settlement_status: 'completed', rules_version: 'v5', finalized_at: '2026-01-04T00:00:00Z' }] };
      if (normalized.includes('from economic_transactions')) return { rows: [{ transaction_kind: 'ASSET_TRANSFER', source_type: 'TAX_COLLECTION', inflow_units: '1', outflow_units: largeExpense }] };
      if (normalized.includes('from notifications')) return { rows: [{ id: 'notification-read', notification_type: 'SHORTAGE', title: 'Food shortage', body: 'Food was short', game_day: 3, game_minute: 12, read_at: '2026-01-04T00:00:00Z' }] };
      if (normalized.includes('from building_settlement_journals')) return { rows: [{ count: '0' }] };
      return { rows: [] };
    },
  };

  const result = await getHouseDailySummary(repository, 'HOUSE-1', 3);
  assert.equal(result.alerts[0].read, true);
  assert.equal(result.timeline[0].id, 'notification-read');
  assert.equal(result.highlights.some((item) => item.id === 'alert:notification-read'), true);
  assert.match(result.highlights.find((item) => item.id === 'negative_cashflow').reason, /90071992547409\.93 C/);
});

test('House Daily Summary distinguishes genuine resource shortfalls from ordinary drawdown', async () => {
  const repository = {
    async query(sql) {
      const normalized = sql.toLowerCase();
      if (normalized.includes('earth_get_current_game_time')) return { rows: [{ game_day: 6, game_minute: 0 }] };
      if (normalized.includes('from house_daily_statements')) return { rows: [{ opening_assets: { FOOD: '100' }, closing_assets: { FOOD: '90' }, production: {}, consumption: { FOOD: '10' }, market_activity: {}, obligations: {}, exceptions: {}, net_credit_units: '0', settlement_status: 'completed', finalized_at: '2026-01-06T00:00:00Z' }] };
      if (normalized.includes('from house_need_assessments')) return { rows: [{ need_code: 'FOOD', shortfall_units: '2', risk_level: 'HIGH' }] };
      if (normalized.includes('from building_settlement_journals')) return { rows: [{ count: '0' }] };
      return { rows: [] };
    },
  };

  const result = await getHouseDailySummary(repository, 'HOUSE-1', 5);
  assert.equal(result.resourceShortfallCount, 1);
  assert.equal(result.highlights.some((item) => item.id === 'resource-attention:FOOD'), true);

  const ordinaryDrawdownRepository = {
    ...repository,
    async query(sql) {
      const result = await repository.query(sql);
      if (sql.toLowerCase().includes('from house_need_assessments')) return { rows: [] };
      return result;
    },
  };
  const ordinary = await getHouseDailySummary(ordinaryDrawdownRepository, 'HOUSE-1', 5);
  assert.equal(ordinary.resourceShortfallCount, 0);
  assert.equal(ordinary.highlights.some((item) => item.id === 'resource-attention:FOOD'), false);
});
