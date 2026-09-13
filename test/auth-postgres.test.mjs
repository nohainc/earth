import test from 'node:test';
import assert from 'node:assert/strict';
import { postgresClient } from './postgres-connection.mjs';
import { PostgresRepository } from '../cloudflare/src/repository.ts';
import { loginIdentity, registerIdentity } from '../cloudflare/src/auth-postgres.ts';

const connectionString = process.env.DATABASE_URL;

test('registration and verified login use the canonical Account → House → Human model', { skip: !connectionString }, async () => {
  const client = postgresClient(connectionString, 'earth-live-auth-test');
  await client.connect();
  const repository = new PostgresRepository(client);
  const email = `auth-test-${Date.now()}@example.invalid`;
  let humanId;
  try {
    const registration = await registerIdentity(repository, { email, personName: 'Auth', houseSurname: 'Tester', password: 'correct-horse-battery-staple' });
    humanId = registration.human.id;
    assert.match(humanId, /^H-/);
    assert.ok(registration.starterPackage.credits > 0);
    const identity = (await repository.query(`SELECT a.id AS account_id, h.id AS house_id, h.current_human_id, human.id AS human_id, human.status FROM auth_accounts a JOIN houses h ON h.account_id = a.id JOIN humans human ON human.house_id = h.id WHERE a.email = $1`, [email])).rows[0];
    assert.deepEqual(identity, { account_id: `account-${humanId.toLowerCase()}`, house_id: `HOUSE-${humanId.slice(2)}`, current_human_id: humanId, human_id: humanId, status: 'ACTIVE' });
    await assert.rejects(() => loginIdentity(repository, { email, password: 'correct-horse-battery-staple', otp: '', validTotp: async () => false }), /Verify your email/);
    await repository.query('UPDATE auth_accounts SET email_verified_at = CURRENT_TIMESTAMP WHERE email = $1', [email]);
    const login = await loginIdentity(repository, { email, password: 'correct-horse-battery-staple', otp: '', validTotp: async () => false });
    assert.equal(login.ok, true);
    assert.equal(login.human.id, humanId);
    assert.equal((await repository.query('SELECT COUNT(*) FROM auth_sessions WHERE account_id = $1', [`account-${humanId.toLowerCase()}`])).rows[0].count, '1');
  } finally {
    if (humanId) await repository.transaction(async (tx) => {
      const houseId = `HOUSE-${humanId.slice(2)}`;
      const economicId = `ECON-${houseId}`;
      await tx.query('DELETE FROM auth_sessions WHERE account_id = $1', [`account-${humanId.toLowerCase()}`]);
      await tx.query('DELETE FROM event_outbox WHERE aggregate_id = $1', [humanId]);
      await tx.query('DELETE FROM buildings WHERE owner_economic_id = $1', [economicId]);
      await tx.query('DELETE FROM economic_entries WHERE account_id IN (SELECT id FROM economic_accounts WHERE owner_economic_id = $1)', [economicId]);
      await tx.query("DELETE FROM economic_transactions WHERE correlation_id LIKE $1", [`starter:${houseId}:%`]);
      await tx.query('DELETE FROM economic_accounts WHERE owner_economic_id = $1', [economicId]);
      await tx.query('DELETE FROM owner_registry WHERE economic_id = $1', [economicId]);
      await tx.query('UPDATE houses SET current_human_id = NULL WHERE id = $1', [houseId]);
      await tx.query('DELETE FROM humans WHERE id = $1', [humanId]);
      await tx.query('UPDATE auth_accounts SET house_id = NULL WHERE email = $1', [email]);
      await tx.query('DELETE FROM houses WHERE id = $1', [houseId]);
      await tx.query('DELETE FROM auth_accounts WHERE email = $1', [email]);
    });
  }
  await client.end();
});
