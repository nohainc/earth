import test from 'node:test';
import assert from 'node:assert/strict';
import { PostgresRepository } from '../cloudflare/src/repository.ts';
import {
  listCities,
  listCorporations,
  cityQualification,
  changeCityResidency,
  changeCorporationMembership,
  setCorporationTaxCharter,
  adoptCityForCorporation,
} from '../cloudflare/src/institutions-postgres.ts';

class MockDbClient {
  constructor(handlers = {}) {
    this.handlers = handlers;
    this.calls = [];
  }

  async query(sql, params = []) {
    this.calls.push({ sql, params });
    for (const [pattern, handler] of Object.entries(this.handlers)) {
      if (sql.includes(pattern)) {
        return typeof handler === 'function' ? handler(sql, params) : handler;
      }
    }
    return { rows: [], rowCount: 0 };
  }
}

test('listCities and listCorporations return rows from database', async () => {
  const client = new MockDbClient({
    'FROM cities': (sql) => sql.includes('FROM corporations')
      ? { rows: [{ id: 'CORP-01', name: 'Aether Dynamics' }], rowCount: 1 }
      : { rows: [{ id: 'CITY-01', name: 'New Kyoto' }], rowCount: 1 },
    'FROM corporations': { rows: [{ id: 'CORP-01', name: 'Aether Dynamics' }], rowCount: 1 },
  });
  const repo = new PostgresRepository(client);

  const cities = await listCities(repo);
  assert.equal(cities.cities.length, 1);
  assert.equal(cities.cities[0].name, 'New Kyoto');

  const corps = await listCorporations(repo);
  assert.equal(corps.corporations.length, 1);
  assert.equal(corps.corporations[0].name, 'Aether Dynamics');
});

test('cityQualification evaluates active population, housing, and health capacity', async () => {
  const client = new MockDbClient({
    'SELECT * FROM cities WHERE id = $1': {
      rows: [{
        id: 'CITY-01',
        institution_id: 'CITY-01',
        residents: 15,
        housing_capacity: 20,
        energy_capacity: 25,
        connectivity_capacity: 20,
        health_capacity: 60,
        treasury: 1000,
      }],
      rowCount: 1,
    },
    'SELECT id FROM institution_roles WHERE institution_id = $1': {
      rows: [{ id: 'ROLE-01' }],
      rowCount: 1,
    },
  });
  const repo = new PostgresRepository(client);

  const qual = await cityQualification(repo, 'CITY-01');
  assert.equal(qual.ok, true);
  assert.equal(qual.qualified, true);
});

test('changeCityResidency adds or removes human residency', async () => {
  const client = new MockDbClient({
    'SELECT id, corporation_id FROM cities WHERE id = $1 FOR UPDATE': {
      rows: [{ id: 'CITY-01', corporation_id: null }],
      rowCount: 1,
    },
    'SELECT action, game_day FROM membership_events': {
      rows: [],
      rowCount: 0,
    },
    'SELECT id FROM humans WHERE id = $1': {
      rows: [{ id: 'H-01' }],
      rowCount: 1,
    },
    'SELECT city_id, corporation_id FROM memberships': {
      rows: [{ city_id: null, corporation_id: null }],
      rowCount: 1,
    },
    'SELECT COALESCE(MAX(game_day), 1) AS game_day FROM world_state': {
      rows: [{ game_day: 100 }],
      rowCount: 1,
    },
    'INSERT INTO memberships': { rows: [], rowCount: 1 },
    'UPDATE cities SET residents': { rows: [], rowCount: 1 },
    'INSERT INTO membership_events': { rows: [], rowCount: 1 },
    'INSERT INTO notifications': { rows: [], rowCount: 1 },
    'SELECT * FROM memberships WHERE human_id = $1': {
      rows: [{ human_id: 'H-01', city_id: 'CITY-01' }],
      rowCount: 1,
    },
  });
  const repo = new PostgresRepository(client);

  const joinResult = await changeCityResidency(repo, {
    humanId: 'H-01',
    cityId: 'CITY-01',
    action: 'join',
    correlationId: 'join-city-01',
  });
  assert.equal(joinResult.ok, true);
});

test('moving cities records departure from the previous city', async () => {
  const client = new MockDbClient({
    'SELECT id, corporation_id FROM cities WHERE id = $1 FOR UPDATE': {
      rows: [{ id: 'CITY-02', corporation_id: 'CORP-01' }], rowCount: 1,
    },
    'SELECT action, game_day FROM membership_events': { rows: [], rowCount: 0 },
    'SELECT id FROM humans WHERE id = $1': { rows: [{ id: 'H-01' }], rowCount: 1 },
    'SELECT city_id, corporation_id FROM memberships': {
      rows: [{ city_id: 'CITY-01', corporation_id: 'CORP-01' }], rowCount: 1,
    },
    'SELECT COALESCE(MAX(game_day), 1) AS game_day': { rows: [{ game_day: 100 }], rowCount: 1 },
    'INSERT INTO memberships': { rows: [], rowCount: 1 },
    'UPDATE cities SET residents': { rows: [], rowCount: 1 },
    'INSERT INTO membership_events': { rows: [], rowCount: 1 },
    'INSERT INTO notifications': { rows: [], rowCount: 1 },
    'SELECT * FROM memberships WHERE human_id = $1': {
      rows: [{ human_id: 'H-01', city_id: 'CITY-02', corporation_id: 'CORP-01' }], rowCount: 1,
    },
  });
  const result = await changeCityResidency(new PostgresRepository(client), {
    humanId: 'H-01', cityId: 'CITY-02', action: 'join', correlationId: 'move-city-01',
  });
  assert.equal(result.ok, true);
  assert.ok(client.calls.some((call) => call.params.includes('CITY-01') && call.sql.includes('city_transfer')));
});

test('corporation members cannot retain a corporation while moving outside its city network', async () => {
  const client = new MockDbClient({
    'SELECT id, corporation_id FROM cities': { rows: [{ id: 'CITY-03', corporation_id: null }], rowCount: 1 },
    'SELECT action, game_day FROM membership_events': { rows: [], rowCount: 0 },
    'SELECT id FROM humans': { rows: [{ id: 'H-01' }], rowCount: 1 },
    'SELECT city_id, corporation_id FROM memberships': { rows: [{ city_id: 'CITY-01', corporation_id: 'CORP-01' }], rowCount: 1 },
  });
  await assert.rejects(
    () => changeCityResidency(new PostgresRepository(client), {
      humanId: 'H-01', cityId: 'CITY-03', action: 'join', correlationId: 'move-city-03',
    }),
    /only to a city in their corporation network/,
  );
});

test('leaving a corporation also clears the affiliated city', async () => {
  const client = new MockDbClient({
    'SELECT id, capital_city_id, admission_policy FROM corporations': { rows: [{ id: 'CORP-01', capital_city_id: 'CITY-01', admission_policy: 'open' }], rowCount: 1 },
    "SELECT id FROM humans": { rows: [{ id: 'H-01' }], rowCount: 1 },
    'SELECT corporation_id, city_id FROM memberships': { rows: [{ corporation_id: 'CORP-01', city_id: 'CITY-01' }], rowCount: 1 },
    'SELECT COALESCE(MAX(game_day), 1) AS game_day': { rows: [{ game_day: 100 }], rowCount: 1 },
    'UPDATE memberships SET corporation_id = NULL, city_id = NULL': { rows: [], rowCount: 1 },
    'UPDATE corporations SET member_count': { rows: [], rowCount: 1 },
    'UPDATE cities SET residents': { rows: [], rowCount: 1 },
    'SELECT * FROM memberships WHERE human_id = $1': { rows: [{ human_id: 'H-01', corporation_id: null, city_id: null }], rowCount: 1 },
  });
  const result = await changeCorporationMembership(new PostgresRepository(client), {
    humanId: 'H-01', corporationId: 'CORP-01', action: 'leave',
  });
  assert.equal(result.ok, true);
  assert.ok(client.calls.some((call) => call.sql.includes('city_id = NULL')));
});

test('corporation executives can update the corporation tax charter', async () => {
  const client = new MockDbClient({
    'SELECT role_assignments.id': { rows: [{ id: 'ROLE-ASSIGNMENT-01' }], rowCount: 1 },
    'SELECT id FROM corporations': { rows: [{ id: 'CORP-01' }], rowCount: 1 },
    'SELECT game_day FROM world_state': { rows: [{ game_day: 100 }], rowCount: 1 },
    'UPDATE institutions SET charter_rules': { rows: [], rowCount: 1 },
    'INSERT INTO world_events': { rows: [], rowCount: 1 },
  });
  const result = await setCorporationTaxCharter(new PostgresRepository(client), {
    humanId: 'H-01', corporationId: 'CORP-01', incomeTaxBps: 500,
    salesTaxBps: 250, corporateTaxBps: 750, propertyTaxBps: 100,
    correlationId: 'corp-charter-01',
  });
  assert.equal(result.ok, true);
  assert.equal(result.charter.corporateTaxBps, 750);
});

test('corporation executives can adopt an unclaimed city', async () => {
  const client = new MockDbClient({
    'SELECT role_assignments.id': { rows: [{ id: 'ROLE-ASSIGNMENT-01' }], rowCount: 1 },
    'SELECT id FROM corporations': { rows: [{ id: 'CORP-01' }], rowCount: 1 },
    'SELECT cities.id, cities.corporation_id, corporations.admission_policy FROM cities': { rows: [{ id: 'CITY-02', corporation_id: null }], rowCount: 1 },
    'SELECT human_id FROM memberships WHERE city_id': { rows: [], rowCount: 0 },
    'SELECT game_day FROM world_state': { rows: [{ game_day: 100 }], rowCount: 1 },
    'UPDATE cities SET corporation_id': { rows: [], rowCount: 1 },
    'UPDATE memberships SET corporation_id': { rows: [], rowCount: 1 },
    'UPDATE corporations SET member_count': { rows: [], rowCount: 1 },
    'UPDATE cities SET residents': { rows: [], rowCount: 1 },
    'INSERT INTO world_events': { rows: [], rowCount: 1 },
    'SELECT * FROM memberships WHERE human_id = $1': { rows: [{ human_id: 'H-01', corporation_id: 'CORP-01', city_id: 'CITY-02' }], rowCount: 1 },
  });
  const result = await adoptCityForCorporation(new PostgresRepository(client), {
    humanId: 'H-01', corporationId: 'CORP-01', cityId: 'CITY-02',
  });
  assert.equal(result.ok, true);
  assert.equal(result.cityId, 'CITY-02');
});
