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
      if (normalized.includes('FROM humans h JOIN house_affiliations')) return { rows: [{ corporation_id: 'CORP-001' }], rowCount: 1 };
      if (normalized.includes('FROM corporation_research_projects p') && normalized.includes('p.correlation_id = $2')) return { rows: [], rowCount: 0 };
      if (normalized.includes('FROM corporation_research_projects p') && normalized.includes('p.status = \'completed\'')) return { rows: [{ tier: '1' }], rowCount: 1 };
      if (normalized.includes('FROM building_catalog WHERE family_code = $1 AND tier = $2')) {
        return { rows: [{ id: 'private-estate-plot-t1', tier: 1, construction_credit_units: '1000', construction_minutes: 1440, slot_footprint: 2, ownership_scope: 'PRIVATE' }], rowCount: 1 };
      }
      if (normalized.includes('FROM building_catalog WHERE id = $1 AND family_code = $2')) return { rows: [{ id: 'private-estate-plot-t2', tier: 2, construction_credit_units: '1700', construction_minutes: 2880, slot_footprint: 2, ownership_scope: 'PRIVATE' }], rowCount: 1 };
      if (normalized.includes("status IN ('QUEUED','ACTIVE','COMPLETED')")) return { rows: [], rowCount: 0 };
      if (normalized.includes('FROM earth_get_current_game_time()')) return { rows: [{ game_day: 1, game_minute: 0 }], rowCount: 1 };
      if (normalized.includes('FROM economic_accounts payer')) return { rows: [{ debit_account_id: '101', research_account_id: '202' }], rowCount: 1 };
      if (normalized.includes('FROM owner_registry WHERE id = $1')) return { rows: [{ economic_id: '3001' }], rowCount: 1 };
      if (normalized.includes('FROM account_balances')) return { rows: [{ account_id: 'account-human-H-001', balance: '100000' }], rowCount: 1 };
      if (normalized.includes('FROM institution_budget_lines')) return { rows: [{ id: 'BUDGET-001' }], rowCount: 1 };
      if (normalized.includes('earth_post_transaction')) throw stopAfterCatalogInsert;
      return { rows: [], rowCount: 0 };
    },
  };

  await assert.rejects(
    () => startCorporationBuildingResearch(new PostgresRepository(client), {
      humanId: 'H-001', buildingType: 'private-estate-plot', correlationId: 'research-private-tier-cast',
    }),
    stopAfterCatalogInsert,
  );

  assert.ok(!calls.some(({ sql }) => sql.includes('INSERT INTO building_catalog')));
  assert.ok(calls.some(({ sql }) => sql.includes('earth_post_transaction')));
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
