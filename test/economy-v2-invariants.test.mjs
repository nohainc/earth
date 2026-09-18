import test from 'node:test';
import assert from 'node:assert/strict';
import { Client } from 'pg';

const connectionString = process.env.DATABASE_URL;

test('clean baseline Economy V2 posting is balanced and idempotent', { skip: !connectionString }, async (t) => {
  const client = new Client({ connectionString, connectionTimeoutMillis: 3000 });
  await client.connect();
  t.after(() => client.end());

  const accounts = await client.query(`
    SELECT operations.id AS debit_id, treasury.id AS credit_id
      FROM economic_accounts operations
      JOIN economic_accounts treasury ON treasury.owner_economic_id = operations.owner_economic_id
       AND treasury.asset_id = operations.asset_id
       WHERE operations.owner_economic_id = 'ECON-EARTH-001'
       AND operations.asset_id = 1
       AND operations.account_type = 'OPERATIONS'
       AND treasury.account_type = 'TREASURY'
     LIMIT 1`);
  assert.equal(accounts.rowCount, 1, 'baseline must provision Earth CREDIT accounts');
  const { debit_id: debitId, credit_id: creditId } = accounts.rows[0];
  const correlation = `baseline-economy-test:${crypto.randomUUID()}`;
  const entries = JSON.stringify([
    { account_id: debitId, delta_units: -25, asset_id: 1 },
    { account_id: creditId, delta_units: 25, asset_id: 1 },
  ]);

  await client.query('BEGIN');
  try {
    await client.query('UPDATE economic_accounts SET balance_units = 100 WHERE id = $1', [debitId]);
    const first = await client.query(
      'SELECT * FROM earth_post_transaction($1, 1, 0, $2, $3, $4, $5, $6::jsonb)',
      [correlation, 'TEST', 'baseline', 'baseline-test', 'baseline-v1', entries],
    );
    const second = await client.query(
      'SELECT * FROM earth_post_transaction($1, 1, 0, $2, $3, $4, $5, $6::jsonb)',
      [correlation, 'TEST', 'baseline', 'baseline-test', 'baseline-v1', entries],
    );
    assert.equal(first.rows[0].transaction_id, second.rows[0].transaction_id);
    assert.equal(first.rows[0].created, true);
    assert.equal(second.rows[0].created, false);
    const posted = await client.query('SELECT COUNT(*)::int AS count FROM economic_entries WHERE transaction_id = $1', [first.rows[0].transaction_id]);
    assert.equal(posted.rows[0].count, 2);
  } finally {
    await client.query('ROLLBACK');
  }
});
