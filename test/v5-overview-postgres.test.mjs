import test from 'node:test';
import assert from 'node:assert/strict';
import { getV5Overview } from '../cloudflare/src/v5-overview-postgres.ts';

test('getV5Overview returns canonical V5 command overview with typed summaries', async () => {
  const repository = {
    async query(sql, params) {
      const query = sql.toLowerCase();
      if (query.includes('earth_get_current_game_time') || query.includes('from world_state')) {
        return { rows: [{ game_day: '100', cycle: '1', cycle_progress_bps: '5000' }] };
      }
      if (query.includes('from houses')) {
        return { rows: [{ id: 'H-100', house_name: 'House Aurelius', generation: 2, status: 'ACTIVE' }] };
      }
      if (query.includes('from house_affiliations')) {
        return { rows: [{ corporation_id: 'CORP-1', status: 'ACTIVE' }] };
      }
      if (query.includes('from economic_accounts')) {
        return { rows: [{ balance_units: '50000' }] };
      }
      if (query.includes('from house_daily_statements')) {
        return { rows: [{ game_day: 99, opening_assets: 10000, closing_assets: 15000, net_credit_units: 5000 }] };
      }
      if (query.includes('from v5_capacity_delinquency_state')) {
        return { rows: [{ status: 'CURRENT', arrears_since_game_day: null, consecutive_missed_days: 0 }] };
      }
      if (query.includes('count(*) filter (where b.status = \'active\')')) {
        return { rows: [{ total_count: '5', active_count: '4', suspended_count: '1', other_count: '0' }] };
      }
      if (query.includes('from market_instruments')) {
        return {
          rows: [
            { product: 'energy', supply: '100', demand: '200', price: '250' },
            { product: 'material', supply: '50', demand: '80', price: '400' },
          ],
        };
      }
      if (query.includes('from house_succession_plans')) {
        return { rows: [{ has_successor: true }] };
      }
      if (query.includes('from house_need_assessments')) {
        return { rows: [] };
      }
      if (query.includes('from proposals')) {
        return { rows: [] };
      }
      if (query.includes('from financial_obligations')) {
        return { rows: [{ unpaid: '0' }] };
      }
      if (query.includes('from corporation_research_projects')) {
        return { rows: [{ progress: '100' }] };
      }
      if (query.includes('from buildings')) {
        return { rows: [] };
      }
      if (query.includes('from v5_house_settlement_profiles')) {
        return { rows: [{ corporation_id: 'CORP-1', residential_units: '50', building_units: '50', total_units: '100' }] };
      }
      if (query.includes('from resolved_constitution_snapshots_v5')) {
        return { rows: [{ id: 'SNAP-1', rules_json: { 'EARTH.CAPACITY.STANDARD': '100', 'EARTH.CAPACITY.BASE_RATE': '1000', 'EARTH.CAPACITY.HOUSE_PROGRESSIVE_SCHEDULE': 'DEFAULT', 'EARTH.CAPACITY.PROGRESSIVE_SCHEDULE': 'DEFAULT' } }] };
      }
      if (query.includes('from constitutional_rule_versions_v5')) {
        return { rows: [] };
      }
      if (query.includes('from progressive_policy_brackets')) {
        return { rows: [] };
      }
      if (query.includes('from v5_capacity_state')) {
        return { rows: [{ subject_type: 'HOUSE', subject_id: 'H-100', capacity_allocated_kw: '100', capacity_used_kw: '80' }] };
      }
      if (query.includes('from v5_capacity_rent_invoices')) {
        return { rows: [] };
      }
      throw new Error(`Unexpected query: ${sql}`);
    },
  };

  const overview = await getV5Overview(repository, 'H-100');

  assert.equal(overview.ok, true);
  assert.equal(overview.gameDay, 100);
  assert.equal(overview.house.id, 'H-100');
  assert.equal(overview.house.name, 'House Aurelius');
  assert.equal(overview.finance.availableWalletUnits, '50000');
  assert.equal(overview.buildings.totalCount, 5);
  assert.equal(overview.buildings.activeCount, 4);
  assert.equal(overview.buildings.suspendedCount, 1);
  assert.equal(overview.market.energyPriceUnits, '250');
  assert.equal(overview.market.materialsPriceUnits, '400');
  assert.equal(overview.decisions.totalCount >= 0, true);
});
