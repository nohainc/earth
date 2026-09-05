import test from 'node:test';
import assert from 'node:assert/strict';
import 'dotenv/config';
import { Client } from 'pg';
import { PostgresRepository } from '../cloudflare/src/repository.ts';
import { createBankDeposit, withdrawBankDeposit } from '../cloudflare/src/global-bank-postgres.ts';
import { settleGlobalBank } from '../cloudflare/src/global-bank-settlement-engine.ts';

const DATABASE_URL = process.env.DATABASE_URL || 'postgres://earth:earth_dev_only@localhost:5432/earth';

async function withRollback(work) {
  const client = new Client({ connectionString: DATABASE_URL });
  await client.connect();
  const repository = new PostgresRepository(client);
  await client.query('BEGIN');
  try { return await work(repository, client); }
  finally { await client.query('ROLLBACK').catch(() => undefined); await client.end(); }
}

async function testHuman(client, minimum = 1000) {
  const result = await client.query(
    `SELECT a.owner_id AS id FROM account_balances a
      JOIN humans h ON h.id = a.owner_id
      WHERE a.currency = 'CREDIT' AND a.balance >= $1
      ORDER BY a.owner_id LIMIT 1`, [minimum]);
  assert.ok(result.rows[0]?.id, 'A funded local test human is required');
  return result.rows[0].id;
}

test('bank mutation wrappers send only backend-owned mutation inputs', async () => {
  const calls = [];
  const repository = { query: async (sql, params) => { calls.push({ sql, params }); return { rows: [{ id: 'DEP-x' }] }; } };
  await createBankDeposit(repository, { humanId: 'H-1', amount: 125, termDays: 7, correlationId: 'corr-x' });
  await withdrawBankDeposit(repository, { humanId: 'H-1', depositId: 'DEP-x', correlationId: 'corr-y' });
  assert.match(calls[0].sql, /earth_create_bank_deposit/);
  assert.deepEqual(calls[0].params, ['DEP-corr-x', 'H-1', 125, 7, 'corr-x']);
  assert.match(calls[1].sql, /earth_withdraw_bank_deposit/);
  assert.deepEqual(calls[1].params, ['H-1', 'DEP-x', 'corr-y']);
  assert.ok(!calls.flatMap((call) => call.params).some((value) => value instanceof Date));
});

test('database creates deposits with authoritative game timestamps', async () => {
  await withRollback(async (repository, client) => {
    const humanId = await testHuman(client);
    const id = `DEP-BANK-TEST-CREATE-${Date.now()}`;
    const result = await repository.query('SELECT * FROM earth_create_bank_deposit($1, $2, $3, $4, $5)', [id, humanId, 25, 3, `${id}-CORR`]);
    const deposit = result.rows[0];
    assert.equal(deposit.id, id);
    assert.equal(Number(deposit.principal), 25);
    assert.equal(Number(deposit.maturity_game_day) - Number(deposit.start_game_day), 3);
    assert.equal(Number(deposit.maturity_game_minute), Number(deposit.start_game_minute));
    assert.equal(Number(deposit.last_settled_game_day), Number(deposit.start_game_day));
    assert.equal(deposit.status, 'active');
  });
});

test('database rejects invalid terms and insufficient funds', async () => {
  await withRollback(async (repository, client) => {
    const humanId = await testHuman(client);
    await client.query('SAVEPOINT invalid_term');
    await assert.rejects(repository.query('SELECT * FROM earth_create_bank_deposit($1, $2, $3, $4, $5)', ['DEP-BANK-TEST-INVALID', humanId, 25, 0, 'BANK-INVALID-TERM']), /between 1 and 90/);
    await client.query('ROLLBACK TO SAVEPOINT invalid_term');
    await client.query('SAVEPOINT invalid_funds');
    await assert.rejects(repository.query('SELECT * FROM earth_create_bank_deposit($1, $2, $3, $4, $5)', ['DEP-BANK-TEST-FUNDS', humanId, 999999999, 7, 'BANK-INVALID-FUNDS']), /Insufficient Credits/);
    await client.query('ROLLBACK TO SAVEPOINT invalid_funds');
  });
});

test('database create is idempotent and does not debit twice', async () => {
  await withRollback(async (repository, client) => {
    const humanId = await testHuman(client);
    const id = `DEP-BANK-TEST-IDEMPOTENT-${Date.now()}`;
    const correlationId = `${id}-CORR`;
    const before = await client.query("SELECT balance FROM account_balances WHERE owner_id = $1 AND currency = 'CREDIT'", [humanId]);
    const first = await repository.query('SELECT * FROM earth_create_bank_deposit($1, $2, $3, $4, $5)', [id, humanId, 25, 3, correlationId]);
    const second = await repository.query('SELECT * FROM earth_create_bank_deposit($1, $2, $3, $4, $5)', [id, humanId, 25, 3, correlationId]);
    const after = await client.query("SELECT balance FROM account_balances WHERE owner_id = $1 AND currency = 'CREDIT'", [humanId]);
    assert.equal(second.rows[0].id, first.rows[0].id);
    assert.equal(Number(before.rows[0].balance) - Number(after.rows[0].balance), 25);
    const ledger = await client.query('SELECT COUNT(*)::int AS count FROM ledger_entries WHERE correlation_id = $1', [correlationId]);
    assert.equal(ledger.rows[0].count, 1);
  });
});

test('database blocks early withdrawal and pays a matured deposit once', async () => {
  await withRollback(async (repository, client) => {
    const humanId = await testHuman(client);
    const id = `DEP-BANK-TEST-WITHDRAW-${Date.now()}`;
    await repository.query('SELECT * FROM earth_create_bank_deposit($1, $2, $3, $4, $5)', [id, humanId, 25, 3, `${id}-CREATE`]);
    await client.query('SAVEPOINT early_withdrawal');
    await assert.rejects(repository.query('SELECT * FROM earth_withdraw_bank_deposit($1, $2, $3)', [humanId, id, `${id}-EARLY`]), /not reached maturity/);
    await client.query('ROLLBACK TO SAVEPOINT early_withdrawal');
    const now = (await client.query('SELECT * FROM earth_get_current_game_time()')).rows[0];
    const nowDay = Math.floor(Number(now.total_game_minutes) / 1440) + 1;
    const nowMinute = Number(now.total_game_minutes) % 1440;
    await client.query('UPDATE global_bank_deposits SET maturity_game_day = $1, maturity_game_minute = $2 WHERE id = $3', [nowDay, nowMinute, id]);
    const payout = await repository.query('SELECT * FROM earth_withdraw_bank_deposit($1, $2, $3)', [humanId, id, `${id}-WITHDRAW`]);
    assert.equal(Number(payout.rows[0].principal), 25);
    assert.equal(Number(payout.rows[0].payout), Number(payout.rows[0].principal) + Number(payout.rows[0].interest));
    await assert.rejects(repository.query('SELECT * FROM earth_withdraw_bank_deposit($1, $2, $3)', [humanId, id, `${id}-WITHDRAW-AGAIN`]), /not withdrawable/);
  });
});

test('bank settlement is idempotent for a game day', async () => {
  await withRollback(async (repository, client) => {
    const now = (await client.query('SELECT * FROM earth_get_current_game_time()')).rows[0];
    const nowDay = Math.floor(Number(now.total_game_minutes) / 1440) + 1;
    const first = await settleGlobalBank(repository, nowDay);
    const second = await settleGlobalBank(repository, nowDay);
    assert.equal(second, 0);
    const journal = await client.query('SELECT COUNT(*)::int AS count FROM global_bank_settlement_journals WHERE game_day = $1', [nowDay]);
    assert.equal(journal.rows[0].count, 1);
    assert.ok(first >= 0);
  });
});
