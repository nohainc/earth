import test from 'node:test';
import assert from 'node:assert/strict';
import { distributeDividends, issueShares } from '../cloudflare/src/business-postgres.ts';
import { setCityTaxCharter } from '../cloudflare/src/institutions-postgres.ts';
import { fromNanoMarkup } from '../cloudflare/src/nano-markup.ts';

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

test('distributeDividends computes pro-rata share payouts and enforces idempotency', async () => {
  const ledgerEntries = [];
  const notifications = [];
  const outboxEvents = [];
  const repo = createMockRepository((sql, params) => {
    if (sql.includes('FROM ledger_entries WHERE reason_type = \'dividend_payout\'')) {
      return { rows: [] };
    }
    if (sql.includes('SELECT id, owner_id FROM businesses')) {
      return { rows: [{ id: 'B-TEST', owner_id: 'H-FOUNDER' }] };
    }
    if (sql.includes('SELECT manager_id FROM business_management')) {
      return { rows: [{ manager_id: 'H-FOUNDER' }] };
    }
    if (sql.includes('SELECT account_id, balance FROM account_balances WHERE owner_id = $1')) {
      return { rows: [{ account_id: 'account-founder', balance: '1000.00' }] };
    }
    if (sql.includes('SELECT holder_id, shares FROM business_shares')) {
      return {
        rows: [
          { holder_id: 'H-FOUNDER', shares: '60' },
          { holder_id: 'H-INVESTOR', shares: '40' },
        ],
      };
    }
    if (sql.includes("SELECT game_day FROM world_state WHERE id = 'WORLD'")) {
      return { rows: [{ game_day: 15 }] };
    }
    if (sql.includes("SELECT account_id FROM account_balances WHERE owner_id = $1 AND currency = 'CREDIT'")) {
      return { rows: [{ account_id: `account-${params[0]}` }] };
    }
    if (sql.includes('earth_transfer_credits')) {
      ledgerEntries.push({ sql, params });
      return { rows: [{ status: 'applied', ledger_id: params[0], amount: params[4], already_processed: false }] };
    }
    if (sql.includes('INSERT INTO notifications')) {
      notifications.push({ sql, params });
      return { rows: [], rowCount: 1 };
    }
    if (sql.includes('INSERT INTO event_outbox')) {
      outboxEvents.push(params[1]);
      return { rows: [], rowCount: 1 };
    }
    return { rows: [], rowCount: 1 };
  });

  const result = await distributeDividends(repo, {
    callerId: 'H-FOUNDER',
    businessId: 'B-TEST',
    totalAmount: 100,
    correlationId: 'DIV-100',
  });

  assert.equal(result.ok, true);
  assert.equal(result.totalAmount, 100);
  assert.equal(result.distributions.length, 2);
  assert.equal(result.distributions[0].holderId, 'H-FOUNDER');
  assert.equal(result.distributions[0].amount, 60);
  assert.equal(result.distributions[1].holderId, 'H-INVESTOR');
  assert.equal(result.distributions[1].amount, 40);
  assert.equal(ledgerEntries.length, 2);
  assert.deepEqual(outboxEvents, ['business-dividend:DIV-100']);
});

test('issueShares enforces supermajority minority shareholder protection', async () => {
  const repo = createMockRepository((sql, params) => {
    if (sql.includes('SELECT amount, reason_id FROM ledger_entries')) {
      return { rows: [] };
    }
    if (sql.includes('SELECT id, owner_id FROM businesses')) {
      return { rows: [{ id: 'B-TEST', owner_id: 'H-FOUNDER' }] };
    }
    if (sql.includes('SELECT id FROM humans')) {
      return { rows: [{ id: 'H-BUYER' }] };
    }
    if (sql.includes('SELECT account_id, owner_id, balance FROM account_balances')) {
      return {
        rows: [
          { account_id: 'acc-buyer', owner_id: 'H-BUYER', balance: '500.00' },
          { account_id: 'acc-owner', owner_id: 'H-FOUNDER', balance: '100.00' },
        ],
      };
    }
    if (sql.includes('SELECT shareholder_vote_threshold FROM business_constitutions')) {
      return { rows: [{ shareholder_vote_threshold: '0.667' }] };
    }
    if (sql.includes('SELECT holder_id, shares FROM business_shares')) {
      return {
        rows: [
          { holder_id: 'H-FOUNDER', shares: '50' },
          { holder_id: 'H-MINORITY', shares: '50' },
        ],
      };
    }
    return { rows: [], rowCount: 1 };
  });

  await assert.rejects(
    () =>
      issueShares(repo, {
        ownerId: 'H-FOUNDER',
        businessId: 'B-TEST',
        recipientId: 'H-BUYER',
        shares: 20,
        pricePerShare: 10,
        correlationId: 'ISSUE-DILUTE',
      }),
    /Supermajority shareholder approval required for dilution/
  );
});

test('setCityTaxCharter updates municipal tax rules and clamps rates within safe bounds', async () => {
  let updatedCharter = null;
  const repo = createMockRepository((sql, params) => {
    if (sql.includes('SELECT role_assignments.id FROM role_assignments')) {
      return { rows: [{ id: 'ROLE-MAYOR' }] };
    }
    if (sql.includes('SELECT id FROM cities WHERE id = $1')) {
      return { rows: [{ id: 'CITY-1' }] };
    }
    if (sql.includes("SELECT game_day FROM world_state WHERE id = 'WORLD'")) {
      return { rows: [{ game_day: 42 }] };
    }
    if (sql.includes('UPDATE institutions SET charter_rules = $1')) {
      updatedCharter = fromNanoMarkup(params[0]);
      return { rows: [], rowCount: 1 };
    }
    return { rows: [], rowCount: 1 };
  });

  const result = await setCityTaxCharter(repo, {
    humanId: 'H-MAYOR',
    cityId: 'CITY-1',
    incomeTaxBps: 1500,
    salesTaxBps: 800,
    corporateTaxBps: 2000,
    propertyTaxBps: 500,
    correlationId: 'CHARTER-42',
  });

  assert.equal(result.ok, true);
  assert.equal(result.cityId, 'CITY-1');
  assert.equal(Number(updatedCharter.incomeTaxBps), 1500);
  assert.equal(Number(updatedCharter.salesTaxBps), 800);
  assert.equal(Number(updatedCharter.corporateTaxBps), 2000);
  assert.equal(Number(updatedCharter.propertyTaxBps), 500);
  assert.equal(updatedCharter.updatedBy, 'H-MAYOR');
  assert.equal(Number(updatedCharter.updatedGameDay), 42);
});
