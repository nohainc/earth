import test from 'node:test';
import assert from 'node:assert/strict';
import { executeMerger, proposeMerger } from '../cloudflare/src/business-postgres.ts';
import { listMarketPriceHistory } from '../cloudflare/src/read-postgres.ts';

function createMockRepository(queries) {
  return {
    async transaction(callback) {
      return callback({
        async query(sql, params = []) {
          return queries(sql, params);
        },
      });
    },
    async query(sql, params = []) {
      return queries(sql, params);
    },
  };
}

test('listMarketPriceHistory queries current clearing price and snapshot history', async () => {
  const repo = createMockRepository((sql, params) => {
    if (sql.includes('FROM market_prices WHERE product = $1')) {
      return { rows: [{ price: '12.50', supply: '500', demand: '450' }] };
    }
    if (sql.includes('FROM rankings_snapshots WHERE ranking_type = $1')) {
      return {
        rows: [
          { game_day: 105, price: '12.50' },
          { game_day: 104, price: '12.00' },
        ],
      };
    }
    return { rows: [] };
  });

  const result = await listMarketPriceHistory(repo, 'material', 30);
  assert.equal(result.product, 'material');
  assert.equal(result.currentPrice, 12.5);
  assert.equal(result.supply, 500);
  assert.equal(result.demand, 450);
  assert.equal(result.history.length, 2);
  assert.equal(result.history[0].gameDay, 105);
});

test('proposeMerger validates balance and records tender offer', async () => {
  let createdProposal = null;
  const outboxEvents = [];
  const repo = createMockRepository((sql, params) => {
    if (sql.includes("FROM negotiated_contracts WHERE proposer_id = $1 AND correlation_id = $2")) {
      return { rows: [] };
    }
    if (sql.includes('SELECT id, owner_id, status FROM businesses WHERE id = $1')) {
      return { rows: [{ id: params[0], owner_id: 'H-BUYER', status: 'active' }] };
    }
    if (sql.includes('SELECT shares FROM business_shares WHERE business_id = $1')) {
      return { rows: [{ shares: '1000' }] };
    }
    if (sql.includes("FROM account_balances WHERE owner_id = $1 AND currency = 'CREDIT'")) {
      return { rows: [{ account_id: 'ACC-BUYER', balance: '50000.00' }] };
    }
    if (sql.includes("SELECT game_day FROM world_state WHERE id = 'WORLD'")) {
      return { rows: [{ game_day: 50 }] };
    }
    if (sql.includes('INSERT INTO negotiated_contracts')) {
      createdProposal = params[0];
      return { rows: [], rowCount: 1 };
    }
    if (sql.includes('INSERT INTO event_outbox')) {
      outboxEvents.push(params[1]);
      return { rows: [], rowCount: 1 };
    }
    return { rows: [], rowCount: 1 };
  });

  const result = await proposeMerger(repo, {
    acquirerId: 'H-BUYER',
    acquirerBusinessId: 'BIZ-ACQUIRER',
    targetBusinessId: 'BIZ-TARGET',
    pricePerShare: 20,
    correlationId: 'MERGER-PROPOSE-1',
  });

  assert.equal(result.ok, true);
  assert.ok(result.mergerId);
  assert.equal(result.terms.totalAmount, 20000);
  assert.equal(createdProposal, result.mergerId);
  assert.deepEqual(outboxEvents, ['business-merger-proposal:MERGER-PROPOSE-1']);
});

test('executeMerger transfers funds pro-rata and dissolves target', async () => {
  let transferredLedgerCount = 0;
  let targetDissolved = false;
  let assetsTransferred = false;
  const outboxEvents = [];

  const repo = createMockRepository((sql, params) => {
    if (sql.includes("FROM world_events WHERE event_type = 'business.merged'")) {
      return { rows: [] };
    }
    if (sql.includes('FROM negotiated_contracts WHERE id = $1')) {
      return {
        rows: [
          {
            id: 'MERGER-123',
            proposer_id: 'H-BUYER',
            counterparty_id: 'H-TARGET-OWNER',
            amount: '10000.00',
            status: 'proposed',
          },
        ],
      };
    }
    if (sql.includes('FROM merger_contracts WHERE contract_id = $1')) {
      return {
        rows: [
          {
            contract_id: 'MERGER-123',
            acquirer_business_id: 'BIZ-ACQUIRER',
            target_business_id: 'BIZ-TARGET',
            price_per_share: '10.00',
            total_shares: '1000',
            total_amount: '10000.00',
          },
        ],
      };
    }
    if (sql.includes("FROM account_balances WHERE owner_id = $1 AND currency = 'CREDIT'")) {
      return { rows: [{ account_id: `ACC-${params[0]}`, balance: '50000.00' }] };
    }
    if (sql.includes('FROM business_shares WHERE business_id = $1')) {
      return {
        rows: [
          { holder_id: 'H-TARGET-OWNER', shares: '600' },
          { holder_id: 'H-MINORITY', shares: '400' },
        ],
      };
    }
    if (sql.includes("SELECT game_day FROM world_state WHERE id = 'WORLD'")) {
      return { rows: [{ game_day: 50 }] };
    }
    if (sql.includes('earth_transfer_credits')) {
      transferredLedgerCount += 1;
      return { rows: [{ status: 'applied', ledger_id: params[0], amount: params[4], already_processed: false }] };
    }
    if (sql.includes('INSERT INTO ledger_entries')) {
      transferredLedgerCount += 1;
      return { rows: [], rowCount: 1 };
    }
    if (sql.includes('SELECT machine_id FROM business_assets WHERE business_id = $1')) {
      return { rows: [{ machine_id: 'MACH-1' }, { machine_id: 'MACH-2' }] };
    }
    if (sql.includes('UPDATE business_assets SET business_id = $1 WHERE business_id = $2')) {
      assetsTransferred = true;
      return { rows: [], rowCount: 2 };
    }
    if (sql.includes("UPDATE businesses SET status = 'bankrupt' WHERE id = $1")) {
      targetDissolved = true;
      return { rows: [], rowCount: 1 };
    }
    if (sql.includes('INSERT INTO event_outbox')) {
      outboxEvents.push(params[1]);
      return { rows: [], rowCount: 1 };
    }
    return { rows: [], rowCount: 1 };
  });

  const result = await executeMerger(repo, {
    callerId: 'H-TARGET-OWNER',
    mergerId: 'MERGER-123',
    correlationId: 'MERGER-EXEC-1',
  });

  assert.equal(result.ok, true);
  assert.equal(result.mergerId, 'MERGER-123');
  assert.equal(transferredLedgerCount, 2);
  assert.equal(assetsTransferred, false);
  assert.equal(targetDissolved, true);
  assert.deepEqual(outboxEvents, ['business-merger:MERGER-EXEC-1']);
});
