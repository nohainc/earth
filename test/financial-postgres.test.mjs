import test from 'node:test';
import assert from 'node:assert/strict';
import { transferCredits } from '../cloudflare/src/financial-postgres.ts';

class FakeRepository {
  constructor(row) { this.row = row; this.calls = []; }

  async query(sql, params) {
    this.calls.push({ sql, params });
    return { rows: this.row ? [this.row] : [] };
  }
}

const input = {
  ledgerId: '00000000-0000-0000-0000-000000000001',
  gameDay: 12,
  debitAccount: 'human-account',
  creditAccount: 'account-ouc-treasury',
  amount: 12.34,
  reasonType: 'tax_settlement',
  reasonId: 'human-account',
  ruleVersion: 'tax-v2',
  correlationId: 'TAX-human-account-12-12.34-2',
};

test('financial adapter delegates one atomic transfer and maps PostgreSQL result', async () => {
  const repository = new FakeRepository({
    status: 'applied',
    ledger_id: input.ledgerId,
    amount: '12.34',
    already_processed: false,
  });

  const result = await transferCredits(repository, input);

  assert.deepEqual(result, {
    status: 'applied',
    ledgerId: input.ledgerId,
    amount: '12.34',
    alreadyProcessed: false,
  });
  assert.match(repository.calls[0].sql, /earth_transfer_credits/);
  assert.deepEqual(repository.calls[0].params, [
    input.ledgerId,
    input.gameDay,
    input.debitAccount,
    input.creditAccount,
    input.amount,
    input.reasonType,
    input.reasonId,
    input.ruleVersion,
    input.correlationId,
  ]);
});

test('financial adapter preserves idempotent replay result', async () => {
  const repository = new FakeRepository({
    status: 'already_processed',
    ledger_id: input.ledgerId,
    amount: '12.34',
    already_processed: true,
  });

  const result = await transferCredits(repository, input);
  assert.equal(result.status, 'already_processed');
  assert.equal(result.alreadyProcessed, true);
});

test('financial adapter fails closed when the database returns no result', async () => {
  await assert.rejects(() => transferCredits(new FakeRepository(null), input), /returned no result/);
});
