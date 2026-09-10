import test from 'node:test';
import assert from 'node:assert/strict';
import { Client } from 'pg';

const connectionString = process.env.DATABASE_URL;

test('Economy V2 transaction invariants', { skip: !connectionString }, async (t) => {
  const client = new Client({ connectionString, connectionTimeoutMillis: 3000 });
  await client.connect();
  t.after(() => client.end());

  const ready = await client.query(`
    SELECT to_regprocedure('earth_post_transaction(text,bigint,smallint,text,text,text,text,jsonb)') AS post,
           to_regprocedure('earth_begin_economic_transaction(text,bigint,smallint,text,text,text,text)') AS begin_tx,
           to_regprocedure('earth_post_settlement_batch(text,bigint,smallint,text,text,text,jsonb)') AS batch
  `);
  if (!ready.rows[0].post || !ready.rows[0].begin_tx || !ready.rows[0].batch) {
    t.skip('Economy V2 migration 171 is not applied to DATABASE_URL');
    return;
  }

  const accounts = await client.query(`
    SELECT issuance.id AS debit_id, sink.id AS credit_id
    FROM economic_accounts issuance
    JOIN economic_accounts sink ON sink.asset_id = issuance.asset_id
    WHERE issuance.account_type = 7 AND sink.account_type = 8
      AND issuance.asset_id = 1 AND issuance.status = 'active' AND sink.status = 'active'
    LIMIT 1
  `);
  assert.equal(accounts.rowCount, 1, 'system issuance and sink accounts are required');
  const { debit_id: debitId, credit_id: creditId } = accounts.rows[0];
  const effects = (a, b, amount = 500) => JSON.stringify([
    { account_id: a, delta: -amount, reason_code: 'test_debit' },
    { account_id: b, delta: amount, reason_code: 'test_credit' },
  ]);
  const correlation = () => `test-plan22-${crypto.randomUUID()}`;

  async function commitMustFail() {
    await assert.rejects(
      () => client.query('COMMIT'),
      /requires at least two entries|not balanced per asset/,
    );
  }

  async function beginHeader() {
    const result = await client.query(
      'SELECT * FROM earth_begin_economic_transaction($1, 1, 0, $2, $3, $4, $5)',
      [correlation(), 'TEST', 'plan22', 'v2-test'],
    );
    return result.rows[0].transaction_id;
  }

  await t.test('balanced transaction succeeds', async () => {
    await client.query('BEGIN');
    await client.query('SELECT * FROM earth_post_transaction($1, 1, 0, $2, $3, $4, $5, $6::jsonb)', [correlation(), 'TEST', 'plan22', 'v2-test', effects(debitId, creditId)]);
    await client.query('ROLLBACK');
  });

  await t.test('unbalanced transaction fails at commit', async () => {
    await client.query('BEGIN');
    const transactionId = await beginHeader();
    await client.query(
      'INSERT INTO economic_entries (transaction_id, account_id, game_day, delta, reason_code) VALUES ($1, $2, 1, 500, $3), ($1, $4, 1, 400, $5)',
      [transactionId, debitId, 'test_unbalanced_debit', creditId, 'test_unbalanced_credit'],
    );
    await commitMustFail();
  });

  await t.test('deleting an entry from an existing transaction fails at commit', async () => {
    await client.query('BEGIN');
    const posted = await client.query(
      'SELECT * FROM earth_post_transaction($1, 1, 0, $2, $3, $4, $5, $6::jsonb)',
      [correlation(), 'TEST', 'plan22', 'v2-test', effects(debitId, creditId)],
    );
    const transactionId = posted.rows[0].transaction_id;
    await client.query(
      'DELETE FROM economic_entries WHERE transaction_id = $1 AND account_id = $2',
      [transactionId, debitId],
    );
    await commitMustFail();
  });

  await t.test('modifying an entry so totals cease balancing fails at commit', async () => {
    await client.query('BEGIN');
    const posted = await client.query(
      'SELECT * FROM earth_post_transaction($1, 1, 0, $2, $3, $4, $5, $6::jsonb)',
      [correlation(), 'TEST', 'plan22', 'v2-test', effects(debitId, creditId)],
    );
    const transactionId = posted.rows[0].transaction_id;
    await client.query(
      'UPDATE economic_entries SET delta = delta + 1 WHERE transaction_id = $1 AND account_id = $2',
      [transactionId, creditId],
    );
    await commitMustFail();
  });

  await t.test('duplicate correlation returns original and parameter mismatch fails', async () => {
    const key = correlation();
    await client.query('BEGIN');
    const first = await client.query('SELECT * FROM earth_begin_economic_transaction($1, 1, 0, $2, $3, $4, $5)', [key, 'TEST', 'plan22', 'v2-test']);
    const second = await client.query('SELECT * FROM earth_begin_economic_transaction($1, 1, 0, $2, $3, $4, $5)', [key, 'TEST', 'plan22', 'v2-test']);
    assert.equal(first.rows[0].transaction_id, second.rows[0].transaction_id);
    await assert.rejects(() => client.query('SELECT * FROM earth_begin_economic_transaction($1, 2, 0, $2, $3, $4, $5)', [key, 'TEST', 'plan22', 'v2-test']), /different transaction parameters/);
    await client.query('ROLLBACK');
  });

  await t.test('settlement batch rejects fewer than two final entries', async () => {
    await assert.rejects(
      () => client.query('SELECT * FROM earth_post_settlement_batch($1, 1, 0, $2, $3, $4, $5::jsonb)', [correlation(), 'scheduler', 'plan22', 'v2-test', JSON.stringify([{ account_id: debitId, delta: 1, reason_code: 'one' }])]),
      /at least two final net entries/,
    );
  });
});
