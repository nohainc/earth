import test from 'node:test';
import assert from 'node:assert/strict';
import { PostgresRepository } from '../cloudflare/src/repository.ts';
import {
  purchasePrivatePlotAndConstruct,
  upgradeBuilding,
  setBuildingOperatingPolicy,
  repairBuilding,
  investInPublicBuilding,
  demolishBuilding,
  getCityDistrictZoning,
  contributeCorporateResearch,
  acquireBuildingPatentLicense,
  renewBuildingPatentLicense,
  checkBuildingPatentAccess,
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
  // 8 + floor(15 / 5) = 11 total slots
  assert.equal(res.totalSlots, 11);
  // ceil(11 * 0.30) = 4 civic reserved slots
  assert.equal(res.civicReservedSlots, 4);
  assert.equal(res.usedPrivateSlots, 3);
  assert.equal(res.usedCivicSlots, 3);
  assert.equal(res.availablePrivateSlots, 4); // (11 - 4) - 3 = 4
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
            base_revenue_crd: '620',
            resource_output_amount: '620',
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
            base_revenue_crd: '806',
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

test('investInPublicBuilding transfers credits and issues crowdfunding shares', async () => {
  const client = new MockDbClient((sql) => {
    if (sql.includes('SELECT details FROM world_events')) return { rows: [], rowCount: 0 };
    if (sql.includes('SELECT game_day')) return { rows: [{ game_day: 184 }], rowCount: 1 };
    if (sql.includes('FROM buildings WHERE id = $1')) {
      return { rows: [{ id: 'BLD-MALL', city_id: 'CITY-0084', ownership_class: 'public_investment', name: 'Mega-Mall' }], rowCount: 1 };
    }
    if (sql.includes('FROM account_balances')) return { rows: [{ account_id: 'account-human-H-001', balance: '10000' }], rowCount: 1 };
    if (sql.includes('transfer_credits')) return { rows: [{ success: true, debit_balance: '7500', credit_balance: '12500' }], rowCount: 1 };
    if (sql.includes('SELECT * FROM building_investment_shares')) {
      return { rows: [{ building_id: 'BLD-MALL', investor_id: 'H-001', shares_owned: 5, invested_credits: '2500' }], rowCount: 1 };
    }
    return { rows: [{ balance: '7500', success: true }], rowCount: 1 };
  });
  const repo = new PostgresRepository(client);

  const res = await investInPublicBuilding(repo, {
    humanId: 'H-001',
    buildingId: 'BLD-MALL',
    sharesCount: 5,
    correlationId: 'test-invest-1',
  });

  assert.equal(res.ok, true);
  assert.equal(res.shares.shares_owned, 5);
});

test('demolishBuilding marks facility closed and recycles materials to owner', async () => {
  const client = new MockDbClient((sql) => {
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

test('checkBuildingPatentAccess allows corporate members and licensed holders, blocks unlicensed', async () => {
  const reqPatent = {
    patentId: 'PAT-DAT-02',
    patentName: 'Photonic Neural Architecture',
    owningCorporationId: 'CORP-001',
    owningCorporationName: 'Aetheria Systems',
    privateLicenseCostCrd: 12000,
    privateDailyRoyaltyCrd: 150,
    cityCivicLicenseCostCrd: 45000,
    termDays: 30,
    technologyId: 'tech-photonic',
  };

  // Case 1: Corporate Member has access
  const memberClient = new MockDbClient((sql, params) => {
    if (sql.includes('FROM memberships WHERE human_id') && params[1] === 'CORP-001') {
      return { rows: [{ corporation_id: 'CORP-001' }], rowCount: 1 };
    }
    return { rows: [], rowCount: 0 };
  });
  const memberRepo = new PostgresRepository(memberClient);
  const memberAccess = await checkBuildingPatentAccess(memberRepo, {
    humanId: 'H-001',
    cityId: 'CITY-0084',
    requiredPatent: reqPatent,
  });
  assert.equal(memberAccess.hasAccess, true);
  assert.equal(memberAccess.accessType, 'corporate_member');

  // Case 2: Non-member without license is blocked
  const unlicensedClient = new MockDbClient((sql, params) => {
    if (sql.includes('FROM memberships WHERE human_id') && params[1] === 'CORP-001') {
      return { rows: [], rowCount: 0 };
    }
    if (sql.includes('FROM building_patent_licenses')) return { rows: [], rowCount: 0 };
    return { rows: [], rowCount: 0 };
  });
  const unlicensedRepo = new PostgresRepository(unlicensedClient);
  const unlicAccess = await checkBuildingPatentAccess(unlicensedRepo, {
    humanId: 'H-002',
    cityId: 'CITY-0084',
    requiredPatent: reqPatent,
  });
  assert.equal(unlicAccess.hasAccess, false);
  assert.equal(unlicAccess.accessType, 'none');

  // Case 3: Non-member with active private license has access
  const licensedClient = new MockDbClient((sql, params) => {
    if (sql.includes('FROM memberships WHERE human_id') && params[1] === 'CORP-001') {
      return { rows: [], rowCount: 0 };
    }
    if (sql.includes('FROM building_patent_licenses WHERE licensee_id')) {
      return { rows: [{ id: 'LIC-01', patent_id: 'PAT-DAT-02', status: 'active' }], rowCount: 1 };
    }
    return { rows: [], rowCount: 0 };
  });
  const licensedRepo = new PostgresRepository(licensedClient);
  const licAccess = await checkBuildingPatentAccess(licensedRepo, {
    humanId: 'H-002',
    cityId: 'CITY-0084',
    requiredPatent: reqPatent,
  });
  assert.equal(licAccess.hasAccess, true);
  assert.equal(licAccess.accessType, 'private_building');
});

test('acquireBuildingPatentLicense purchases private license and transfers credits', async () => {
  const client = new MockDbClient((sql) => {
    if (sql.includes('SELECT details FROM world_events')) return { rows: [], rowCount: 0 };
    if (sql.includes('SELECT reason_id FROM ledger_entries')) return { rows: [], rowCount: 0 };
    if (sql.includes('SELECT game_day')) return { rows: [{ game_day: 184 }], rowCount: 1 };
    if (sql.includes('FROM account_balances')) return { rows: [{ account_id: 'acc-h-1', balance: '50000' }], rowCount: 1 };
    if (sql.includes('UPDATE account_balances')) return { rows: [{ balance: '38000' }], rowCount: 1 };
    if (sql.includes('SELECT * FROM building_patent_licenses WHERE id = $1')) {
      return {
        rows: [
          {
            id: 'LIC-TEST-01',
            patent_id: 'PAT-DAT-02',
            license_type: 'private_building',
            licensee_id: 'H-001',
            status: 'active',
          },
        ],
        rowCount: 1,
      };
    }
    return { rows: [{ balance: '38000' }], rowCount: 1 };
  });
  const repo = new PostgresRepository(client);

  const res = await acquireBuildingPatentLicense(repo, {
    humanId: 'H-001',
    patentId: 'PAT-DAT-02',
    licenseType: 'private_building',
    correlationId: 'test-acq-lic-1',
  });

  assert.equal(res.ok, true);
  assert.equal(res.license.status, 'active');
});

test('renewBuildingPatentLicense extends expiry and transfers renewal fee', async () => {
  const client = new MockDbClient((sql) => {
    if (sql.includes('SELECT details FROM world_events')) return { rows: [], rowCount: 0 };
    if (sql.includes('SELECT reason_id FROM ledger_entries')) return { rows: [], rowCount: 0 };
    if (sql.includes('SELECT game_day')) return { rows: [{ game_day: 184 }], rowCount: 1 };
    if (sql.includes('FROM building_patent_licenses WHERE id = $1 FOR UPDATE')) {
      return {
        rows: [
          {
            id: 'LIC-TEST-01',
            patent_id: 'PAT-DAT-02',
            license_type: 'private_building',
            licensee_id: 'H-001',
            licensor_corporation_id: 'CORP-001',
            expiry_game_day: '184',
          },
        ],
        rowCount: 1,
      };
    }
    if (sql.includes('FROM account_balances')) return { rows: [{ account_id: 'acc-h-1', balance: '50000' }], rowCount: 1 };
    if (sql.includes('UPDATE account_balances')) return { rows: [{ balance: '38000' }], rowCount: 1 };
    if (sql.includes('SELECT * FROM building_patent_licenses WHERE id = $1')) {
      return {
        rows: [
          {
            id: 'LIC-TEST-01',
            patent_id: 'PAT-DAT-02',
            expiry_game_day: '214',
            status: 'active',
          },
        ],
        rowCount: 1,
      };
    }
    return { rows: [{ balance: '38000' }], rowCount: 1 };
  });
  const repo = new PostgresRepository(client);

  const res = await renewBuildingPatentLicense(repo, {
    humanId: 'H-001',
    licenseId: 'LIC-TEST-01',
    correlationId: 'test-renew-lic-1',
  });

  assert.equal(res.ok, true);
  assert.equal(res.license.expiry_game_day, '214');
  assert.equal(res.license.status, 'active');
});

