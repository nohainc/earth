import { Client } from 'pg';

const connectionString = process.env.DATABASE_URL;
if (!connectionString) throw new Error('DATABASE_URL is required');

const parsed = new URL(connectionString);
const usesSystemRoot = parsed.searchParams.get('sslrootcert') === 'system';
if (usesSystemRoot) {
  parsed.searchParams.delete('sslrootcert');
  parsed.searchParams.delete('sslmode');
}

const client = new Client({
  connectionString: parsed.toString(),
  ...(usesSystemRoot ? { ssl: { rejectUnauthorized: true } } : {}),
  application_name: 'earth-postgres-target-audit',
  connectionTimeoutMillis: 5000,
});

await client.connect();
try {
  const metadata = await client.query(`
    SELECT current_database() AS database,
           current_user AS user,
           inet_server_addr() AS host,
           inet_server_port() AS port,
           current_setting('server_version') AS server_version`);
  const migrations = await client.query(`
    SELECT version, name
    FROM earth_schema_migrations
    ORDER BY version DESC
    LIMIT 10`).catch(() => ({ rows: [] }));
  const tables = await client.query(`
    SELECT COUNT(*)::int AS count
    FROM pg_tables
    WHERE schemaname = 'public' AND tablename NOT LIKE 'pg_%'`);
  console.log(JSON.stringify({
    environment: process.env.EARTH_RESET_ENV ?? 'unspecified',
    ...metadata.rows[0],
    current_migration_version: migrations.rows[0]?.version ?? null,
    current_earth_table_count: tables.rows[0].count,
    migrations: migrations.rows,
  }, null, 2));
} finally {
  await client.end();
}
