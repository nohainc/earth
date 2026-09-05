import test from 'node:test';
import assert from 'node:assert/strict';
import { PostgresRepository } from '../cloudflare/src/repository.ts';
import { listCities, cityQualification, changeCityResidency } from '../cloudflare/src/institutions-postgres.ts';

class Db {
  constructor(handlers) { this.handlers = handlers; this.calls = []; }
  async query(sql, params = []) {
    this.calls.push({ sql, params });
    for (const [key, value] of Object.entries(this.handlers)) if (sql.includes(key)) {
      return typeof value === 'function' ? value(sql, params) : value;
    }
    return { rows: [], rowCount: 0 };
  }
}

test('City API lists city capacity with corporation names', async () => {
  const db = new Db({'FROM cities': { rows: [{ id: 'CITY-01', name: 'New Kyoto', corporation_name: 'Aether Dynamics' }], rowCount: 1 }});
  const result = await listCities(new PostgresRepository(db));
  assert.deepEqual(result.cities[0], { id: 'CITY-01', name: 'New Kyoto', corporation_name: 'Aether Dynamics' });
});

test('City API qualification reports every capacity and governance requirement', async () => {
  const db = new Db({
    'SELECT * FROM cities WHERE id': { rows: [{ id: 'CITY-01', institution_id: 'CITY-01', residents: 20, housing_capacity: 20, energy_capacity: 25, connectivity_capacity: 20, health_capacity: 60, treasury: 100 }], rowCount: 1 },
    'FROM governance_rules': { rows: [{ id: 'RULE-01' }], rowCount: 1 },
  });
  const result = await cityQualification(new PostgresRepository(db), 'CITY-01');
  assert.equal(result.qualified, true);
  assert.deepEqual(result.requirements, { activePopulation: true, housing: true, energy: true, connectivity: true, health: true, treasury: true, governance: true });
});

test('City API residency is idempotent for a repeated correlation id', async () => {
  const db = new Db({
    'SELECT id, corporation_id FROM cities': { rows: [{ id: 'CITY-01', corporation_id: null }], rowCount: 1 },
    'SELECT action, game_day FROM membership_events': { rows: [{ action: 'joined', game_day: 44 }], rowCount: 1 },
    'SELECT * FROM memberships WHERE human_id': { rows: [{ human_id: 'H-01', city_id: 'CITY-01' }], rowCount: 1 },
  });
  const result = await changeCityResidency(new PostgresRepository(db), { humanId: 'H-01', cityId: 'CITY-01', action: 'join', correlationId: 'city-replay-44' });
  assert.equal(result.alreadyProcessed, true);
  assert.equal(result.residency, 'resident');
  assert.equal(result.gameDay, 44);
});
