import test from 'node:test';
import assert from 'node:assert/strict';
import { getNetWorthHistory, recordDailyNetWorthSnapshot } from '../cloudflare/src/net-worth-postgres.ts';

test('Net Worth PostgreSQL Module: queries history and aggregates summary accurately', async () => {
  const mockSnapshots = [
    {
      id: 'NW-H0044-155',
      human_id: 'H-0044',
      game_day: 155,
      liquid_credits: '15000.00',
      commodity_valuation: '8000.00',
      equity_valuation: '25000.00',
      real_estate_valuation: '12000.00',
      total_net_worth: '60000.00',
      created_at: new Date().toISOString(),
    },
    {
      id: 'NW-H0044-185',
      human_id: 'H-0044',
      game_day: 185,
      liquid_credits: '40000.00',
      commodity_valuation: '20000.00',
      equity_valuation: '68000.00',
      real_estate_valuation: '30000.00',
      total_net_worth: '158000.00',
      created_at: new Date().toISOString(),
    },
  ];

  const mockClient = {
    query: async (sql, params) => {
      if (sql.includes('FROM net_worth_snapshots')) {
        return { rows: mockSnapshots };
      }
      return { rows: [] };
    },
  };

  const result = await getNetWorthHistory(mockClient, 'H-0044');
  assert.equal(result.ok, true);
  assert.equal(result.snapshots.length, 2);
  assert.equal(result.summary.currentNetWorth, 158000);
  assert.equal(result.summary.liquidCredits, 40000);
  assert.equal(result.summary.peakNetWorth, 158000);
  assert.equal(result.summary.peakDay, 185);
  assert.equal(result.summary.growthRatePct > 100, true);
  assert.equal(typeof result.summary.assetAllocation.cashPct, 'number');
});

test('Net Worth PostgreSQL Module: recordDailyNetWorthSnapshot creates and stores snapshot', async () => {
  const mockClient = {
    query: async (sql, params) => {
      if (sql.includes('account_balances')) {
        return { rows: [{ balance: '35000.00' }] };
      }
      if (sql.includes('resource_balances')) {
        return { rows: [{ resource: 'energy', amount: '100' }, { resource: 'compute', amount: '50' }] };
      }
      if (sql.includes('INSERT INTO net_worth_snapshots')) {
        return {
          rows: [
            {
              id: params[0],
              human_id: params[1],
              game_day: params[2],
              liquid_credits: params[3],
              commodity_valuation: params[4],
              equity_valuation: params[5],
              real_estate_valuation: params[6],
              total_net_worth: params[7],
              created_at: new Date().toISOString(),
            },
          ],
        };
      }
      return { rows: [] };
    },
  };

  const res = await recordDailyNetWorthSnapshot(mockClient, 'H-0044', 186);
  assert.equal(res.ok, true);
  assert.equal(res.snapshot.human_id, 'H-0044');
  assert.equal(res.snapshot.game_day, 186);
  assert.equal(Number(res.snapshot.liquid_credits), 35000);
  assert.equal(Number(res.snapshot.commodity_valuation), 6000); // 100*30 + 50*60
});
