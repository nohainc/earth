import test from 'node:test';
import assert from 'node:assert/strict';
import { postgresClient } from './postgres-connection.mjs';
import { PostgresRepository } from '../cloudflare/src/repository.ts';
import { listEvents, listHistory, listInstitutions, listMarketPriceHistory, listPantheonOfAchievements, listCemeteryProfiles } from '../cloudflare/src/read-postgres.ts';
import { listNotifications } from '../cloudflare/src/read-models/notifications-read.ts';
import { listRankings } from '../cloudflare/src/read-postgres.ts';

const connectionString = process.env.DATABASE_URL;
const undefinedObjectCodes = new Set(['42P01', '42703', '42883']);

test('registered read projections execute without undefined PostgreSQL objects', { skip: !connectionString }, async () => {
  const client = postgresClient(connectionString, 'earth-runtime-dependency-certification');
  await client.connect();
  const repository = new PostgresRepository(client);
  try {
    const human = (await repository.query("SELECT id, house_id FROM humans WHERE status = 'ACTIVE' ORDER BY id LIMIT 1")).rows[0];
    assert.ok(human, 'certification database must contain an active Human');
    const projections = [
      ['events', () => listEvents(repository, 10)],
      ['history', () => listHistory(repository, 10)],
      ['institutions', () => listInstitutions(repository)],
      ['market history', () => listMarketPriceHistory(repository, 'MATERIAL', 10)],
      ['pantheon', () => listPantheonOfAchievements(repository)],
      ['cemetery', () => listCemeteryProfiles(repository, { limit: 10 })],
      ['notifications', () => listNotifications(repository, human.house_id, 10)],
      ['rankings', () => listRankings(repository, { currentHumanId: human.id, limit: 10 })],
    ];
    for (const [name, invoke] of projections) {
      try {
        await invoke();
      } catch (error) {
        assert.ok(!undefinedObjectCodes.has(error?.code), `${name} referenced an undefined PostgreSQL object: ${error.message}`);
        throw error;
      }
    }
  } finally {
    await client.end();
  }
});
