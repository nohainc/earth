import test from 'node:test';
import assert from 'node:assert/strict';
import { getDailyBriefing } from '../cloudflare/src/daily-briefing-postgres.ts';

test('getDailyBriefing calculates net wealth delta, cashflow, and recommendations', async () => {
  const mockClient = {
    async query(sql, params) {
      if (sql.includes('from world_ticks')) {
        return { rows: [{ game_day: 185 }] };
      }
      if (sql.includes('from net_worth_snapshots')) {
        return {
          rows: [
            {
              game_day: 185,
              total_net_worth: '158000.00',
              liquid_credits: '40000.00',
              commodity_valuation: '20000.00',
              equity_valuation: '68000.00',
            },
            {
              game_day: 184,
              total_net_worth: '152400.00',
              liquid_credits: '38000.00',
              commodity_valuation: '19400.00',
              equity_valuation: '66000.00',
            },
          ],
        };
      }
      if (sql.includes('from businesses')) {
        return { rows: [{ count: '2' }] };
      }
      if (sql.includes('from governance_proposals')) {
        return { rows: [{ count: '3' }] };
      }
      if (sql.includes('from notifications')) {
        return { rows: [{ count: '2' }] };
      }
      return { rows: [] };
    },
  };

  const res = await getDailyBriefing(mockClient, 'H-0044');

  assert.equal(res.ok, true);
  assert.equal(res.gameDay, 185);
  assert.equal(res.sinceDay, 184);
  assert.equal(res.netWealthDelta.current, 158000);
  assert.equal(res.netWealthDelta.previous, 152400);
  assert.equal(res.netWealthDelta.delta, 5600);
  assert.ok(res.netWealthDelta.deltaPct > 0);

  assert.equal(res.cashflow.totalIncome, 14250);
  assert.equal(res.cashflow.netProfit, 9430);
  assert.equal(res.marketMovements.length, 5);
  assert.equal(res.businessSummary.activeBusinesses, 2);
  assert.equal(res.civicSummary.cityResidency, 'New Geneva');
  assert.ok(res.recommendedDirectives.length >= 3);
});
