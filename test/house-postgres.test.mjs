import test from 'node:test';
import assert from 'node:assert/strict';
import {
  getHouseProfile,
  updateHouseProfile,
} from '../cloudflare/src/house-postgres.ts';

function createMockDb(initialData = {}) {
  const houses = initialData.houses || [
    {
      id: 'HSE-H0044',
      house_name: 'House Vance',
      motto: 'From the Red Dust We Build Eternity',
      current_human_id: 'H-0044',
      generation: 2,
      status: 'ACTIVE',
      dynasty_legacy: '350',
      created_at: new Date().toISOString(),
    },
  ];

  const repository = {
    async query(sql, params = []) {
      const s = sql.trim().toUpperCase();

      if (s.includes('FROM HUMANS WHERE ID = $1')) {
        return { rows: [{ id: params[0], display_name: 'Amara Vance', birth_game_day: 1, age_years: 34, status: 'ACTIVE', standing: '100', final_legacy: '170' }] };
      }

      if (s.includes('FROM HOUSES WHERE ID = $1') || s.includes('FROM DYNASTIES WHERE ID = $1')) {
        const found = houses.find((d) => d.id === params[0]);
        return { rows: found ? [found] : [] };
      }

      if ((s.includes('UPDATE HOUSES SET MOTTO = $1') || s.includes('UPDATE DYNASTIES SET MOTTO = $1'))) {
        const dyn = houses.find((d) => d.id === params[2]);
        if (dyn) {
          dyn.motto = params[0];
          dyn.house_name = params[1];
          dyn.dynasty_name = params[1];
        }
        return { rows: [dyn] };
      }

      return { rows: [] };
    },
  };
  repository.transaction = async (work) => work(repository);
  return repository;
}

test('getHouseProfile returns canonical House identity and lineage', async () => {
  const db = createMockDb();
  const res = await getHouseProfile(db, 'HSE-H0044', 'H-0044');

  assert.equal(res.ok, true);
  assert.equal(res.houseProfile.identity.name, 'House Vance');
  assert.equal(res.houseProfile.currentHuman.displayName, 'Amara Vance');
  assert.equal(res.houseProfile.settlementProfile, null);
});

test('updateHouseProfile updates canonical House identity', async () => {
  const db = createMockDb();
  const mottoRes = await updateHouseProfile(db, 'HSE-H0044', { motto: 'Per Aspera Ad Astra', houseName: 'House Vance-Neo' });
  assert.equal(mottoRes.ok, true);
  assert.equal(mottoRes.motto, 'Per Aspera Ad Astra');
  assert.equal(mottoRes.houseName, 'House Vance-Neo');
});
