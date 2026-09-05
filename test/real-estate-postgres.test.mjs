import test from 'node:test';
import assert from 'node:assert/strict';
import { PostgresRepository } from '../cloudflare/src/repository.ts';
import {
  purchasePrivatePlotAndConstruct,
  upgradeBuilding,
  setBuildingOperatingPolicy,
  setBuildingAutoRepair,
  repairBuilding,
  demolishBuilding,
  getCityDistrictZoning,
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

test('getCityDistrictZoning calculates total slots, occupancy, and 30% civic quota', async () => {
  const client = new MockDbClient((sql) => {
    if (sql.includes('FROM cities')) return { rows: [{ id: 'CITY-0084', name: 'New Carthage' }], rowCount: 1 };
    if (sql.includes('FROM memberships')) return { rows: [{ count: '15' }], rowCount: 1 };
    if (sql.includes('FROM buildings')) {
      return {
        rows: [
          { slot_footprint: 1, ownership_class: 'private' },
          { slot_footprint: 2, ownership_class: 'private' },
          { slot_footprint: 3, ownership_class: 'civic' },
        ],
        rowCount: 3,
      };
    }
    return { rows: [], rowCount: 0 };
  });
  const repo = new PostgresRepository(client);

  const res = await getCityDistrictZoning(repo, 'CITY-0084');
  assert.equal(res.cityId, 'CITY-0084');
  assert.equal(res.population, 15);
  // 1 District Module = 120 total slots (100 private, 20 civic)
  assert.equal(res.totalSlots, 120);
  assert.equal(res.civicReservedSlots, 20);
  assert.equal(res.usedPrivateSlots, 3);
  assert.equal(res.usedCivicSlots, 3);
  assert.equal(res.availablePrivateSlots, 97); // (120 - 20) - 3 = 97
});

test('purchasePrivatePlotAndConstruct verifies zoning slots, balances, and provisions building', async () => {
  const client = new MockDbClient((sql) => {
    if (sql.includes('SELECT details FROM world_events')) return { rows: [], rowCount: 0 };
    if (sql.includes('SELECT game_day')) return { rows: [{ game_day: 184 }], rowCount: 1 };
    if (sql.includes('FROM cities')) return { rows: [{ id: 'CITY-0084', name: 'New Carthage' }], rowCount: 1 };
    if (sql.includes('FROM memberships')) return { rows: [{ city_id: 'CITY-0084', count: '15' }], rowCount: 1 };
    if (sql.includes('FROM buildings WHERE city_id')) return { rows: [], rowCount: 0 };
    if (sql.includes('FROM account_balances')) return { rows: [{ account_id: 'account-human-H-001', balance: '25000' }], rowCount: 1 };
    if (sql.includes('FROM resource_balances')) return { rows: [{ amount: '500' }], rowCount: 1 };
    if (sql.includes('UPDATE account_balances')) return { rows: [{ balance: '16500' }], rowCount: 1 };
    if (sql.includes('UPDATE resource_balances')) return { rows: [{ amount: '380' }], rowCount: 1 };
    if (sql.includes('SELECT * FROM buildings WHERE id = $1')) return { rows: [{ id: 'BLD-TEST', name: 'Bistro Stellar' }], rowCount: 1 };
    return { rows: [{ balance: '16500' }], rowCount: 1 };
  });
  const repo = new PostgresRepository(client);

  const res = await purchasePrivatePlotAndConstruct(repo, {
    ownerId: 'H-001',
    cityId: 'CITY-0084',
    buildingType: 'restaurant',
    name: 'Bistro Stellar',
    correlationId: 'test-purchase-1',
  });

  assert.equal(res.ok, true);
  assert.equal(res.building.name, 'Bistro Stellar');
});

test('upgradeBuilding advances tier, increases revenue and condition', async () => {
  const client = new MockDbClient((sql) => {
    if (sql.includes('SELECT details FROM world_events')) return { rows: [], rowCount: 0 };
    if (sql.includes('SELECT game_day')) return { rows: [{ game_day: 184 }], rowCount: 1 };
    if (sql.includes('FOR UPDATE') && sql.includes('FROM buildings')) {
      return {
        rows: [
          {
            id: 'BLD-01',
            owner_id: 'H-001',
            city_id: 'CITY-0084',
            tier: 1,
            building_type: 'restaurant',
            resource_output_amount: '620',
            daily_operating_credits: '60',
            status: 'active',
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
            resource_output_amount: '806',
            daily_operating_credits: '75',
            condition: '100',
          },
        ],
        rowCount: 1,
      };
    }
    if (sql.includes('FROM account_balances')) return { rows: [{ account_id: 'account-human-H-001', balance: '20000' }], rowCount: 1 };
    if (sql.includes('FROM resource_balances')) return { rows: [{ amount: '100' }], rowCount: 1 };
    if (sql.includes('UPDATE account_balances')) return { rows: [{ balance: '10400' }], rowCount: 1 };
    if (sql.includes('UPDATE resource_balances')) return { rows: [{ amount: '50' }], rowCount: 1 };
    return { rows: [{ balance: '10400' }], rowCount: 1 };
  });
  const repo = new PostgresRepository(client);

  const res = await upgradeBuilding(repo, {
    humanId: 'H-001',
    buildingId: 'BLD-01',
    correlationId: 'test-upgrade-1',
  });

  assert.equal(res.ok, true);
  assert.equal(res.building.tier, 2);
});

test('setBuildingOperatingPolicy updates policy on facility', async () => {
  const client = new MockDbClient((sql) => {
    if (sql.includes('FROM buildings WHERE id = $1')) {
      return { rows: [{ id: 'BLD-01', owner_id: 'H-001' }], rowCount: 1 };
    }
    return { rows: [], rowCount: 1 };
  });
  const repo = new PostgresRepository(client);

  const res = await setBuildingOperatingPolicy(repo, {
    humanId: 'H-001',
    buildingId: 'BLD-01',
    policy: 'overclock',
  });

  assert.equal(res.ok, true);
  assert.equal(res.policy, 'overclock');
});

test('repairBuilding consumes components and restores condition to 100%', async () => {
  const client = new MockDbClient((sql) => {
    if (sql.includes('earth_mutate_resource_balance')) {
      return { rows: [{ status: 'success', ledger_id: 'LED-RESOURCE', owner_id: 'H-001', resource: 'components', delta: -4, balance_after: 46, already_processed: false }], rowCount: 1 };
    }
    if (sql.includes('FROM buildings WHERE id = $1')) {
      return { rows: [{ id: 'BLD-01', owner_id: 'H-001', condition: '60', tier: 2 }], rowCount: 1 };
    }
    if (sql.includes('FROM resource_balances')) {
      return { rows: [{ amount: '50' }], rowCount: 1 };
    }
    return { rows: [], rowCount: 1 };
  });
  const repo = new PostgresRepository(client);

  const res = await repairBuilding(repo, {
    humanId: 'H-001',
    buildingId: 'BLD-01',
  });

  assert.equal(res.ok, true);
  assert.equal(res.condition, 100);
});

test('demolishBuilding marks facility closed and recycles materials to owner', async () => {
  const client = new MockDbClient((sql) => {
    if (sql.includes('earth_mutate_resource_balance')) {
      return { rows: [{ status: 'success', ledger_id: 'LED-RESOURCE', owner_id: 'H-001', resource: 'material', delta: 30, balance_after: 80, already_processed: false }], rowCount: 1 };
    }
    if (sql.includes('FROM buildings WHERE id = $1')) {
      return { rows: [{ id: 'BLD-01', owner_id: 'H-001', building_type: 'restaurant', slot_footprint: 1 }], rowCount: 1 };
    }
    return { rows: [], rowCount: 1 };
  });
  const repo = new PostgresRepository(client);

  const res = await demolishBuilding(repo, {
    humanId: 'H-001',
    buildingId: 'BLD-01',
  });

  assert.equal(res.ok, true);
  assert.equal(res.freedSlots, 1);
  assert.ok(res.recycledMaterials > 0);
});

test('contributeCorporateResearch contributes credits and compute to corporate pool', async () => {
  const client = new MockDbClient((sql) => {
    if (sql.includes('SELECT details FROM world_events')) return { rows: [], rowCount: 0 };
    if (sql.includes('SELECT game_day')) return { rows: [{ game_day: 184 }], rowCount: 1 };
    if (sql.includes('FROM memberships')) return { rows: [{ corporation_id: 'CORP-001' }], rowCount: 1 };
    if (sql.includes('FROM corporate_research_pools')) {
      return {
        rows: [
          {
            id: 'CRP-01',
            corporation_id: 'CORP-001',
            name: 'Automated Assembly 2.0',
            target_compute: '5000',
            target_credits: '25000',
            contributed_compute: '1200',
            contributed_credits: '8500',
            status: 'active',
          },
        ],
        rowCount: 1,
      };
    }
    if (sql.includes('FROM account_balances')) return { rows: [{ account_id: 'account-human-H-001', balance: '15000' }], rowCount: 1 };
    if (sql.includes('FROM resource_balances')) return { rows: [{ amount: '500' }], rowCount: 1 };
    if (sql.includes('UPDATE account_balances')) return { rows: [{ balance: '13000' }], rowCount: 1 };
    if (sql.includes('UPDATE resource_balances')) return { rows: [{ amount: '400' }], rowCount: 1 };
    if (sql.includes('SELECT * FROM corporate_research_pools WHERE id = $1')) {
      return {
        rows: [
          {
            id: 'CRP-01',
            contributed_compute: '1300',
            contributed_credits: '10500',
            status: 'active',
          },
        ],
        rowCount: 1,
      };
    }
    return { rows: [{ balance: '13000' }], rowCount: 1 };
  });
  const repo = new PostgresRepository(client);

  const res = await contributeCorporateResearch(repo, {
    humanId: 'H-001',
    poolId: 'CRP-01',
    credits: 2000,
    compute: 100,
    correlationId: 'test-corp-rd-1',
  });

  assert.equal(res.ok, true);
  assert.equal(res.pool.status, 'active');
});

test('setBuildingAutoRepair updates auto repair toggle on facility', async () => {
  const updates = [];
  const client = new MockDbClient((sql, params) => {
    if (sql.includes('SELECT id, owner_id FROM buildings WHERE id = $1')) {
      return { rows: [{ id: 'BLD-TEST', owner_id: 'H-001' }], rowCount: 1 };
    }
    if (sql.includes('UPDATE buildings SET auto_repair_enabled')) {
      updates.push(params);
      return { rows: [], rowCount: 1 };
    }
    return { rows: [], rowCount: 0 };
  });
  const repo = new PostgresRepository(client);

  const res = await setBuildingAutoRepair(repo, {
    humanId: 'H-001',
    buildingId: 'BLD-TEST',
    autoRepairEnabled: false,
  });

  assert.equal(res.ok, true);
  assert.equal(res.autoRepairEnabled, false);
  assert.equal(updates.length, 1);
  assert.equal(updates[0][0], false);
  assert.equal(updates[0][1], 'BLD-TEST');
});
