import { createHash } from 'node:crypto';
import { readdir, readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { Client } from 'pg';

const connectionString = process.env.DATABASE_URL;
if (!connectionString) {
  throw new Error('DATABASE_URL is required; refusing to run a migration without an explicit database target');
}

const migrationDirectory = new URL('../db/migrations/', import.meta.url);
const names = (await readdir(migrationDirectory)).filter((name) => /^\d+_.+\.sql$/.test(name)).sort();
// These checksums identify historical migrations that were applied before the
// canonical files were restored. Reconcile metadata only; never rerun them.
const knownAppliedLegacyChecksums = new Map([
  [82, new Set(['a2823b34c6fcb946d18074df75693f9894bdf3839feeab85200d845ffc69ad15'])],
  [83, new Set(['5eddbfba8cb5e96eb21ca627250de3d825e97e789d678bd6891553c58241fcb9'])],
  [98, new Set(['e2718362ed4075091ac45a3256ccd83c68c37aa46cd2ddbab723383111c3a70a'])],
  [104, new Set(['bbbc3dbec5fef0860aafb8a7433e1ad7d302c1ea0babe28cf0945ce666985bf2'])],
]);
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
try {
  await client.query(`
    create table if not exists earth_schema_migrations (
      version integer primary key,
      name text not null,
      applied_at timestamptz not null default now(),
      checksum text not null
    )
  `);

  const allowRepair = process.env.ALLOW_MIGRATION_REPAIR === 'true' || process.argv.includes('--repair');

  for (const name of names) {
    const version = Number(name.slice(0, name.indexOf('_')));
    const sql = await readFile(join(migrationDirectory.pathname, name), 'utf8');
    const checksum = createHash('sha256').update(sql).digest('hex');
    const existing = await client.query('select name, checksum from earth_schema_migrations where version = $1', [version]);
    if (existing.rowCount) {
      if (existing.rows[0].name !== name || existing.rows[0].checksum !== checksum) {
        if (existing.rows[0].name === name && knownAppliedLegacyChecksums.get(version)?.has(existing.rows[0].checksum)) {
          await client.query(
            'update earth_schema_migrations set checksum = $1 where version = $2',
            [checksum, version],
          );
          console.warn(`Reconciled legacy checksum for already-applied migration ${name}; SQL was not rerun.`);
          continue;
        }
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
  await client.end();
}
