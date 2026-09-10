import test from 'node:test';
import assert from 'node:assert/strict';
import { computeResourceFlows } from '../cloudflare/src/engines/resource-flow-engine.ts';

test('computeResourceFlows calculates accurate continuous rates from buildings and research', async () => {
  const mockRepo = {
    query: async (sql, params) => {
      if (sql.includes('FROM buildings b')) {
        return {
          rows: [
            {
              asset_code: 'CREDIT',
              output_units: 1440,
              upkeep_units: 0,
              operating_units: 144,
              effective_output_multiplier: 1,
              effective_cost_multiplier: 1,
            },
            {
              asset_code: 'ENERGY',
              output_units: 0,
              upkeep_units: 288,
              operating_units: 0,
              effective_output_multiplier: 1,
              effective_cost_multiplier: 1,
            },
          ],
        };
      }
      if (sql.includes('FROM research_projects')) {
        return {
          rows: [
            { budget: '288' },
          ],
        };
      }
      return { rows: [] };
    },
  };

  const flows = await computeResourceFlows(mockRepo, 'H-0044');

  // Daily gross credit production: 1440 -> 1.0/sec
  assert.equal(flows.credits.grossProductionPerSecond, 1.0);
  // Daily credit consumption: 144 (operating) + 288 (research) = 432 -> 0.3/sec
  assert.equal(flows.credits.grossConsumptionPerSecond, 0.3);
  // Net per second: 1.0 - 0.3 = 0.7
  assert.equal(flows.credits.netPerSecond, 0.7);
  // Net per game day: 0.7 * 1440 = 1008
  assert.equal(flows.credits.netPerGameDay, 1008);

  // Daily gross energy consumption: 288 -> 0.2/sec
  assert.equal(flows.energy.grossConsumptionPerSecond, 0.2);
  assert.equal(flows.energy.netPerSecond, -0.2);
  assert.equal(flows.energy.netPerGameDay, -288);
});
