import { readFile } from 'node:fs/promises';
import { Client } from 'pg';

const connectionString = process.env.DATABASE_URL;
const exportPath = process.env.D1_EXPORT;
if (!connectionString || !exportPath) throw new Error('DATABASE_URL and D1_EXPORT are required');

const parsedConnection = new URL(connectionString);
const usesSystemRoot = parsedConnection.searchParams.get('sslrootcert') === 'system';
if (usesSystemRoot) {
  parsedConnection.searchParams.delete('sslrootcert');
  parsedConnection.searchParams.delete('sslmode');
}

const d1Counts = new Map();
for (const line of (await readFile(exportPath, 'utf8')).split('\n')) {
  const match = line.match(/^INSERT INTO "([^"]+)"/);
  if (match && !['d1_migrations', 'sqlite_sequence'].includes(match[1])) d1Counts.set(match[1], (d1Counts.get(match[1]) ?? 0) + 1);
}

const client = new Client({
  connectionString: parsedConnection.toString(),
  ...(usesSystemRoot ? { ssl: { rejectUnauthorized: true } } : {}),
  application_name: 'earth-world-d1-postgres-verifier',
  connectionTimeoutMillis: 5000,
  query_timeout: 30000,
  statement_timeout: 30000,
});
await client.connect();
try {
  const mismatches = [];
  const counts = {};
  for (const [table, expected] of d1Counts) {
    const result = await client.query(`select count(*)::integer as count from "${table}"`);
    const actual = result.rows[0].count;
    counts[table] = { d1: expected, postgres: actual };
    if (actual !== expected) mismatches.push({ table, d1: expected, postgres: actual });
  }
  const invariants = {
    nonNegativeBalances: (await client.query('select count(*)::integer as invalid from account_balances where balance < 0')).rows[0].invalid === 0,
    boundedMachines: (await client.query('select count(*)::integer as invalid from machines where condition < 0 or condition > 100')).rows[0].invalid === 0,
    positiveLedger: (await client.query('select count(*)::integer as invalid from ledger_entries where amount <= 0')).rows[0].invalid === 0,
    migrationVersion: (await client.query('select max(version)::integer as version from earth_schema_migrations')).rows[0].version === 4,
  };
  const result = { ok: mismatches.length === 0 && Object.values(invariants).every(Boolean), mismatches, invariants, tables: counts };
  console.log(JSON.stringify(result, null, 2));
  if (!result.ok) process.exitCode = 1;
} finally {
  await client.end();
}
