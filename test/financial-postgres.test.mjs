import test from 'node:test';
import assert from 'node:assert/strict';
import { transferCredits } from '../cloudflare/src/financial-postgres.ts';

class FakeRepository {
  constructor(row) { this.row = row; this.calls = []; }

  async transaction(callback) { return callback(this); }

  async query(sql, params) {
    this.calls.push({ sql, params });
    if (sql.includes('earth_get_current_game_time')) {
      return {
        rows: [{
          game_day: 12,
          game_minute: 100,
          total_game_minutes: 12 * 1440 + 100,
          genesis_at: new Date(Date.now() - 100000).toISOString(),
          server_now: new Date().toISOString(),
          elapsed_real_seconds: 100,
          real_seconds_per_game_minute: 1,
        }],
      };
    }
    if (sql.includes('daily_settlement_control')) {
      return {
        rows: [{
          status: 'active',
          settled_through_game_day: 11,
        }],
      };
    }
    if (sql.includes('FROM economic_accounts')) return { rows: [{ account_id: params[0] === input.debitPrincipalId ? '101' : '102' }] };
    if (sql.includes('earth_post_transaction')) return { rows: this.row ? [{ transaction_id: input.ledgerId, created: this.row.already_processed !== true }] : [] };
    return { rows: this.row ? [this.row] : [] };
  }
}

const input = {
  ledgerId: '00000000-0000-0000-0000-000000000001',
  gameDay: 12,
  debitPrincipalId: 'human-account',
  debitPurpose: 'WALLET',
  creditPrincipalId: 'earth-treasury',
  creditPurpose: 'TREASURY',
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
  assert.ok(repository.calls.some(({ sql }) => /earth_post_transaction/.test(sql)));
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

test('financial adapter has no legacy transfer fallback', async () => {
  const source = await import('node:fs/promises').then((fs) => fs.readFile(new URL('../cloudflare/src/financial-postgres.ts', import.meta.url), 'utf8'));
  assert.doesNotMatch(source, /earth_transfer_credits|await transferCredits\(repository, input\)/);
});
