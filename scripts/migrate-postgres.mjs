import { createHash } from 'node:crypto';
import { readdir, readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { Client } from 'pg';

const connectionString = process.env.DATABASE_URL;
if (!connectionString) {
  throw new Error('DATABASE_URL is required; refusing to run a migration without an explicit database target');
}

const migrationDirectory = new URL('../db/migrations/', import.meta.url);
const names = (await readdir(migrationDirectory))
  .filter((name) => /^\d+_.+\.sql$/.test(name))
  .sort((a, b) => Number(a.match(/^\d+/)[0]) - Number(b.match(/^\d+/)[0]));
const activeMigrations = [];
for (const name of names) {
  const sql = await readFile(join(migrationDirectory.pathname, name), 'utf8');
  if (sql.includes('-- EARTH ACTIVE MIGRATION:')) activeMigrations.push({ name, sql });
}
const migrationTarget = process.env.MIGRATION_TARGET_VERSION ? Number(process.env.MIGRATION_TARGET_VERSION) : null;
if (migrationTarget !== null && (!Number.isInteger(migrationTarget) || migrationTarget < 1)) {
  throw new Error('MIGRATION_TARGET_VERSION must be a positive integer');
}
const migrationsToApply = migrationTarget === null
  ? activeMigrations
  : activeMigrations.filter(({ name }) => Number(name.slice(0, name.indexOf('_'))) <= migrationTarget);
const activeVersions = activeMigrations.map(({ name }) => Number(name.slice(0, name.indexOf('_'))));
for (let index = 1; index < activeVersions.length; index += 1) {
  if (activeVersions[index] !== activeVersions[index - 1] + 1) {
    throw new Error(`Active migration sequence is not contiguous at versions ${activeVersions[index - 1]} and ${activeVersions[index]}`);
  }
}
const parsedConnection = new URL(connectionString);
const usesSystemRoot = parsedConnection.searchParams.get('sslrootcert') === 'system';
if (usesSystemRoot) {
  parsedConnection.searchParams.delete('sslrootcert');
  parsedConnection.searchParams.delete('sslmode');
}
const client = new Client({
  connectionString: parsedConnection.toString(),
  ...(usesSystemRoot ? { ssl: { rejectUnauthorized: true } } : {}),
  application_name: 'earth-world-migrator',
  connectionTimeoutMillis: 5000,
  query_timeout: 30000,
  statement_timeout: 30000,
});

await client.connect();
await client.query('SELECT pg_advisory_lock(hashtext($1))', ['earth-schema-migrations']);
try {
  await client.query(`
    create table if not exists earth_schema_migrations (
      version integer primary key,
      name text not null,
      applied_at timestamptz not null default now(),
      checksum text not null
    )
  `);

  if (process.argv.includes('--repair')) {
    throw new Error('Migration repair is permanently unavailable; applied migrations are immutable, use a forward migration');
  }

  for (const migration of migrationsToApply) {
    const { name, sql } = migration;
    const version = Number(name.slice(0, name.indexOf('_')));
    const checksum = createHash('sha256').update(sql).digest('hex');
    const existing = await client.query('select name, checksum from earth_schema_migrations where version = $1', [version]);
    if (existing.rowCount) {
      if (existing.rows[0].name !== name || existing.rows[0].checksum !== checksum) {
        throw new Error(`Migration ${name} differs from the applied checksum; applied migrations are immutable, create a new forward migration`);
      }
      continue;
    }

    await client.query('begin');
    try {
      await client.query(sql);
      await client.query(
        'insert into earth_schema_migrations (version, name, checksum) values ($1, $2, $3)',
        [version, name, checksum],
      );
      await client.query('commit');
      console.log(`Applied ${name}`);
    } catch (error) {
      await client.query('rollback');
      throw error;
    }
  }

  const result = await client.query('select version, name, applied_at from earth_schema_migrations order by version');
  const appliedVersions = result.rows.map(({ version }) => Number(version));
  for (let index = 0; index < appliedVersions.length; index += 1) {
    const expected = index + 1;
    if (appliedVersions[index] !== expected) {
      throw new Error(`Applied migration history is not contiguous: expected version ${expected}, found ${appliedVersions[index]}`);
    }
  }
  const appliedNames = new Set(result.rows.map(({ name }) => name));
  const knownNames = new Set(activeMigrations.map(({ name }) => name));
  for (const name of appliedNames) {
    if (!knownNames.has(name)) throw new Error(`Applied migration ${name} is not present as an active repository migration`);
  }
  console.log(JSON.stringify({ ok: true, migrations: result.rows }, null, 2));
} finally {
  await client.query('SELECT pg_advisory_unlock(hashtext($1))', ['earth-schema-migrations']).catch(() => undefined);
  await client.end();
}
