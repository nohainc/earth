import test from 'node:test';
import assert from 'node:assert/strict';
import { postgresClient } from './postgres-connection.mjs';

const connectionString = process.env.DATABASE_URL;
const options = { skip: !connectionString };

async function connect(name) {
  const client = postgresClient(connectionString, name);
  await client.connect();
  return client;
}

async function testAccounts(client) {
  const result = await client.query(
    `SELECT id::TEXT AS id FROM economic_accounts
      WHERE asset_id = 1 AND status = 'ACTIVE' ORDER BY id LIMIT 2`,
  );
  assert.equal(result.rows.length, 2, 'two seeded active CREDIT accounts are required');
  return result.rows.map((row) => row.id);
}

function entries(sourceAccountId, destinationAccountId) {
  return JSON.stringify([
    { account_id: sourceAccountId, asset_id: 1, delta_units: '-1', reason_code: 'certification_debit' },
    { account_id: destinationAccountId, asset_id: 1, delta_units: '1', reason_code: 'certification_credit' },
  ]);
}

async function removeTransactions(client, correlations, sourceAccountId, destinationAccountId) {
  await client.query(
    `DELETE FROM economic_entries WHERE transaction_id IN
      (SELECT id FROM economic_transactions WHERE correlation_id = ANY($1::TEXT[]))`,
    [correlations],
  );
  await client.query('DELETE FROM economic_transactions WHERE correlation_id = ANY($1::TEXT[])', [correlations]);
  await client.query('UPDATE economic_accounts SET balance_units = balance_units + 1 WHERE id = $1', [sourceAccountId]);
  await client.query('UPDATE economic_accounts SET balance_units = balance_units - 1 WHERE id = $1', [destinationAccountId]);
}

test('real PostgreSQL clock and economic posting preserve coordinates and idempotency', options, async () => {
  const client = await connect('earth-authoritative-time-certification');
  const correlation = `certification:clock:${crypto.randomUUID()}`;
  try {
    await client.query('BEGIN');
    const clock = (await client.query('SELECT * FROM earth_get_current_game_time()')).rows[0];
    const [sourceAccountId, destinationAccountId] = await testAccounts(client);
    const result = await client.query(
      `SELECT transaction_id, created FROM earth_post_transaction(
        $1, $2, $3, 'CERTIFICATION', 'TEST', 'authoritative-time', 'certification-v1', $4::JSONB)`,
      [correlation, clock.game_day, clock.game_minute, entries(sourceAccountId, destinationAccountId)],
    );
    assert.equal(result.rows[0].created, true);
    const retry = await client.query(
      `SELECT transaction_id, created FROM earth_post_transaction(
        $1, $2, $3, 'CERTIFICATION', 'TEST', 'authoritative-time', 'certification-v1', $4::JSONB)`,
      [correlation, clock.game_day, clock.game_minute, entries(sourceAccountId, destinationAccountId)],
    );
    assert.equal(retry.rows[0].created, false);
    assert.equal(retry.rows[0].transaction_id, result.rows[0].transaction_id);
    await client.query('ROLLBACK');
  } finally {
    await client.query('ROLLBACK').catch(() => {});
    await client.end();
  }
});

test('two real PostgreSQL connections serialize duplicate economic correlations', options, async () => {
  const first = await connect('earth-authoritative-time-certification-a');
  const second = await connect('earth-authoritative-time-certification-b');
  const cleanup = await connect('earth-authoritative-time-certification-cleanup');
  const correlation = `certification:concurrency:${crypto.randomUUID()}`;
  let sourceAccountId;
  let destinationAccountId;
  try {
    const clock = (await first.query('SELECT * FROM earth_get_current_game_time()')).rows[0];
    [sourceAccountId, destinationAccountId] = await testAccounts(first);
    const values = [correlation, clock.game_day, clock.game_minute, entries(sourceAccountId, destinationAccountId)];
    await first.query('BEGIN');
    await second.query('BEGIN');
    const firstResult = await first.query(
      `SELECT transaction_id, created FROM earth_post_transaction(
        $1, $2, $3, 'CERTIFICATION', 'TEST', 'concurrent-time', 'certification-v1', $4::JSONB)`, values,
    );
    assert.equal(firstResult.rows[0].created, true);
    const secondResultPromise = second.query(
      `SELECT transaction_id, created FROM earth_post_transaction(
        $1, $2, $3, 'CERTIFICATION', 'TEST', 'concurrent-time', 'certification-v1', $4::JSONB)`, values,
    );
    await first.query('COMMIT');
    const secondResult = await secondResultPromise;
    await second.query('COMMIT');
    assert.equal(secondResult.rows[0].created, false);
    assert.equal(secondResult.rows[0].transaction_id, firstResult.rows[0].transaction_id);
  } finally {
    await first.query('ROLLBACK').catch(() => {});
    await second.query('ROLLBACK').catch(() => {});
    await cleanup.query('BEGIN');
    await removeTransactions(cleanup, [correlation], sourceAccountId, destinationAccountId);
    await cleanup.query('COMMIT');
    await first.end();
    await second.end();
    await cleanup.end();
  }
});

test('real PostgreSQL settlement posting returns a true idempotency result', options, async () => {
  const client = await connect('earth-settlement-time-certification');
  const correlation = `certification:settlement:${crypto.randomUUID()}`;
  try {
    await client.query('BEGIN');
    const [sourceAccountId, destinationAccountId] = await testAccounts(client);
    const result = await client.query(
      `SELECT transaction_id, created FROM earth_post_settlement_batch(
        $1, 1, 1439, 'CERTIFICATION', 'settlement-time', 'certification-v1', $2::JSONB)`,
      [correlation, entries(sourceAccountId, destinationAccountId)],
    );
    assert.equal(result.rows[0].created, true);
    const retry = await client.query(
      `SELECT transaction_id, created FROM earth_post_settlement_batch(
        $1, 1, 1439, 'CERTIFICATION', 'settlement-time', 'certification-v1', $2::JSONB)`,
      [correlation, entries(sourceAccountId, destinationAccountId)],
    );
    assert.equal(retry.rows[0].created, false);
    assert.equal(retry.rows[0].transaction_id, result.rows[0].transaction_id);
    await client.query('ROLLBACK');
  } finally {
    await client.query('ROLLBACK').catch(() => {});
    await client.end();
  }
});
