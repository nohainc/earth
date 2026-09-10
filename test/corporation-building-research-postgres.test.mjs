import test from 'node:test';
import assert from 'node:assert/strict';
import { PostgresRepository } from '../cloudflare/src/repository.ts';
import {
  advanceCorporationBuildingResearch,
  startCorporationBuildingResearch,
} from '../cloudflare/src/corporation-building-research-postgres.ts';

test('private-tier research casts the tier parameter before using it in catalog arithmetic', async () => {
  const calls = [];
  const stopAfterCatalogInsert = new Error('catalog insert captured');
  const client = {
    async query(sql, params = []) {
      calls.push({ sql, params });
      const normalized = sql.replace(/\s+/g, ' ').trim();
      if (normalized === 'BEGIN' || normalized === 'ROLLBACK') return { rows: [], rowCount: 0 };
      if (normalized.includes('FROM memberships')) return { rows: [{ corporation_id: 'CORP-001' }], rowCount: 1 };
      if (normalized.includes('FROM corporation_building_research_projects WHERE corporation_id = $1 AND correlation_id')) return { rows: [], rowCount: 0 };
      if (normalized.includes('FROM corporation_building_unlocks')) return { rows: [{ tier: '1' }], rowCount: 1 };
      if (normalized.includes('FROM building_catalog WHERE building_type = $1 AND tier = $2')) {
        return { rows: [{ id: 'private-estate-plot-t1', tier: 1, cost_credits: '1000', construction_days: 1, slot_footprint: 2, ownership_class: 'private' }], rowCount: 1 };
      }
      if (normalized.includes('FROM building_catalog WHERE id = $1')) return { rows: [], rowCount: 0 };
      if (normalized.includes('status IN (\'active\',\'paused\',\'completed\')')) return { rows: [], rowCount: 0 };
      if (normalized.includes('FROM earth_get_current_game_time()')) return { rows: [{ game_day: 1, game_minute: 0 }], rowCount: 1 };
      if (normalized.includes('FROM account_balances')) return { rows: [{ account_id: 'account-human-H-001', balance: '100000' }], rowCount: 1 };
      if (normalized.includes('INSERT INTO building_catalog')) throw stopAfterCatalogInsert;
      return { rows: [], rowCount: 0 };
    },
  };

  await assert.rejects(
    () => startCorporationBuildingResearch(new PostgresRepository(client), {
      humanId: 'H-001', buildingType: 'private-estate-plot', correlationId: 'research-private-tier-cast',
    }),
    stopAfterCatalogInsert,
  );

  const insert = calls.find(({ sql }) => sql.includes('INSERT INTO building_catalog'))?.sql;
  assert.match(insert, /slot_footprint \* \$2::integer/);
  assert.match(insert, /\$2::integer \* 1440/);
});

test('research progress is delegated to the database-owned clock procedure', async () => {
  const calls = [];
  const client = {
    async query(sql, params = []) {
      calls.push({ sql, params });
      return { rows: [{ completed: 2 }], rowCount: 1 };
    },
  };

  const completed = await advanceCorporationBuildingResearch(
    new PostgresRepository(client),
  );

  assert.equal(completed, 2);
  assert.deepEqual(calls, [{
    sql: 'SELECT earth_advance_corporation_building_research() AS completed',
    params: [],
  }]);
});
