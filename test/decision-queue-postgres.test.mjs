import test from 'node:test';
import assert from 'node:assert/strict';
import { getDecisionQueue } from '../cloudflare/src/decision-queue-postgres.ts';

test('PostgreSQL decision queue derives service and obligation actions from current facts', async () => {
  const repository = {
    async query(sql) {
      const query = sql.toLowerCase();
      if (query.includes('from world_state')) return { rows: [{ game_day: '12' }] };
      if (query.includes('from house_succession_plans')) return { rows: [{ has_successor: true }] };
      if (query.includes('from house_need_assessments')) return { rows: [{ need_code: 'ENERGY', demand_units: '10', allocated_units: '0', shortfall_units: '10', risk_level: 'CRITICAL' }] };
      if (query.includes('from proposals')) return { rows: [] };
      if (query.includes('from financial_obligations')) return { rows: [{ unpaid: '25' }] };
      if (query.includes('from corporation_research_projects')) return { rows: [{ progress: '100' }] };
      throw new Error(`Unexpected query: ${sql}`);
    },
  };
  const result = await getDecisionQueue(repository, 'HOUSE-1');
  assert.equal(result.gameDay, 12);
  assert.equal(result.generatedFrom, 'postgres-canonical-facts');
  assert.equal(result.decisions.some((item) => item.id === 'decision-house-service-energy'), true);
  assert.equal(result.decisions.some((item) => item.id === 'decision-finance-tax-settlement'), true);
});
