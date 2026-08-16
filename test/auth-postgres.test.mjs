import test, { after, before } from 'node:test';
import assert from 'node:assert/strict';
import { Client } from 'pg';
import { PostgresRepository } from '../cloudflare/src/repository.ts';
import { loginIdentity, registerIdentity } from '../cloudflare/src/auth-postgres.ts';

const connectionString = process.env.DATABASE_URL;
const email = `auth-test-${Date.now()}@example.invalid`;
let client;
let humanId;

test('registration and verified login are atomic PostgreSQL flows', { skip: !connectionString }, async () => {
  client = new Client({ connectionString });
  await client.connect();
  const repository = new PostgresRepository(client);
  const registration = await registerIdentity(repository, {
    email,
    displayName: 'Auth Test Human',
    password: 'correct-horse-battery-staple',
  });
  humanId = registration.human.id;
  assert.match(humanId, /^H-/);
  assert.equal(registration.starterPackage.credits > 0, true);

  const starterRows = await repository.query(
    `SELECT (
      SELECT COUNT(*) FROM account_balances WHERE owner_id = $1
    ) + (
      SELECT COUNT(*) FROM businesses WHERE owner_id = $1
    ) + (
      SELECT COUNT(*) FROM machines WHERE owner_id = $1
    ) + (
      SELECT COUNT(*) FROM ai_assistants WHERE owner_id = $1
    ) AS count`,
    [humanId],
  );
  assert.equal(Number(starterRows.rows[0].count), 4);

  const businessId = `B-${humanId.slice(2)}`;
  const playableState = await repository.query(
    `SELECT
      (SELECT COUNT(*) FROM institutions WHERE id = $2 AND kind = 'BUSINESS') AS institution,
      (SELECT COUNT(*) FROM business_constitutions WHERE business_id = $2) AS constitution,
      (SELECT COUNT(*) FROM business_management WHERE business_id = $2 AND manager_id = $1) AS management,
      (SELECT COUNT(*) FROM financial_states WHERE institution_id = $2 AND status = 'active') AS business_finance,
      (SELECT COUNT(*) FROM personal_financial_states WHERE human_id = $1 AND status = 'active') AS personal_finance`,
    [humanId, businessId],
  );
  assert.deepEqual(Object.values(playableState.rows[0]).map(Number), [1, 1, 1, 1, 1]);

  await assert.rejects(
    () => loginIdentity(repository, { email, password: 'correct-horse-battery-staple', otp: '', validTotp: async () => false }),
    /Verify your email/,
  );

  await repository.query('UPDATE auth_credentials SET email_verified_at = CURRENT_TIMESTAMP WHERE human_id = $1', [humanId]);
  const login = await loginIdentity(repository, { email, password: 'correct-horse-battery-staple', otp: '', validTotp: async () => false });
  assert.equal(login.ok, true);
  assert.equal(login.human.id, humanId);
  assert.equal(typeof login.token, 'string');
  assert.equal((await repository.query('SELECT COUNT(*) FROM auth_sessions WHERE human_id = $1', [humanId])).rows[0].count, '1');
});

after(async () => {
  if (!client) return;
  const cleanup = new PostgresRepository(client);
  await cleanup.transaction(async (tx) => {
    await tx.query('DELETE FROM auth_sessions WHERE human_id = $1', [humanId]);
    await tx.query('DELETE FROM auth_action_tokens WHERE human_id = $1', [humanId]);
    await tx.query('DELETE FROM auth_login_attempts WHERE email = $1', [email]);
    await tx.query('DELETE FROM ai_assistants WHERE owner_id = $1', [humanId]);
    await tx.query('DELETE FROM business_assets WHERE business_id IN (SELECT id FROM businesses WHERE owner_id = $1)', [humanId]);
    await tx.query('DELETE FROM ownership_events WHERE to_owner_id = $1', [humanId]);
    await tx.query('DELETE FROM research_projects WHERE owner_id = $1', [humanId]);
    await tx.query('DELETE FROM machines WHERE owner_id = $1', [humanId]);
    await tx.query('DELETE FROM business_shares WHERE holder_id = $1', [humanId]);
    await tx.query('DELETE FROM business_financials WHERE business_id IN (SELECT id FROM businesses WHERE owner_id = $1)', [humanId]);
    await tx.query('DELETE FROM business_constitutions WHERE business_id IN (SELECT id FROM businesses WHERE owner_id = $1)', [humanId]);
    await tx.query('DELETE FROM business_management WHERE business_id IN (SELECT id FROM businesses WHERE owner_id = $1)', [humanId]);
    await tx.query('DELETE FROM financial_states WHERE institution_id IN (SELECT id FROM businesses WHERE owner_id = $1)', [humanId]);
    await tx.query('DELETE FROM personal_financial_states WHERE human_id = $1', [humanId]);
    await tx.query('DELETE FROM businesses WHERE owner_id = $1', [humanId]);
    await tx.query('DELETE FROM institutions WHERE id = $1', [`B-${humanId.slice(2)}`]);
    await tx.query('DELETE FROM patents WHERE owner_id = $1', [humanId]);
    await tx.query('DELETE FROM technologies WHERE owner_id = $1', [humanId]);
    await tx.query('DELETE FROM resource_balances WHERE owner_id = $1', [humanId]);
    await tx.query('DELETE FROM account_balances WHERE owner_id = $1', [humanId]);
    await tx.query('DELETE FROM auth_credentials WHERE human_id = $1', [humanId]);
    await tx.query('DELETE FROM humans WHERE id = $1', [humanId]);
  });
  await client.end();
});
