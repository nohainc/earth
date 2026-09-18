import { createHash } from 'node:crypto';
import { readFile, readdir } from 'node:fs/promises';
import { Client } from 'pg';

const connectionString = process.env.DATABASE_URL;
if (!connectionString) throw new Error('DATABASE_URL is required; refusing to infer a reset target');

const environment = process.env.EARTH_RESET_ENV;
const confirmations = { local: 'RESET_LOCAL_EARTH', remote: 'RESET_REMOTE_EARTH' };
if (!Object.hasOwn(confirmations, environment)) {
  throw new Error('EARTH_RESET_ENV must be exactly local or remote');
}
if (process.env.EARTH_ALLOW_DESTRUCTIVE_RESET !== 'true') {
  throw new Error('Refusing to reset: set EARTH_ALLOW_DESTRUCTIVE_RESET=true');
}
if (process.env.EARTH_CONFIRM_DATABASE_RESET !== confirmations[environment]) {
  throw new Error(`Refusing to reset: set EARTH_CONFIRM_DATABASE_RESET=${confirmations[environment]}`);
}
if (environment === 'remote' && process.env.EARTH_CONFIRM_WRITERS_STOPPED !== 'WRITERS_STOPPED') {
  throw new Error('Refusing remote reset: stop API/scheduler writers and set EARTH_CONFIRM_WRITERS_STOPPED=WRITERS_STOPPED');
}
if (environment === 'remote' && process.env.EARTH_MAINTENANCE_MODE !== 'true') {
  throw new Error('Refusing remote reset: enable deployed EARTH_MAINTENANCE_MODE=true before resetting');
}

const parsed = new URL(connectionString);
const localHosts = new Set(['localhost', '127.0.0.1', '::1']);
if (environment === 'local' && !localHosts.has(parsed.hostname)) {
  throw new Error(`Refusing local reset for non-local host ${parsed.hostname}`);
}
if (environment === 'remote' && localHosts.has(parsed.hostname)) {
  throw new Error(`Refusing remote reset for local host ${parsed.hostname}`);
}

const usesSystemRoot = parsed.searchParams.get('sslrootcert') === 'system';
if (usesSystemRoot) {
  parsed.searchParams.delete('sslrootcert');
  parsed.searchParams.delete('sslmode');
}

const baseline = await readFile(new URL('../db/migrations/001_baseline.sql', import.meta.url), 'utf8');
if (!baseline.includes('-- EARTH ACTIVE MIGRATION:')) {
  throw new Error('001_baseline.sql is not marked as an active EARTH migration');
}
const checksum = createHash('sha256').update(baseline).digest('hex');

const client = new Client({
  connectionString: parsed.toString(),
  ...(usesSystemRoot ? { ssl: { rejectUnauthorized: true } } : {}),
  application_name: 'earth-postgres-reset',
  connectionTimeoutMillis: 5000,
  query_timeout: 30000,
  statement_timeout: 30000,
});

await client.connect();
const lockKey = 'earth-schema-migrations';
try {
  await client.query('SELECT pg_advisory_lock(hashtext($1))', [lockKey]);

  const metadata = await client.query(`
    SELECT current_database() AS database,
           current_user AS current_user,
           current_setting('server_version') AS server_version,
           inet_server_port() AS server_port
  `);
  const tableCount = await client.query(`
    SELECT COUNT(*)::int AS count
    FROM pg_tables
    WHERE schemaname = 'public' AND tablename NOT LIKE 'pg_%'
  `);
  const migrations = await client.query(`
    SELECT version, name
    FROM earth_schema_migrations
    ORDER BY version DESC
  `).catch(() => ({ rows: [] }));
  const row = metadata.rows[0];

  console.log(JSON.stringify({
    environment,
    host: parsed.hostname,
    port: row.server_port,
    database: row.database,
    user: row.current_user,
    server_version: row.server_version,
    current_migration_version: migrations.rows[0]?.version ?? null,
    current_earth_table_count: tableCount.rows[0].count,
    migrations: migrations.rows,
  }, null, 2));

  // Drop the old object graph in its own transaction. Keeping the old
  // dependency locks while creating the replacement baseline can exceed
  // PostgreSQL's max_locks_per_transaction on a mature installation.
  await client.query('BEGIN');
  await client.query('DROP SCHEMA public CASCADE');
  await client.query('CREATE SCHEMA public');
  await client.query('GRANT ALL ON SCHEMA public TO PUBLIC');
  await client.query('COMMIT');

  const emptySchema = await client.query(`
    SELECT
      (SELECT COUNT(*)::int FROM pg_tables WHERE schemaname = 'public') AS tables,
      (SELECT COUNT(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'public') AS functions
  `);
  if (emptySchema.rows[0].tables !== 0 || emptySchema.rows[0].functions !== 0) {
    throw new Error(`Remote schema is not empty after reset: ${JSON.stringify(emptySchema.rows[0])}`);
  }

  await client.query('BEGIN');
  await client.query(`
    CREATE TABLE earth_schema_migrations (
      version INTEGER PRIMARY KEY,
      name TEXT NOT NULL,
      applied_at TIMESTAMPTZ NOT NULL DEFAULT now(),
      checksum TEXT NOT NULL
    )
  `);
  await client.query(baseline);
  await client.query(
    'INSERT INTO earth_schema_migrations (version, name, checksum) VALUES (1, $1, $2)',
    ['001_baseline.sql', checksum],
  );
  await client.query('COMMIT');

  // A reset must produce the same schema as a fresh canonical installation:
  // apply the immutable baseline, then every active forward migration.
  const migrationDirectory = new URL('../db/migrations/', import.meta.url);
  const forwardMigrations = [];
  for (const name of (await readdir(migrationDirectory)).sort((a, b) => Number(a.match(/^\d+/)?.[0] ?? 0) - Number(b.match(/^\d+/)?.[0] ?? 0))) {
    if (name === '001_baseline.sql' || !/^\d+_.+\.sql$/.test(name)) continue;
    const sql = await readFile(new URL(name, migrationDirectory), 'utf8');
    if (sql.includes('-- EARTH ACTIVE MIGRATION:')) forwardMigrations.push({ name, sql });
  }
  for (const migration of forwardMigrations) {
    const version = Number(migration.name.match(/^\d+/)?.[0]);
    const migrationChecksum = createHash('sha256').update(migration.sql).digest('hex');
    await client.query('BEGIN');
    try {
      await client.query(migration.sql);
      await client.query(
        'INSERT INTO earth_schema_migrations (version, name, checksum) VALUES ($1, $2, $3)',
        [version, migration.name, migrationChecksum],
      );
      await client.query('COMMIT');
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    }
  }

  const verification = await client.query('SELECT version, name, checksum FROM earth_schema_migrations ORDER BY version');
  const expectedVersion = 1 + forwardMigrations.length;
  if (verification.rowCount !== expectedVersion || verification.rows.at(-1)?.version !== expectedVersion || verification.rows[0]?.checksum !== checksum) {
    throw new Error(`Reset verification failed: expected canonical migration chain through ${expectedVersion}`);
  }
  console.log(JSON.stringify({ ok: true, reset: true, migrationVersion: expectedVersion, migration: '001_baseline.sql + active forward migrations' }));
} catch (error) {
  await client.query('ROLLBACK').catch(() => {});
  throw error;
} finally {
  await client.query('SELECT pg_advisory_unlock(hashtext($1))', [lockKey]).catch(() => {});
  await client.end();
}
