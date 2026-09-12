import { Client } from 'pg';
import { readFile } from 'node:fs/promises';

const connectionString = process.env.DATABASE_URL;
if (!connectionString) throw new Error('DATABASE_URL is required; refusing to verify an implicit database target');
const manifest = JSON.parse(await readFile(new URL('../db/schema-manifest.json', import.meta.url), 'utf8'));

const parsedConnection = new URL(connectionString);
const usesSystemRoot = parsedConnection.searchParams.get('sslrootcert') === 'system';
if (usesSystemRoot) {
  parsedConnection.searchParams.delete('sslrootcert');
  parsedConnection.searchParams.delete('sslmode');
}
const client = new Client({
  connectionString: parsedConnection.toString(),
  ...(usesSystemRoot ? { ssl: { rejectUnauthorized: true } } : {}),
  connectionTimeoutMillis: 5000,
  query_timeout: 10000,
  application_name: 'earth-invariant-verifier',
});
await client.connect();
try {
  const checks = {};
  const invalidBalances = await client.query("SELECT COUNT(*)::integer AS count FROM account_balances WHERE balance < 0");
  const invalidLedger = await client.query("SELECT COUNT(*)::integer AS count FROM ledger_entries WHERE amount <= 0 OR debit_account = credit_account OR correlation_id IS NULL");
  const invalidOwnership = await client.query("SELECT COUNT(*)::integer AS count FROM ownership_events WHERE from_owner_id IS NOT NULL AND from_owner_id = to_owner_id");
  const pendingOutbox = await client.query("SELECT COUNT(*)::integer AS count FROM event_outbox WHERE processed_at IS NULL AND attempts > 20");
  const world = await client.query("SELECT COUNT(*)::integer AS count FROM world_state WHERE id = 'WORLD'");
  const migrations = await client.query('SELECT COUNT(*)::integer AS count, COALESCE(MAX(version), 0)::integer AS version FROM earth_schema_migrations');
  const detailed = await client.query('SELECT severity, check_name, invalid_count FROM earth_integrity_report_detailed() ORDER BY severity, check_name');
  const critical = Object.fromEntries(detailed.rows.filter((row) => row.severity === 'critical').map((row) => [row.check_name, Number(row.invalid_count)]));
  const warnings = Object.fromEntries(detailed.rows.filter((row) => row.severity === 'warning').map((row) => [row.check_name, Number(row.invalid_count)]));
  const expensive = Object.fromEntries(detailed.rows.filter((row) => row.severity === 'expensive').map((row) => [row.check_name, Number(row.invalid_count)]));

  checks.balancesNonNegative = Number(invalidBalances.rows[0].count) === 0;
  checks.ledgerEntriesValid = Number(invalidLedger.rows[0].count) === 0;
  checks.ownershipTransitionsValid = Number(invalidOwnership.rows[0].count) === 0;
  checks.outboxRetryPressureBounded = Number(pendingOutbox.rows[0].count) === 0;
  checks.singleWorldRow = Number(world.rows[0].count) === 1;
  checks.migrationsExact = Number(migrations.rows[0].version) === manifest.migrationVersion;
  checks.criticalInvariants = Object.values(critical).every((count) => count === 0);

  const result = {
    ok: Object.values(checks).every(Boolean),
    critical,
    warnings,
    expensive,
    checks,
    counts: {
      invalidBalances: Number(invalidBalances.rows[0].count),
      invalidLedger: Number(invalidLedger.rows[0].count),
      invalidOwnershipTransitions: Number(invalidOwnership.rows[0].count),
      outboxRetryPressure: Number(pendingOutbox.rows[0].count),
      migrations: Number(migrations.rows[0].count),
      migrationVersion: Number(migrations.rows[0].version),
    },
  };
  console.log(JSON.stringify(result, null, 2));
  if (!result.ok) process.exitCode = 1;
} finally {
  await client.end();
}
