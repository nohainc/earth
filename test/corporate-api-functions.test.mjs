import test from 'node:test';
import assert from 'node:assert/strict';
import { PostgresRepository } from '../cloudflare/src/repository.ts';
import { listCorporations, changeCorporationMembership, corporationQualification } from '../cloudflare/src/institutions-postgres.ts';

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

test('Corporate API list returns active corporations and safely parameterizes search', async () => {
  const db = new Db({
    'FROM corporations': { rows: [{ id: 'CORP-01', name: 'Aether Dynamics', charter_rules: null, member_count: 31 }], rowCount: 1 },
  });
  const result = await listCorporations(new PostgresRepository(db), 'Aether%_');
  assert.equal(result.corporations[0].name, 'Aether Dynamics');
  const query = db.calls.find((call) => call.sql.includes('FROM corporations'));
  assert.equal(query.params[0], '%Aether%');
});

test('Corporate API membership joins an open corporation and records the canonical membership', async () => {
  const db = new Db({
    'FROM corporations WHERE id': { rows: [{ id: 'CORP-01', capital_city_id: 'CITY-01', admission_policy: 'open' }], rowCount: 1 },
    'FROM humans WHERE id': { rows: [{ id: 'H-01' }], rowCount: 1 },
    'FROM memberships WHERE human_id': (sql) => sql.includes('FOR UPDATE')
      ? { rows: [{ corporation_id: null, city_id: null }], rowCount: 1 }
      : { rows: [{ human_id: 'H-01', corporation_id: 'CORP-01', city_id: 'CITY-01' }], rowCount: 1 },
    "SELECT game_day FROM world_state": { rows: [{ game_day: 42 }], rowCount: 1 },
    'SELECT * FROM memberships': { rows: [{ human_id: 'H-01', corporation_id: 'CORP-01', city_id: 'CITY-01' }], rowCount: 1 },
  });
  const result = await changeCorporationMembership(new PostgresRepository(db), { humanId: 'H-01', corporationId: 'CORP-01', action: 'join' });
  assert.equal(result.ok, true);
  assert.equal(result.membership.corporation_id, 'CORP-01');
  assert.ok(db.calls.some((call) => call.sql.includes('INSERT INTO membership_events')));
});

test('Corporate API qualification requires membership, city, treasury, constitution, and governance', async () => {
  const db = new Db({
    'FROM corporations WHERE id': { rows: [{ id: 'CORP-01', institution_id: 'CORP-01', member_count: 30, treasury: 1000, constitution_version: 1 }], rowCount: 1 },
    'FROM memberships WHERE corporation_id': { rows: [{ city_id: 'CITY-01' }], rowCount: 1 },
    'FROM institution_roles': { rows: [{ id: 'ROLE-01' }], rowCount: 1 },
    'FROM cities WHERE id': { rows: [{ id: 'CITY-01' }], rowCount: 1 },
  });
  const result = await corporationQualification(new PostgresRepository(db), 'CORP-01');
  assert.equal(result.qualified, true);
  assert.deepEqual(result.requirements, { activeMembership: true, recognizedCity: true, treasury: true, constitution: true, governance: true });
});
