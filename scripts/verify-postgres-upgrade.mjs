import assert from 'node:assert/strict';
import { readFile, writeFile } from 'node:fs/promises';
import { Client } from 'pg';

const connectionString = process.env.DATABASE_URL;
if (!connectionString) throw new Error('DATABASE_URL is required; refusing to verify an implicit database target');
const snapshotPath = process.env.EARTH_UPGRADE_SNAPSHOT || '/tmp/earth-upgrade-snapshot.json';
const mode = process.argv.includes('--verify') ? 'verify' : 'snapshot';
const tables = {
  houses: 'houses', humans: 'humans', economicAccounts: 'economic_accounts', economicTransactions: 'economic_transactions',
  economicEntries: 'economic_entries', marketOrders: 'market_orders', marketFills: 'market_fills',
  buildings: 'buildings', researchProjects: 'corporation_research_projects', taxObligations: 'tax_obligations', taxRules: 'tax_rule_versions',
  budgetCommitments: 'institution_budget_commitments', deposits: 'bank_deposits', loans: 'bank_loans', proposals: 'proposals', outbox: 'event_outbox',
};

const client = new Client({ connectionString, application_name: 'earth-postgres-upgrade-verifier', connectionTimeoutMillis: 5000, query_timeout: 30000 });
await client.connect();
try {
  const counts = {};
  for (const [key, table] of Object.entries(tables)) {
    const result = await client.query(`SELECT COUNT(*)::bigint AS count FROM ${table}`);
    counts[key] = String(result.rows[0].count);
  }
  const totals = await client.query(`
    SELECT
      (SELECT COALESCE(SUM(balance_units), 0)::numeric FROM economic_accounts) AS economic_balance,
      (SELECT COALESCE(SUM(delta_units), 0)::numeric FROM economic_entries) AS economic_entry_delta,
      (SELECT COALESCE(SUM(quantity_units), 0)::numeric FROM market_orders) AS order_quantity,
      (SELECT COALESCE(SUM(quantity_units), 0)::numeric FROM market_fills) AS fill_quantity
  `);
  const migrations = await client.query('SELECT COALESCE(MAX(version), 0)::integer AS version FROM earth_schema_migrations');
  const current = { migrationVersion: Number(migrations.rows[0].version), counts, totals: Object.fromEntries(Object.entries(totals.rows[0]).map(([key, value]) => [key, String(value)])) };

  if (mode === 'snapshot') {
    await writeFile(snapshotPath, `${JSON.stringify(current, null, 2)}\n`);
    console.log(JSON.stringify({ ok: true, mode, snapshotPath, ...current }, null, 2));
  } else {
    const before = JSON.parse(await readFile(snapshotPath, 'utf8'));
    const failures = [];
    for (const key of Object.keys(tables)) if (current.counts[key] !== before.counts[key]) failures.push(`${key} count changed from ${before.counts[key]} to ${current.counts[key]}`);
    for (const key of Object.keys(current.totals)) if (current.totals[key] !== before.totals[key]) failures.push(`${key} total changed from ${before.totals[key]} to ${current.totals[key]}`);
    const result = { ok: failures.length === 0, mode, before, after: current, failures };
    console.log(JSON.stringify(result, null, 2));
    assert.equal(result.ok, true, failures.join('; '));
  }
} finally {
  await client.end();
}
