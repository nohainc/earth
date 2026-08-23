import test from 'node:test';
import assert from 'node:assert/strict';
import { PostgresRepository } from '../cloudflare/src/repository.ts';
import {
  advanceBuildingConstruction,
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
    if (sql.includes('FROM memberships WHERE city_id')) {
      return {
        rows: [{ human_id: 'H-RES-01' }, { human_id: 'H-RES-02' }],
        rowCount: 2,
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
    if (sql.includes("FROM account_balances WHERE owner_id = $1 AND currency = 'CREDIT'")) {
      return { rows: [{ account_id: `acc-${params[0]}`, balance: '50000' }], rowCount: 1 };
    }
    if (sql.includes('FROM account_balances WHERE account_id')) {
      return { rows: [{ account_id: 'account-city-operations-CITY-0084', balance: '50000' }], rowCount: 1 };
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

  // Total 4 authentic double-entry transfers:
  // 1. Resident 1 customer purchase: acc-H-RES-01 -> account-market-clearing (1000 CRD)
  // 2. Resident 2 customer purchase: acc-H-RES-02 -> account-market-clearing (1000 CRD)
  // 3. Shareholder 1 dividend: account-market-clearing -> acc-H-INV-1 (1200 CRD)
  // 4. Shareholder 2 dividend: account-market-clearing -> acc-H-INV-2 (800 CRD)
  assert.equal(transfers.length, 4);
  assert.equal(transfers[0].reason, 'consumer_commercial_purchase');
  assert.equal(transfers[0].debit, 'acc-H-RES-01');
  assert.equal(transfers[0].credit, 'account-market-clearing');
  assert.equal(transfers[0].amount, '1000.00');

  assert.equal(transfers[1].reason, 'consumer_commercial_purchase');
  assert.equal(transfers[1].debit, 'acc-H-RES-02');
  assert.equal(transfers[1].credit, 'account-market-clearing');
  assert.equal(transfers[1].amount, '1000.00');

  assert.equal(transfers[2].reason, 'public_share_dividend');
  assert.equal(transfers[2].debit, 'account-market-clearing');
  assert.equal(transfers[2].credit, 'acc-H-INV-1');
  assert.equal(transfers[2].amount, '1200.00');

  assert.equal(transfers[3].reason, 'public_share_dividend');
  assert.equal(transfers[3].debit, 'account-market-clearing');
  assert.equal(transfers[3].credit, 'acc-H-INV-2');
  assert.equal(transfers[3].amount, '800.00');

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
    if (sql.includes('FROM memberships WHERE city_id')) {
      return { rows: [{ human_id: 'H-RES-01' }], rowCount: 1 };
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
      throw new Error('Ledger transfer failed: insufficient customer balance');
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
  const updatedBuildings = [];
  const insertedEvents = [];

  const client = new MockDbClient((sql, params) => {
    if (sql.includes("SELECT id, name, city_id, owner_id, construction_started_game_day, construction_complete_game_day FROM buildings WHERE status = 'under_construction'")) {
      return {
        rows: [
          {
            id: 'BLD-NEW-01',
            name: 'Solar Plant',
            city_id: 'CITY-0084',
            owner_id: 'H-001',
            construction_started_game_day: 180,
            construction_complete_game_day: 184, // Completes on day 184
          },
          {
            id: 'BLD-NEW-02',
            name: 'Hydroponics Lab',
            city_id: 'CITY-0084',
            owner_id: 'H-002',
            construction_started_game_day: 182,
            construction_complete_game_day: 186, // In-progress on day 184 (50%)
          },
        ],
        rowCount: 2,
      };
    }
    if (sql.includes("UPDATE buildings SET status = 'active'")) {
      updatedBuildings.push({ id: params[0], status: 'active' });
      return { rows: [], rowCount: 1 };
    }
    if (sql.includes('UPDATE buildings SET construction_progress')) {
      updatedBuildings.push({ id: params[1], progress: params[0] });
      return { rows: [], rowCount: 1 };
    }
    if (sql.includes('INSERT INTO world_events')) {
      insertedEvents.push(params);
      return { rows: [], rowCount: 1 };
    }
    return { rows: [], rowCount: 0 };
  });

  const repo = new PostgresRepository(client);
  await advanceBuildingConstruction(repo, 184);

  assert.equal(updatedBuildings.length, 2);
  assert.equal(updatedBuildings[0].id, 'BLD-NEW-01');
  assert.equal(updatedBuildings[0].status, 'active');

  assert.equal(updatedBuildings[1].id, 'BLD-NEW-02');
  assert.equal(updatedBuildings[1].progress, 50.0);

  assert.equal(insertedEvents.length, 1);
  assert.equal(insertedEvents[0][0], 'BLD-CONSTRUCTED-BLD-NEW-01-184');
});

test('settleBuildingUpkeepAndRevenue: debits daily operating credits and executes auto-repair', async () => {
  const transfers = [];
  const resourceDeductions = [];

  const client = new MockDbClient((sql, params) => {
    if (sql.includes('SELECT id, name, city_id')) return { rows: [], rowCount: 0 };
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
    if (sql.includes("FROM memberships WHERE city_id")) {
      return {
        rows: [{ human_id: 'H-RES-02' }],
        rowCount: 1,
      };
    }
    if (sql.includes("FROM resource_balances WHERE owner_id = $1 AND resource = $2")) {
      // 10 components available
      return { rows: [{ amount: '10' }], rowCount: 1 };
    }
    if (sql.includes("FROM account_balances WHERE owner_id = $1 AND currency = 'CREDIT'")) {
      return { rows: [{ account_id: `acc-${params[0]}`, balance: '20000' }], rowCount: 1 };
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

  // 3 Double-entry transfers:
  // 1. Operating fee: acc-H-001 -> account-city-operations-CITY-0084 (50 CRD)
  // 2. Real resident customer purchase: acc-H-RES-02 -> account-market-clearing (500 CRD)
  // 3. Commercial revenue: account-market-clearing -> acc-H-001 (500 CRD)
  assert.equal(transfers.length, 3);
  assert.equal(transfers[0].reason, 'building_operating_cost');
  assert.equal(transfers[0].debit, 'acc-H-001');
  assert.equal(transfers[0].credit, 'account-city-operations-CITY-0084');
  assert.equal(transfers[0].amount, '50.00');

  assert.equal(transfers[1].reason, 'consumer_service_purchase');
  assert.equal(transfers[1].debit, 'acc-H-RES-02');
  assert.equal(transfers[1].credit, 'account-market-clearing');
  assert.equal(transfers[1].amount, '500.00');

  assert.equal(transfers[2].reason, 'building_commercial_revenue');
  assert.equal(transfers[2].debit, 'account-market-clearing');
  assert.equal(transfers[2].credit, 'acc-H-001');
  assert.equal(transfers[2].amount, '500.00');
});

test('settleBuildingUpkeepAndRevenue: double-entry reconciliation verifies clearing inflows match payouts exactly', async () => {
  const ledgerInflows = [];
  const ledgerOutflows = [];
  const journals = [];

  const client = new MockDbClient((sql, params) => {
    if (sql.includes('SELECT id, name, city_id')) return { rows: [], rowCount: 0 };
    if (sql.includes("SELECT * FROM buildings WHERE status = 'active'")) {
      return {
        rows: [
          {
            id: 'BLD-CIVIC-01',
            owner_id: 'CITY-0084',
            city_id: 'CITY-0084',
            ownership_class: 'civic',
            business_id: null,
            operating_policy: 'balanced',
            condition: '100',
            daily_operating_credits: '100',
            resource_output_type: 'credits',
            resource_output_amount: '1200',
          },
        ],
        rowCount: 1,
      };
    }
    if (sql.includes("FROM memberships WHERE city_id")) {
      return { rows: [{ human_id: 'H-RES-01' }], rowCount: 1 };
    }
    if (sql.includes("FROM account_balances WHERE owner_id = $1 AND currency = 'CREDIT'")) {
      return { rows: [{ account_id: 'acc-H-RES-01', balance: '100000' }], rowCount: 1 };
    }
    if (sql.includes("FROM account_balances WHERE account_id = $1")) {
      return { rows: [{ account_id: params[0], balance: '100000' }], rowCount: 1 };
    }
    if (sql.includes("earth_transfer_credits")) {
      const entry = { debit: params[2], credit: params[3], amount: params[4], reason: params[5] };
      if (entry.credit === 'account-market-clearing') {
        ledgerInflows.push(entry);
      }
      if (entry.debit === 'account-market-clearing') {
        ledgerOutflows.push(entry);
      }
      return { rows: [{ status: 'applied', ledger_id: 'LED-REC', amount: params[4], already_processed: false }], rowCount: 1 };
    }
    if (sql.includes("INSERT INTO building_settlement_journals")) {
      journals.push(params);
      return { rows: [], rowCount: 1 };
    }
    return { rows: [], rowCount: 0 };
  });

  const repo = new PostgresRepository(client);
  await settleBuildingUpkeepAndRevenue(repo, 184);

  // Reconciliation Assertions:
  assert.equal(ledgerInflows.length, 1);
  assert.equal(ledgerOutflows.length, 1);
  assert.equal(ledgerInflows[0].reason, 'municipal_utility_bill');
  assert.equal(ledgerInflows[0].debit, 'acc-H-RES-01');
  assert.equal(ledgerOutflows[0].reason, 'civic_utility_revenue');
  assert.equal(ledgerOutflows[0].credit, 'account-city-CITY-0084');
  assert.equal(ledgerInflows[0].amount, ledgerOutflows[0].amount);
  assert.equal(ledgerInflows[0].amount, '1200.00');

  // Journal Assertions:
  assert.equal(journals.length, 1);
  const grossRev = journals[0][5];
  const opCost = journals[0][6];
  const netSurplus = journals[0][7];
  assert.equal(grossRev, 1200);
  assert.equal(opCost, 100);
  assert.equal(netSurplus, 1100); // 1200 - 100
  assert.equal(netSurplus, grossRev - opCost);
});
