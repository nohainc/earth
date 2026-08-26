import test from 'node:test';
import assert from 'node:assert/strict';
import { settleContinuousRankings } from '../cloudflare/src/engines/rankings-engine.ts';

test('settleContinuousRankings calculates relative data-driven indexes and upserts into civic_rankings', async () => {
  const upsertedRows = [];

  const mockRepo = {
    async query(sql, params) {
      if (sql.includes('FROM humans\n') || sql.includes('FROM humans ')) {
        return {
          rows: [
            { id: 'H-1', display_name: 'Citizen One', standing: 1000, legacy: 100, credits: 50000, machine_assets_val: 10000, city_name: 'Metropolis', corporation_name: 'Alpha Corp' },
            { id: 'H-2', display_name: 'Citizen Two', standing: 500, legacy: 200, credits: 20000, machine_assets_val: 0, city_name: null, corporation_name: null },
          ],
        };
      }
      if (sql.includes('FROM corporations c\n') || sql.includes('FROM corporations c ')) {
        return {
          rows: [
            { id: 'corp-1', name: 'Alpha Corp', member_count: 50, treasury: 200000 },
            { id: 'corp-2', name: 'Beta Corp', member_count: 100, treasury: 50000 },
          ],
        };
      }
      if (sql.includes('FROM cities c\n') || sql.includes('FROM cities c ')) {
        return {
          rows: [
            { id: 'city-1', name: 'Metropolis', corporation_id: 'corp-1', residents: 100, housing_capacity: 100, energy_capacity: 100, connectivity_capacity: 100, health_capacity: 100, treasury: 50000, corporation_name: 'Alpha Corp', businesses_count: 8, buildings_valuation: 20000 },
            { id: 'city-2', name: 'Oasis', corporation_id: null, residents: 50, housing_capacity: 100, energy_capacity: 50, connectivity_capacity: 50, health_capacity: 80, treasury: 25000, corporation_name: null, businesses_count: 2, buildings_valuation: 5000 },
          ],
        };
      }
      if (sql.includes('INSERT INTO civic_rankings')) {
        upsertedRows.push({
          id: params[0],
          entityId: params[1],
          entityName: params[2],
          rank: params[3],
          finalScore: params[4],
          metricsLine: params[5],
          subIndexes: JSON.parse(params[6]),
          rawMetrics: JSON.parse(params[7]),
          affiliation: params[8],
          gameDay: params[9],
        });
        return { rows: [] };
      }
      return { rows: [] };
    },
  };

  const res = await settleContinuousRankings(mockRepo, 105);
  assert.equal(res.corporationsSettled, 2);
  assert.equal(res.citiesSettled, 2);
  assert.equal(res.citizensSettled, 2);
  assert.equal(res.gameDay, 105);

  // Check City upserts
  const city1 = upsertedRows.find((r) => r.entityId === 'city-1');
  assert.ok(city1);
  // City 1 Capitalization: 50000 + 20000 + (100+100+100+100)*25 = 80,000 -> "80k Cap · 8 Biz · 100 Res"
  assert.equal(city1.metricsLine, '80k Cap · 8 Biz · 100 Res');

  // Check Corporation upserts (Rollup from City 1)
  const corp1 = upsertedRows.find((r) => r.entityId === 'corp-1');
  const corp2 = upsertedRows.find((r) => r.entityId === 'corp-2');
  assert.ok(corp1);
  assert.ok(corp2);

  // Corp 1 Total Cap = 200,000 + 80,000 = 280,000 -> "280k Cap · 8 Biz · 100 Res"
  assert.equal(corp1.metricsLine, '280k Cap · 8 Biz · 100 Res');
  assert.ok(corp1.finalScore > 0);

  // Check Citizens upserts
  const h1 = upsertedRows.find((r) => r.entityId === 'H-1');
  const h2 = upsertedRows.find((r) => r.entityId === 'H-2');
  assert.ok(h1);
  assert.ok(h2);

  // H1 Cap: 50000 + 10000 = 60000 -> "100 Leg · 1000 Std · 60k Cap"
  assert.equal(h1.metricsLine, '100 Leg · 1000 Std · 60k Cap');
  assert.equal(h1.affiliation, 'Alpha Corp · Metropolis');

  // H2 Cap: 20000 -> "200 Leg · 500 Std · 20k Cap"
  assert.equal(h2.metricsLine, '200 Leg · 500 Std · 20k Cap');
  assert.equal(h2.affiliation, 'Independent');
});
