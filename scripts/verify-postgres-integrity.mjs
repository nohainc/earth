import { Client } from 'pg';

const connectionString = process.env.DATABASE_URL;
if (!connectionString) throw new Error('DATABASE_URL is required; refusing to verify an implicit database target');

const client = new Client({ connectionString, application_name: 'earth-integrity-report', connectionTimeoutMillis: 5000, query_timeout: 30000 });
await client.connect();
try {
  const report = await client.query('SELECT check_name, invalid_count FROM earth_integrity_report() ORDER BY check_name');
  const checks = Object.fromEntries(report.rows.map((row) => [row.check_name, Number(row.invalid_count)]));
  const ownerRegistry = await client.query("SELECT COUNT(*)::integer AS count FROM owner_registry WHERE status = 'active'");
  const result = {
    ok: Object.values(checks).every((count) => count === 0) && Number(ownerRegistry.rows[0]?.count ?? 0) > 0,
    checks,
    activeOwnerRegistryEntries: Number(ownerRegistry.rows[0]?.count ?? 0),
  };
  console.log(JSON.stringify(result, null, 2));
  if (!result.ok) process.exitCode = 1;
} finally {
  await client.end();
}
