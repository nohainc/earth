import test from 'node:test';
import assert from 'node:assert/strict';
import { Client } from 'pg';
import { PostgresRepository } from '../../cloudflare/src/repository.ts';
import { getTaxStatement } from '../../cloudflare/src/tax-statement-postgres.ts';
import { getNetWorthHistory, recordDailyNetWorthSnapshot } from '../../cloudflare/src/net-worth-postgres.ts';

const databaseUrl = process.env.DATABASE_URL || 'postgres://earth:earth_dev_only@localhost:5432/earth';
test('Page 12: Personal Finance, Taxation and Net Worth', async (t) => {
  const client = new Client({ connectionString: databaseUrl });
  await client.connect();
  const repository = new PostgresRepository(client);
  const principal = (await repository.query("SELECT id, house_id FROM humans WHERE status = 'active' ORDER BY id LIMIT 1")).rows[0];

  t.after(() => client.end());

  if (!principal) {
    t.skip('requires at least one active local test Human');
    return;
  }

  await t.test('tax statement is sourced from canonical V4 facts', async () => {
    const statement = await getTaxStatement(repository, principal.id);
    assert.equal(statement.generatedFrom, 'postgres-canonical-facts');
    assert.equal(statement.houseId, principal.house_id);
    assert.ok(Array.isArray(statement.activeRules));
    assert.ok(Array.isArray(statement.financialObligations));
    assert.ok(Array.isArray(statement.taxObligations));
  });

  await t.test('net-worth snapshot is idempotent for a game day', async () => {
    const first = await recordDailyNetWorthSnapshot(repository, principal.id, 14528);
    const second = await recordDailyNetWorthSnapshot(repository, principal.id, 14528);
    assert.equal(first.ok, true);
    assert.equal(second.ok, true);
    assert.equal(second.snapshot.game_day, 14528);
    assert.equal(second.snapshot.human_id, principal.id);
  });

  await t.test('net-worth history exposes a bounded canonical summary', async () => {
    const history = await getNetWorthHistory(client, principal.id);
    assert.equal(history.ok, true);
    assert.equal(history.humanId, principal.id);
    assert.ok(Array.isArray(history.snapshots));
    assert.ok(history.snapshots.length <= 60);
    assert.equal(typeof history.summary.currentNetWorth, 'number');
  });
});
