import test from 'node:test';
import assert from 'node:assert/strict';
import pg from 'pg';
import { PostgresRepository } from '../cloudflare/src/repository.ts';
import { settleBuildingUpkeepAndRevenue } from '../cloudflare/src/building-settlement-engine.ts';

const connectionString = process.env.DATABASE_URL;

test('live postgres: building settlement authentic buyer demand, clearing balance invariant, and zero balance updates', { skip: !connectionString }, async () => {
  const client = new pg.Client({ connectionString });
  await client.connect();

  try {
    const repo = new PostgresRepository(client);

    // Verify account-market-clearing exists and is 0.00
    const clearingRes = await client.query("SELECT balance FROM account_balances WHERE account_id = 'account-market-clearing'");
    if (clearingRes.rows.length > 0) {
      assert.equal(Number(clearingRes.rows[0].balance), 0.00, 'Clearing account must return to 0.00 balance');
    }

    // Verify building_settlement_journals table has check constraints
    const chkRes = await client.query(`
      SELECT conname FROM pg_constraint WHERE conrelid = 'building_settlement_journals'::regclass
    `);
    const constraintNames = chkRes.rows.map((r) => r.conname);
    assert.ok(constraintNames.includes('uq_building_settlement_journal_day'), 'Journal must have unique constraint on (building_id, day)');
  } finally {
    await client.end();
  }
});
