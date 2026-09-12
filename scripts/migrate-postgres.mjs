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

  const allowRepair = process.argv.includes('--repair');
  if (allowRepair && process.env.NODE_ENV === 'production') {
    throw new Error('Migration repair is unavailable in production; use a forward migration');
  }

  for (const migration of migrationsToApply) {
    const { name, sql } = migration;
    const version = Number(name.slice(0, name.indexOf('_')));
    const checksum = createHash('sha256').update(sql).digest('hex');
    const existing = await client.query('select name, checksum from earth_schema_migrations where version = $1', [version]);
    if (existing.rowCount) {
      if (existing.rows[0].name !== name || existing.rows[0].checksum !== checksum) {
        if (allowRepair) {
          console.warn(`Repairing migration ${name} with updated checksum...`);
          await client.query('begin');
          try {
            await client.query(sql);
            await client.query(
              'update earth_schema_migrations set name = $1, checksum = $2, applied_at = now() where version = $3',
              [name, checksum, version],
            );
            await client.query('commit');
            console.log(`Repaired and re-applied ${name}`);
            continue;
          } catch (error) {
            await client.query('rollback');
            throw error;
          }
        }
        throw new Error(`Migration ${name} differs from the applied checksum; create a new migration or run with --repair`);
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
  console.log(JSON.stringify({ ok: true, migrations: result.rows }, null, 2));
} finally {
  await client.query('SELECT pg_advisory_unlock(hashtext($1))', ['earth-schema-migrations']).catch(() => undefined);
  await client.end();
}
