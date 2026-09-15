import test from 'node:test';
import assert from 'node:assert/strict';
import { settleHouseNeedsAndServices } from '../cloudflare/src/service-settlement-postgres.ts';

test('service capacity is allocated once across Houses in deterministic order', async () => {
  const assessments = [];
  const allocations = [];
  const repository = {
    async query(sql) {
      const query = sql.toLowerCase();
      if (query.includes('from need_rules')) return { rows: [{ need_code: 'ENERGY', service_type_code: 'ENERGY', demand_units_per_human: '1', critical_threshold_bps: 7500, rules_version: 'needs-v1' }] };
      if (query.includes('from houses h')) return { rows: [{ house_id: 'HOUSE-1', economic_id: 'ECON-1', territory_id: 'T-1', residents: '1' }, { house_id: 'HOUSE-2', economic_id: 'ECON-2', territory_id: 'T-1', residents: '1' }] };
      if (query.includes('from world_conditions')) return { rows: [] };
      if (query.includes('from organization_economies')) return { rows: [] };
      if (query.includes('from service_types')) return { rows: [{ code: 'ENERGY', daily_price_units: '0' }] };
      if (query.includes('from buildings b')) return { rows: [{ territory_id: 'T-1', service_code: 'ENERGY', economic_id: 'PROVIDER-1', owner_type: 'CORPORATION', capacity_units: '1' }] };
      if (query.includes('from house_need_assessments')) return { rows: [] };
      if (query.includes('insert into service_allocations')) { allocations.push(sql); return { rows: [] }; }
      if (query.includes('insert into house_need_assessments')) { assessments.push(sql); return { rows: [] }; }
      throw new Error(`Unexpected query: ${sql}`);
    },
  };
  const result = await settleHouseNeedsAndServices(repository, 7, 0, 1);
  assert.equal(result.houses, 2);
  assert.equal(result.allocations, 1);
  assert.equal(result.shortfalls, 1);
  assert.equal(allocations.length, 1);
  assert.equal(assessments.length, 2);
});
