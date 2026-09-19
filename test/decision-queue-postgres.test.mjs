import test from 'node:test';
import assert from 'node:assert/strict';
import { getDecisionQueue } from '../cloudflare/src/decision-queue-postgres.ts';

test('PostgreSQL decision queue derives service and obligation actions from current facts', async () => {
  const repository = {
    async query(sql) {
      const query = sql.toLowerCase();
      if (query.includes('earth_get_current_game_time') || query.includes('from world_state')) return { rows: [{ game_day: '12', cycle: '1', cycle_progress_bps: '5000' }] };
      if (query.includes('from house_succession_plans')) return { rows: [{ has_successor: true }] };
      if (query.includes('from house_need_assessments')) return { rows: [{ need_code: 'ENERGY', demand_units: '10', allocated_units: '0', shortfall_units: '10', risk_level: 'CRITICAL' }] };
      if (query.includes('from v5_governance_proposals')) return { rows: [] };
      if (query.includes('from financial_obligations')) return { rows: [{ unpaid: '25' }] };
      if (query.includes('from corporation_research_projects')) return { rows: [{ progress: '100' }] };
      if (query.includes('from market_instruments')) return { rows: [] };
      if (query.includes('from buildings')) return { rows: [] };
      if (query.includes('from market_orders')) return { rows: [{ open_count: '0', expiring_count: '0' }] };
      throw new Error(`Unexpected query: ${sql}`);
    },
  };
  const result = await getDecisionQueue(repository, 'HOUSE-1');
  assert.equal(result.gameDay, 12);
  assert.equal(result.generatedFrom, 'postgres-canonical-facts');
  assert.equal(result.decisions.some((item) => item.id === 'decision-house-service-energy'), true);
  assert.equal(result.decisions.some((item) => item.id === 'decision-finance-tax-settlement'), true);
});
