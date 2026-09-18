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

test('Market fill sequences are scoped by instrument within one batch', options, async (t) => {
  const client = await connect('earth-market-fill-sequence-certification');
  try {
    await client.query('BEGIN');

    const instruments = await client.query(
      `SELECT id FROM market_instruments
       WHERE symbol IN ('ENERGY', 'FOOD')
       ORDER BY symbol`,
    );
    const owners = await client.query('SELECT economic_id FROM owner_registry ORDER BY economic_id LIMIT 1');
    const transaction = await client.query('SELECT id FROM economic_transactions ORDER BY id LIMIT 1');
    if (instruments.rows.length < 2 || owners.rows.length < 1 || transaction.rows.length < 1) {
      t.skip('seeded market instruments, owner, and transaction are required');
      await client.query('ROLLBACK');
      return;
    }

    const batch = await client.query(
      `INSERT INTO market_batches (game_day, game_minute, status, correlation_id)
       VALUES (1, 0, 'OPEN', $1)
       RETURNING id`,
      [`certification:market-fill-sequence:${crypto.randomUUID()}`],
    );
    const batchId = batch.rows[0].id;
    const instrumentIds = instruments.rows.map((row) => row.id);
    const ownerId = owners.rows[0].economic_id;
    const transactionId = transaction.rows[0].id;

    const orderIds = instrumentIds.slice(0, 2).map((instrumentId, index) => `CERT-MARKET-FILL-${crypto.randomUUID()}-${index}`);
    for (const [index, instrumentId] of instrumentIds.slice(0, 2).entries()) {
      await client.query(
        `INSERT INTO market_orders
          (id, batch_id, instrument_id, owner_economic_id, side, quantity_units, remaining_units,
           limit_price_units, rules_version, correlation_id)
         VALUES ($1, $2, $3, $4, 'BUY', 1, 1, 1, 'certification-v1', $5)`,
        [orderIds[index], batchId, instrumentId, ownerId, `${orderIds[index]}:correlation`],
      );
    }

    const insertFill = async (instrumentId, orderId) => client.query(
      `INSERT INTO market_fills
        (batch_id, instrument_id, buy_order_id, sell_order_id, buyer_economic_id, seller_economic_id,
         quantity_units, price_units, gross_quote_units, buyer_fee_units, seller_fee_units,
         economic_transaction_id, sequence_no)
       VALUES ($1, $2, $3, $3, $4, $4, 1, 1, 1, 0, 0, $5, 1)`,
      [batchId, instrumentId, orderId, ownerId, transactionId],
    );

    await insertFill(instrumentIds[0], orderIds[0]);
    await insertFill(instrumentIds[1], orderIds[1]);
    const count = await client.query(
      'SELECT COUNT(*)::INTEGER AS count FROM market_fills WHERE batch_id = $1 AND sequence_no = 1',
      [batchId],
    );
    assert.equal(count.rows[0].count, 2);
    await client.query('ROLLBACK');
  } finally {
    await client.query('ROLLBACK').catch(() => {});
    await client.end();
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
