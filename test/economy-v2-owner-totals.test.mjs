import test from 'node:test';
import assert from 'node:assert/strict';
import { Client } from 'pg';

const connectionString = process.env.DATABASE_URL;

test('Economy V2 owner totals classify internal transfers by owner net', { skip: !connectionString }, async (t) => {
  const client = new Client({ connectionString, connectionTimeoutMillis: 3000 });
  await client.connect();
  t.after(() => client.end());

  const ready = await client.query(`
    SELECT to_regprocedure('earth_post_transaction(text,bigint,smallint,text,text,text,text,jsonb)') AS post
  `);
  if (!ready.rows[0].post) {
    t.skip('Economy V2 owner totals migration is not applied to DATABASE_URL');
    return;
  }

  const accounts = await client.query(`
    SELECT wallet.id AS wallet_id, reserve.id AS reserve_id,
           wallet.owner_economic_id
    FROM economic_accounts wallet
    JOIN economic_accounts reserve
      ON reserve.owner_economic_id = wallet.owner_economic_id
     AND reserve.asset_id = wallet.asset_id
     AND reserve.account_type = 5
     AND reserve.status = 'active'
    WHERE wallet.asset_id = 1
      AND wallet.account_type = 1
      AND wallet.status = 'active'
      AND wallet.balance >= 100
    LIMIT 1
  `);
  if (accounts.rowCount === 0) {
    t.skip('An owner with funded WALLET and active RESERVE CREDIT accounts is required');
    return;
  }

  const { wallet_id: walletId, reserve_id: reserveId, owner_economic_id: ownerId } = accounts.rows[0];
  const before = await client.query(
    'SELECT credit_received, credit_spent FROM economic_owner_totals WHERE owner_economic_id = $1',
    [ownerId],
  );
  assert.equal(before.rowCount, 1);

  await client.query('BEGIN');
  await client.query(
    'SELECT * FROM earth_post_transaction($1, 1, 0, $2, $3, $4, $5, $6::jsonb)',
    [
      `test-plan23-${crypto.randomUUID()}`,
      'TEST',
      'plan23',
      'v2-test',
      JSON.stringify([
        { account_id: walletId, delta: -100, reason_code: 'test_internal_transfer' },
        { account_id: reserveId, delta: 100, reason_code: 'test_internal_transfer' },
      ]),
    ],
  );
  const after = await client.query(
    'SELECT credit_received, credit_spent FROM economic_owner_totals WHERE owner_economic_id = $1',
    [ownerId],
  );
  assert.deepEqual(after.rows[0], before.rows[0]);
  await client.query('ROLLBACK');
});
