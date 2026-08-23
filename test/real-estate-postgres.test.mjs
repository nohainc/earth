import test from 'node:test';
import assert from 'node:assert/strict';
import { PostgresRepository } from '../cloudflare/src/repository.ts';
import {
  purchaseBuilding,
  upgradeBuilding,
  registerMunicipalLabor,
  withdrawMunicipalLabor,
  contributeCorporateResearch,
} from '../cloudflare/src/real-estate-postgres.ts';

class MockDbClient {
  constructor(handler) {
    this.handler = handler;
    this.calls = [];
  }
  async query(sql, params = []) {
    this.calls.push({ sql, params });
    const normalized = sql.replace(/\s+/g, ' ').trim();
    return this.handler(normalized, params);
  }
}

test('purchaseBuilding verifies balances and provisions new building record', async () => {
  const client = new MockDbClient((sql) => {
    if (sql.includes('SELECT details FROM world_events')) return { rows: [], rowCount: 0 };
    if (sql.includes('SELECT game_day')) return { rows: [{ game_day: 184 }], rowCount: 1 };
    if (sql.includes('FROM account_balances')) return { rows: [{ account_id: 'account-human-H-001', balance: '25000' }], rowCount: 1 };
    if (sql.includes('FROM resource_balances')) return { rows: [{ amount: '500' }], rowCount: 1 };
    if (sql.includes('UPDATE account_balances')) return { rows: [{ balance: '16500' }], rowCount: 1 };
    if (sql.includes('UPDATE resource_balances')) return { rows: [{ amount: '380' }], rowCount: 1 };
    if (sql.includes('SELECT * FROM buildings WHERE id = $1')) return { rows: [{ id: 'BLD-TEST', name: 'Bistro Stellar' }], rowCount: 1 };
    return { rows: [{ balance: '16500' }], rowCount: 1 };
  });
  const repo = new PostgresRepository(client);

  const res = await purchaseBuilding(repo, {
    ownerId: 'H-001',
    cityId: 'CITY-0084',
    buildingType: 'restaurant',
    name: 'Bistro Stellar',
    correlationId: 'test-purchase-1',
  });

  assert.equal(res.ok, true);
  assert.equal(res.building.name, 'Bistro Stellar');
});

test('upgradeBuilding advances tier and charges upgrade cost', async () => {
  const client = new MockDbClient((sql) => {
    if (sql.includes('SELECT details FROM world_events')) return { rows: [], rowCount: 0 };
    if (sql.includes('SELECT game_day')) return { rows: [{ game_day: 184 }], rowCount: 1 };
    if (sql.includes('FOR UPDATE') && sql.includes('FROM buildings')) {
      return {
        rows: [
          {
            id: 'BLD-01',
            owner_id: 'H-001',
            tier: 1,
            building_type: 'restaurant',
            max_staff_slots: 4,
            base_revenue_crd: '450',
            condition: '90',
          },
        ],
        rowCount: 1,
      };
    }
    if (sql.includes('SELECT * FROM buildings WHERE id = $1')) {
      return {
        rows: [
          {
            id: 'BLD-01',
            owner_id: 'H-001',
            tier: 2,
            building_type: 'restaurant',
            max_staff_slots: 8,
            base_revenue_crd: '607.5',
            condition: '100',
          },
        ],
        rowCount: 1,
      };
    }
    if (sql.includes('FROM account_balances')) return { rows: [{ account_id: 'account-human-H-001', balance: '20000' }], rowCount: 1 };
    if (sql.includes('FROM resource_balances')) return { rows: [{ amount: '100' }], rowCount: 1 };
    if (sql.includes('UPDATE account_balances')) return { rows: [{ balance: '11000' }], rowCount: 1 };
    if (sql.includes('UPDATE resource_balances')) return { rows: [{ amount: '60' }], rowCount: 1 };
    return { rows: [{ balance: '11000' }], rowCount: 1 };
  });
  const repo = new PostgresRepository(client);

  const res = await upgradeBuilding(repo, {
    humanId: 'H-001',
    buildingId: 'BLD-01',
    correlationId: 'test-upgrade-1',
  });

  assert.equal(res.ok, true);
  assert.equal(res.building.tier, 2);
  assert.equal(res.building.max_staff_slots, 8);
});

test('registerMunicipalLabor registers idle machine into municipal pool', async () => {
  const client = new MockDbClient((sql) => {
    if (sql.includes('FROM machines WHERE id = $1')) {
      return {
        rows: [{ id: 'M-01', owner_id: 'H-001', status: 'active', machine_type: 'rig', condition: 95 }],
        rowCount: 1,
      };
    }
    if (sql.includes('FROM memberships')) return { rows: [{ city_id: 'CITY-0084' }], rowCount: 1 };
    if (sql.includes('FROM municipal_labor_pool')) return { rows: [], rowCount: 0 };
    return { rows: [], rowCount: 1 };
  });
  const repo = new PostgresRepository(client);

  const res = await registerMunicipalLabor(repo, {
    humanId: 'H-001',
    machineId: 'M-01',
  });

  assert.equal(res.ok, true);
});

test('withdrawMunicipalLabor sets pool record to inactive', async () => {
  const client = new MockDbClient((sql) => {
    if (sql.includes('FROM municipal_labor_pool')) {
      return {
        rows: [{ id: 'MLP-01', status: 'active' }],
        rowCount: 1,
      };
    }
    return { rows: [], rowCount: 1 };
  });
  const repo = new PostgresRepository(client);

  const res = await withdrawMunicipalLabor(repo, {
    humanId: 'H-001',
    machineId: 'M-01',
  });

  assert.equal(res.ok, true);
});

test('contributeCorporateResearch contributes credits and compute to corporate pool', async () => {
  const client = new MockDbClient((sql) => {
    if (sql.includes('SELECT details FROM world_events')) return { rows: [], rowCount: 0 };
    if (sql.includes('SELECT game_day')) return { rows: [{ game_day: 184 }], rowCount: 1 };
    if (sql.includes('FROM memberships')) return { rows: [{ corporation_id: 'CORP-001' }], rowCount: 1 };
    if (sql.includes('FROM corporate_research_pools')) {
      return {
        rows: [{ id: 'CRP-01', corporation_id: 'CORP-001', contributed_credits: '1000', target_credits: '50000', contributed_compute: '50', target_compute: '1000', status: 'active' }],
        rowCount: 1,
      };
    }
    if (sql.includes('FROM account_balances')) return { rows: [{ account_id: 'account-human-H-001', balance: '10000' }], rowCount: 1 };
    if (sql.includes('FROM resource_balances')) return { rows: [{ amount: '200' }], rowCount: 1 };
    if (sql.includes('UPDATE account_balances')) return { rows: [{ balance: '9500' }], rowCount: 1 };
    if (sql.includes('UPDATE resource_balances')) return { rows: [{ amount: '180' }], rowCount: 1 };
    return { rows: [{ balance: '9500' }], rowCount: 1 };
  });
  const repo = new PostgresRepository(client);

  const res = await contributeCorporateResearch(repo, {
    humanId: 'H-001',
    poolId: 'CRP-01',
    credits: 500,
    compute: 20,
    correlationId: 'test-rd-1',
  });

  assert.equal(res.ok, true);
  assert.equal(typeof res.pool, 'object');
});
