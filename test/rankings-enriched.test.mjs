import test from 'node:test';
import assert from 'node:assert/strict';
import { listRankings } from '../cloudflare/src/read-postgres.ts';

test('listRankings returns enriched citizens, podium stats, tiers, and rank deltas', async () => {
  const mockRepo = {
    async query(sql, params) {
      if (sql.includes('FROM account_balances')) {
        return { rows: [{ human_id: 'H-0044', balance: '5000' }, { human_id: 'H-0012', balance: '4200' }] };
      }
      if (sql.includes('FROM cities')) {
        return {
          rows: [
            { id: 'city-new-tokyo', residents: 124, treasury: '28500', housing_capacity: 150, energy_capacity: 180, connectivity_capacity: 160, health_capacity: 140 },
          ],
        };
      }
      if (sql.includes('FROM corporations')) {
        return {
          rows: [
            { id: 'corp-kline-industrial', member_count: 14, treasury: '32000' },
          ],
        };
      }
      if (sql.includes('FROM technologies')) {
        return {
          rows: [
            { id: 'tech-quantum-core', name: 'Quantum Core', owner_id: 'H-0044', progress: 100 },
          ],
        };
      }
      if (sql.includes('FROM humans')) {
        return {
          rows: [
            { id: 'H-0044', display_name: 'Amara Vance', age_years: 42, standing: 840, legacy: 120, life_status: 'active', city_id: 'city-new-tokyo', dynasty_name: 'Vance Dynasty', balance: '5000' },
            { id: 'H-0012', display_name: 'Dmitri Rostov', age_years: 38, standing: 720, legacy: 95, life_status: 'active', city_id: 'city-london', dynasty_name: 'House of Rostov', balance: '4200' },
          ],
        };
      }
      if (sql.includes('FROM deceased_profiles')) {
        return {
          rows: [
            { dynasty_name: 'Vance Dynasty', deceased_count: 3, peak_legacy: 5400, peak_standing: 980 },
          ],
        };
      }
      if (sql.includes('FROM rankings_snapshots')) {
        return {
          rows: [
            { ranking_type: 'citizens', entity_id: 'H-0044', rank: 1, game_day: 100 },
            { ranking_type: 'citizens', entity_id: 'H-0012', rank: 3, game_day: 100 },
          ],
        };
      }
      return { rows: [] };
    },
  };

  const result = await listRankings(mockRepo);
  assert.equal(result.ok, true);

  const citizens = result.citizens;
  assert.equal(citizens.length, 2);

  // Check Citizen 1: Amara Vance
  assert.equal(citizens[0].displayName, 'Amara Vance');
  assert.equal(citizens[0].rank, 1);
  assert.equal(citizens[0].rankDelta, 0); // was 1, now 1
  assert.equal(citizens[0].compositeScore, 120 * 3 + 840 * 2 + Math.floor(5000 / 100)); // 360 + 1680 + 50 = 2090

  // Check Citizen 2: Dmitri Rostov
  assert.equal(citizens[1].displayName, 'Dmitri Rostov');
  assert.equal(citizens[1].rank, 2);
  assert.equal(citizens[1].rankDelta, 1); // was 3, now 2 => delta +1

  // Check Cities & QoL Index calculation
  const cities = result.cities;
  assert.equal(cities.length, 1);
  assert.equal(cities[0].id, 'city-new-tokyo');
  assert.equal(cities[0].qolIndex, Math.min(100, Math.round(((150 + 180 + 140) / 300) * 100)));
  assert.ok(cities[0].compositeIndex > 0);

  // Check Corporations & compositeIndex
  const corps = result.corporations;
  assert.equal(corps.length, 1);
  assert.equal(corps[0].id, 'corp-kline-industrial');
  assert.ok(corps[0].compositeIndex > 0);

  // Check Dynastic Houses
  const dynasties = result.dynasticHouses;
  assert.equal(dynasties.length, 1);
  assert.equal(dynasties[0].dynasty_name, 'Vance Dynasty');
});
