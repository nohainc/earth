import test from 'node:test';
import assert from 'node:assert/strict';
import { postgresClient } from './postgres-connection.mjs';
import { PostgresRepository } from '../cloudflare/src/repository.ts';
import { registerIdentity } from '../cloudflare/src/auth-postgres.ts';
import { deliverOutbox } from '../cloudflare/src/outbox-postgres.ts';
import fs from 'node:fs';

const connectionString = process.env.DATABASE_URL;
const schemaManifest = JSON.parse(fs.readFileSync(new URL('../db/schema-manifest.json', import.meta.url), 'utf8'));

async function connect() {
  const client = postgresClient(connectionString, 'earth-live-integration-test');
  await client.connect();
  return { client, repository: new PostgresRepository(client) };
}

test('PostgreSQL integration target is explicit and the clean world is initialized', { skip: !connectionString }, async () => {
  const { client, repository } = await connect();
  try {
    const result = await repository.query(`SELECT current_database() AS database, current_setting('server_version') AS version, (SELECT COUNT(*) FROM earth_schema_migrations) AS migrations, (SELECT COUNT(*) FROM institutions) AS institutions`);
    assert.equal(result.rows[0].database, new URL(connectionString).pathname.slice(1));
    assert.match(result.rows[0].version, /^\d+\./);
    assert.equal(Number(result.rows[0].migrations), schemaManifest.migrationVersion);
    assert.ok(Number(result.rows[0].institutions) >= 2);
  } finally { await client.end(); }
});

test('canonical registration creates one House principal and outbox delivery is retry-safe', { skip: !connectionString }, async () => {
  const { client, repository } = await connect();
  const email = `outbox-e2e-${Date.now()}@example.invalid`;
  let humanId;
  try {
    const registration = await registerIdentity(repository, { email, personName: 'Outbox', houseSurname: 'Tester', password: 'correct-horse-battery-staple' });
    humanId = registration.human.id;
    const eventKey = `starter-package:${humanId}`;
    assert.equal((await repository.query('SELECT COUNT(*) FROM event_outbox WHERE event_key = $1', [eventKey])).rows[0].count, '1');
    await deliverOutbox(repository, async () => { throw new Error('simulated delivery failure'); });
    const failed = (await repository.query('SELECT attempts, processed_at, locked_at FROM event_outbox WHERE event_key = $1', [eventKey])).rows[0];
    assert.equal(Number(failed.attempts), 1);
    assert.equal(failed.processed_at, null);
    assert.equal(failed.locked_at, null);
  } finally {
    if (humanId) await repository.transaction(async (tx) => {
      const houseId = `HOUSE-${humanId.slice(2)}`;
      const economicId = `ECON-${houseId}`;
      await tx.query('DELETE FROM event_outbox WHERE aggregate_id = $1', [humanId]);
      await tx.query('DELETE FROM auth_sessions WHERE human_id = $1', [humanId]);
      await tx.query('DELETE FROM economic_entries WHERE account_id IN (SELECT id FROM economic_accounts WHERE owner_economic_id = $1)', [economicId]);
      await tx.query('DELETE FROM economic_entries WHERE transaction_id IN (SELECT id FROM economic_transactions WHERE correlation_id LIKE $1)', [`starter:${houseId}:%`]);
      await tx.query('DELETE FROM economic_transactions WHERE correlation_id LIKE $1', [`starter:${houseId}:%`]);
      await tx.query('DELETE FROM economic_accounts WHERE owner_economic_id = $1', [economicId]);
      await tx.query('DELETE FROM owner_registry WHERE economic_id = $1', [economicId]);
      await tx.query('UPDATE houses SET current_human_id = NULL WHERE id = $1', [houseId]);
      await tx.query('DELETE FROM humans WHERE id = $1', [humanId]);
      await tx.query('UPDATE auth_accounts SET house_id = NULL WHERE email = $1', [email]);
      await tx.query('DELETE FROM house_entry_support WHERE house_id = $1', [houseId]);
      await tx.query('DELETE FROM house_onboarding_progress WHERE house_id = $1', [houseId]);
      await tx.query('DELETE FROM v5_house_settlement_profiles WHERE house_id = $1', [houseId]);
      await tx.query('DELETE FROM houses WHERE id = $1', [houseId]);
      await tx.query('DELETE FROM auth_accounts WHERE email = $1', [email]);
    });
  }
  await client.end();
});

test('canonical PostgreSQL world projection contains no legacy economic authority', { skip: !connectionString }, async () => {
  const { client, repository } = await connect();
  try {
    const world = (await repository.query("SELECT world_seed FROM world_state WHERE id = 'WORLD'")).rows[0];
    const clock = (await repository.query("SELECT game_day, game_minute FROM earth_get_current_game_time()")).rows[0];
    assert.ok(Number(clock.game_day) >= 1);
    assert.ok(Number(clock.game_minute) >= 0 && Number(clock.game_minute) <= 1439);
    assert.equal(world.world_seed, 'EARTH-GENESIS');
    assert.equal((await repository.query("SELECT COUNT(*) FROM pg_tables WHERE schemaname = 'public' AND tablename IN ('account_balances','resource_balances','ledger_entries','businesses')")).rows[0].count, '0');
    assert.ok(Number((await repository.query('SELECT COUNT(*) FROM economic_assets')).rows[0].count) >= 6);
  } finally { await client.end(); }
});
