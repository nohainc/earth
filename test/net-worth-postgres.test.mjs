import test from 'node:test';
import assert from 'node:assert/strict';
import { getNetWorthHistory, recordDailyNetWorthSnapshot } from '../cloudflare/src/net-worth-postgres.ts';

test('House net worth history is keyed by House and preserves exact units', async () => {
  const snapshots = [{
    id: 'NW-HOUSE-1-185', house_id: 'HOUSE-1', current_human_id: 'H-0044', game_day: 185,
    liquid_credits_units: '900719925474099300', deposit_principal_units: '2500',
    commodity_valuation_units: '8000', buildings_valuation_units: '12000', debt_units: '500',
    total_net_worth_units: '900719925474121300', valuation_policy: 'HOUSE_NET_WORTH_V5_COST_BASIS_MARKET_INVENTORY',
    created_at: new Date().toISOString(),
  }];
  const client = { query: async (sql) => {
    if (sql.includes('FROM humans')) return { rows: [{ house_id: 'HOUSE-1' }] };
    if (sql.includes('FROM net_worth_snapshots')) return { rows: snapshots };
    return { rows: [] };
  } };
  const result = await getNetWorthHistory(client, 'H-0044');
  assert.equal(result.houseId, 'HOUSE-1');
  assert.equal(result.snapshots[0].house_id, 'HOUSE-1');
  assert.equal(result.summary.currentNetWorthUnits, '900719925474121300');
  assert.equal(result.summary.liquidCreditsUnits, '900719925474099300');
  assert.match(result.valuationPolicy.description, /Corporation equity is excluded/);
});

test('House net worth snapshot uses exact unit arithmetic and debt subtraction', async () => {
  const client = {
    query: async (sql, params) => {
      if (sql.includes('FROM humans')) return { rows: [{ house_id: 'HOUSE-1' }] };
      if (sql.includes('FROM net_worth_snapshots')) return { rows: [] };
      if (sql.includes('INSERT INTO net_worth_snapshots')) return { rows: [{ house_id: params[1], game_day: params[3], total_net_worth_units: params[9], liquid_credits_units: params[4], deposit_principal_units: params[5], commodity_valuation_units: params[6], buildings_valuation_units: params[7], debt_units: params[8] }] };
      if (sql.includes('economic_assets')) return { rows: [{ resource: 'energy', quantity_units: '10' }] };
      if (sql.includes('economic_accounts')) return { rows: [{ units: '900719925474099300' }] };
      if (sql.includes('bank_deposits')) return { rows: [{ units: '2500' }] };
      if (sql.includes('bank_loans')) return { rows: [{ units: '500' }] };
      if (sql.includes('market_instruments')) return { rows: [{ resource: 'energy', price_units: '30' }] };
      if (sql.includes('building_catalog')) return { rows: [{ units: '12000' }] };
      return { rows: [] };
    },
    transaction: async (work) => work(client),
  };
  const result = await recordDailyNetWorthSnapshot(client, 'H-0044', 186);
  assert.equal(result.snapshot.house_id, 'HOUSE-1');
  assert.equal(result.snapshot.total_net_worth_units, '900719925474113600');
});
