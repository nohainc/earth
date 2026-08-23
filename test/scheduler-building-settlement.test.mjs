import test from 'node:test';
import assert from 'node:assert/strict';
import { PostgresRepository } from '../cloudflare/src/repository.ts';
import {
  settleBuildingUpkeepAndRevenue,
  settleCivicDividends,
} from '../cloudflare/src/scheduler-postgres.ts';

class MockDbClient {
  constructor(handler) {
    this.handler = handler;
  }
  async query(sql, params = []) {
    return this.handler(sql, params);
  }
}

test('settleCivicDividends: only Credit outputs generate cash surplus and distribute 70/30 UBI', async () => {
  const executedTransfers = [];
  const insertedPayouts = [];

  const client = new MockDbClient((sql, params) => {
    if (sql.includes('SELECT id FROM cities')) {
      return { rows: [{ id: 'CITY-0084' }], rowCount: 1 };
    }
    if (sql.includes('SELECT id FROM civic_dividend_payouts WHERE city_id')) {
      return { rows: [], rowCount: 0 };
    }
    if (sql.includes('SELECT COALESCE(SUM(net_surplus_crd), 0) AS total_surplus FROM building_settlement_journals')) {
      // Proves that dividends are calculated strictly from recorded civic settlement journals
      assert.ok(sql.includes("ownership_class = 'civic'"));
      return { rows: [{ total_surplus: '1000' }], rowCount: 1 };
    }
    if (sql.includes('FROM memberships WHERE city_id')) {
      return {
        rows: [
          { human_id: 'H-001' },
          { human_id: 'H-002' },
        ],
        rowCount: 2,
      };
    }
    if (sql.includes('FROM ballots WHERE human_id')) {
      // H-001 has 3 ballots, H-002 has 0 ballots
      const count = params[0] === 'H-001' ? '3' : '0';
      return { rows: [{ count }], rowCount: 1 };
    }
    if (sql.includes('FROM account_balances WHERE account_id')) {
      return { rows: [{ account_id: 'account-city-CITY-0084', balance: '500000' }], rowCount: 1 };
    }
    if (sql.includes('FROM account_balances WHERE owner_id')) {
      return { rows: [{ account_id: `acc-${params[0]}` }], rowCount: 1 };
    }
    if (sql.includes('earth_transfer_credits')) {
      executedTransfers.push({
        debit: params[2],
        credit: params[3],
        amount: params[4],
        reason: params[5],
      });
      return { rows: [{ status: 'applied', ledger_id: 'LED-DIV', amount: params[4], already_processed: false }], rowCount: 1 };
    }
    if (sql.includes('INSERT INTO civic_dividend_payouts')) {
      insertedPayouts.push(params);
      return { rows: [], rowCount: 1 };
    }
    return { rows: [], rowCount: 0 };
  });

  const repo = new PostgresRepository(client);
  await settleCivicDividends(repo, 184);

  assert.equal(executedTransfers.length, 2);
  // Total surplus: 1000 CRD
  // 70% Base: 700 CRD / 2 residents = 350 CRD each
  // 30% Participation: 300 CRD.
  // H-001 score = 1 + 3 = 4, H-002 score = 1 + 0 = 1. Total score = 5.
  // H-001 gets 350 + (300 * 4/5) = 350 + 240 = 590 CRD (59000 cents)
  // H-002 gets 350 + (300 * 1/5) = 350 + 60 = 410 CRD (41000 cents)
  assert.equal(executedTransfers[0].credit, 'acc-H-001');
  assert.equal(executedTransfers[0].amount, '590.00');

  assert.equal(executedTransfers[1].credit, 'acc-H-002');
  assert.equal(executedTransfers[1].amount, '410.00');

  assert.equal(insertedPayouts.length, 1);
  assert.equal(insertedPayouts[0][1], 'CITY-0084');
  assert.equal(insertedPayouts[0][2], 184);
  assert.equal(insertedPayouts[0][3], 1000);
});

test('settleCivicDividends: duplicate city/day payouts are skipped idempotently', async () => {
  let transferCalled = false;

  const client = new MockDbClient((sql) => {
    if (sql.includes('SELECT id FROM cities')) {
      return { rows: [{ id: 'CITY-0084' }], rowCount: 1 };
    }
    if (sql.includes('SELECT id FROM civic_dividend_payouts WHERE city_id')) {
      // Prior payout exists
      return { rows: [{ id: 'PAYOUT-CITY-0084-184' }], rowCount: 1 };
    }
    if (sql.includes('earth_transfer_credits')) {
      transferCalled = true;
      return { rows: [{ status: 'applied' }], rowCount: 1 };
    }
    return { rows: [], rowCount: 0 };
  });

  const repo = new PostgresRepository(client);
  await settleCivicDividends(repo, 184);

  assert.equal(transferCalled, false);
});

test('settleBuildingUpkeepAndRevenue: public investment distributes pro-rata shares reliably', async () => {
  const transfers = [];
  const shareUpdates = [];

  const client = new MockDbClient((sql, params) => {
    if (sql.includes('SELECT id, name, city_id')) return { rows: [], rowCount: 0 };
    if (sql.includes("SELECT * FROM buildings WHERE status = 'active'")) {
      return {
        rows: [
          {
            id: 'BLD-PUB-01',
            owner_id: 'CITY-0084',
            city_id: 'CITY-0084',
            ownership_class: 'public_investment',
            business_id: null,
            operating_policy: 'balanced',
            condition: '100',
            resource_output_type: 'credits',
            resource_output_amount: '2000',
          },
        ],
        rowCount: 1,
      };
    }
    if (sql.includes('FROM building_investment_shares WHERE building_id')) {
      return {
        rows: [
          { investor_id: 'H-INV-1', shares_owned: 60, total_shares_issued: 100 },
          { investor_id: 'H-INV-2', shares_owned: 40, total_shares_issued: 100 },
        ],
        rowCount: 2,
      };
    }
    if (sql.includes('FROM account_balances WHERE owner_id')) {
      return { rows: [{ account_id: `acc-${params[0]}` }], rowCount: 1 };
    }
    if (sql.includes('earth_transfer_credits')) {
      transfers.push({
        debit: params[2],
        credit: params[3],
        amount: params[4],
        reason: params[5],
      });
      return { rows: [{ status: 'applied', ledger_id: 'LED-PUB', amount: params[4], already_processed: false }], rowCount: 1 };
    }
    if (sql.includes('UPDATE building_investment_shares')) {
      shareUpdates.push(params);
      return { rows: [], rowCount: 1 };
    }
    return { rows: [], rowCount: 0 };
  });

  const repo = new PostgresRepository(client);
  await settleBuildingUpkeepAndRevenue(repo, 184);

  // 2000 CRD total yield
  // H-INV-1 (60%): 1200 CRD
  // H-INV-2 (40%): 800 CRD
  assert.equal(transfers.length, 2);
  assert.equal(transfers[0].debit, 'account-market-clearing');
  assert.equal(transfers[0].credit, 'acc-H-INV-1');
  assert.equal(shareUpdates.length, 2);
  assert.equal(shareUpdates[0][0], 1200);
  assert.equal(shareUpdates[1][0], 800);
});

test('settleCivicDividends: non-credit civic facilities produce 0 cash dividend surplus', async () => {
  let transferCalled = false;

  const client = new MockDbClient((sql) => {
    if (sql.includes('SELECT id FROM cities')) {
      return { rows: [{ id: 'CITY-0084' }], rowCount: 1 };
    }
    if (sql.includes('SELECT id FROM civic_dividend_payouts WHERE city_id')) {
      return { rows: [], rowCount: 0 };
    }
    if (sql.includes('SELECT COALESCE(SUM(net_surplus_crd), 0) AS total_surplus FROM building_settlement_journals')) {
      // Non-credit outputs produce 0 cash surplus in settlement journals
      return { rows: [{ total_surplus: '0' }], rowCount: 1 };
    }
    if (sql.includes('earth_transfer_credits')) {
      transferCalled = true;
      return { rows: [{ status: 'applied' }], rowCount: 1 };
    }
    return { rows: [], rowCount: 0 };
  });

  const repo = new PostgresRepository(client);
  await settleCivicDividends(repo, 184);

  assert.equal(transferCalled, false);
});

test('settleBuildingUpkeepAndRevenue: failed ledger transfer aborts without updating dividends', async () => {
  let shareUpdateCalled = false;

  const client = new MockDbClient((sql) => {
    if (sql.includes('SELECT id, name, city_id')) return { rows: [], rowCount: 0 };
    if (sql.includes("SELECT * FROM buildings WHERE status = 'active'")) {
      return {
        rows: [
          {
            id: 'BLD-PUB-FAIL',
            owner_id: 'CITY-0084',
            city_id: 'CITY-0084',
            ownership_class: 'public_investment',
            business_id: null,
            operating_policy: 'balanced',
            condition: '100',
            resource_output_type: 'credits',
            resource_output_amount: '1000',
          },
        ],
        rowCount: 1,
      };
    }
    if (sql.includes('FROM building_investment_shares WHERE building_id')) {
      return {
        rows: [{ investor_id: 'H-INV-1', shares_owned: 100, total_shares_issued: 100 }],
        rowCount: 1,
      };
    }
    if (sql.includes('FROM account_balances WHERE owner_id')) {
      return { rows: [{ account_id: 'acc-H-INV-1', balance: '50000' }], rowCount: 1 };
    }
    if (sql.includes('earth_transfer_credits')) {
      throw new Error('Ledger transfer failed: insufficient city treasury');
    }
    if (sql.includes('UPDATE building_investment_shares')) {
      shareUpdateCalled = true;
      return { rows: [], rowCount: 1 };
    }
    return { rows: [], rowCount: 0 };
  });

  const repo = new PostgresRepository(client);
  await assert.rejects(
    async () => settleBuildingUpkeepAndRevenue(repo, 184),
    /Ledger transfer failed/,
  );

  assert.equal(shareUpdateCalled, false);
});

test('advanceBuildingConstruction: activates completed facilities and updates progress', async () => {
  const updatedStatus = [];
  const progressUpdates = [];

  const client = new MockDbClient((sql, params) => {
    if (sql.includes("SELECT id, name, city_id, owner_id, construction_started_game_day, construction_complete_game_day FROM buildings WHERE status = 'under_construction'")) {
      return {
        rows: [
          {
            id: 'BLD-DONE',
            name: 'Completed Core',
            city_id: 'CITY-0084',
            owner_id: 'H-001',
            construction_started_game_day: 180,
            construction_complete_game_day: 184,
          },
          {
            id: 'BLD-INPROG',
            name: 'Midway Tower',
            city_id: 'CITY-0084',
            owner_id: 'H-002',
            construction_started_game_day: 182,
            construction_complete_game_day: 186,
          },
        ],
        rowCount: 2,
      };
    }
    if (sql.includes("UPDATE buildings SET status = 'active'")) {
      updatedStatus.push(params[0]);
      return { rows: [], rowCount: 1 };
    }
    if (sql.includes('UPDATE buildings SET construction_progress')) {
      progressUpdates.push({ id: params[1], progress: params[0] });
      return { rows: [], rowCount: 1 };
    }
    if (sql.includes("SELECT * FROM buildings WHERE status = 'active'")) {
      return { rows: [], rowCount: 0 };
    }
    return { rows: [], rowCount: 0 };
  });

  const repo = new PostgresRepository(client);
  await settleBuildingUpkeepAndRevenue(repo, 184);

  assert.equal(updatedStatus.length, 1);
  assert.equal(updatedStatus[0], 'BLD-DONE');

  assert.equal(progressUpdates.length, 1);
  assert.equal(progressUpdates[0].id, 'BLD-INPROG');
  // Started 182, completes 186 (4 days total), at day 184 (2 days elapsed) -> 50%
  assert.equal(progressUpdates[0].progress, 50.0);
});

test('settleBuildingUpkeepAndRevenue: debits daily operating credits and executes auto-repair', async () => {
  const transfers = [];
  const resourceDeductions = [];

  const client = new MockDbClient((sql, params) => {
    if (sql.includes("SELECT id, name, city_id")) return { rows: [], rowCount: 0 };
    if (sql.includes("SELECT * FROM buildings WHERE status = 'active'")) {
      return {
        rows: [
          {
            id: 'BLD-COMM-01',
            owner_id: 'H-001',
            city_id: 'CITY-0084',
            ownership_class: 'private',
            business_id: null,
            operating_policy: 'balanced',
            condition: '70', // Condition < 80 triggers auto-repair
            auto_repair_enabled: true,
            daily_operating_credits: '50',
            resource_output_type: 'credits',
            resource_output_amount: '500',
          },
        ],
        rowCount: 1,
      };
    }
    if (sql.includes("FROM resource_balances WHERE owner_id = $1 AND resource = $2")) {
      // 10 components available
      return { rows: [{ amount: '10' }], rowCount: 1 };
    }
    if (sql.includes("FROM account_balances WHERE owner_id = $1 AND currency = 'CREDIT'")) {
      return { rows: [{ account_id: 'acc-H-001', balance: '20000' }], rowCount: 1 };
    }
    if (sql.includes("earth_transfer_credits")) {
      transfers.push({
        debit: params[2],
        credit: params[3],
        amount: params[4],
        reason: params[5],
      });
      return { rows: [{ status: 'applied', ledger_id: 'LED-OP', amount: params[4], already_processed: false }], rowCount: 1 };
    }
    if (sql.includes("UPDATE resource_balances SET amount = amount - 1")) {
      resourceDeductions.push(params);
      return { rows: [], rowCount: 1 };
    }
    return { rows: [], rowCount: 0 };
  });

  const repo = new PostgresRepository(client);
  await settleBuildingUpkeepAndRevenue(repo, 184);

  // Auto repair deducted 1 component
  assert.equal(resourceDeductions.length, 1);
  assert.equal(resourceDeductions[0][0], 'H-001');
  assert.equal(resourceDeductions[0][1], 'components');

  // Operating costs debited 50 CRD, then output credited 500 CRD
  assert.equal(transfers.length, 2);
  assert.equal(transfers[0].reason, 'building_operating_cost');
  assert.equal(transfers[0].debit, 'acc-H-001');
  assert.equal(transfers[0].credit, 'account-city-operations-CITY-0084');
  assert.equal(transfers[0].amount, '50.00');

  assert.equal(transfers[1].reason, 'building_commercial_revenue');
  assert.equal(transfers[1].debit, 'account-market-clearing');
  assert.equal(transfers[1].credit, 'acc-H-001');
  assert.equal(transfers[1].amount, '500.00');
});


