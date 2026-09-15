import { createHash } from 'node:crypto';
import { readdir, readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { Client } from 'pg';

const connectionString = process.env.DATABASE_URL;
if (!connectionString) {
  throw new Error('DATABASE_URL is required; refusing to run a migration without an explicit database target');
}

const migrationDirectory = new URL('../db/migrations/', import.meta.url);
// A small set of migrations was expanded with additive compatibility bridges
// after some environments had already applied the earlier versions. Keep
// only those known historical fingerprints readable so environments can
// advance through forward migrations. Unknown checksum drift remains a hard
// failure; this is not a repair or checksum rewrite mechanism.
const approvedHistoricalChecksums = new Map([
  ['001_baseline.sql', new Set([
    'e2cfdb721f8367ce49a56c6679cdea63ce384b95ecf866923c499d804c0102a6',
    '7257e134835aced183eb02afbb82780c29170cbb0fded680f908e88001e2de57',
    'c4946ae53bbd774353c16533b2f27b6077ed3f5c8f91d22d23201b55fa14c857',
  ])],
  // Migration 004 was expanded before the legacy production bridge was
  // applied. Existing local databases may already contain the original
  // public-infrastructure constraint; preserve that record and continue with
  // later forward migrations.
  ['004_public_infrastructure_credit.sql', new Set([
    'e864fc948fd6b9f07bf9b08c659a6262a656f0d727e62fbb58394929ef8a4822',
  ])],
  ['005_architecture_integrity_report.sql', new Set([
    'fe632055188742f32218deede17e7b116d292a9f281b9daa2af99845d0bfa299',
  ])],
  ['026_organization_legacy_bridge.sql', new Set([
    '1558fff4f4d692778f8536d754128718aa585d4d0ab4f5d1c2e5aff26448aa33',
  ])],
  ['053_tax_authority_and_statement_traceability.sql', new Set([
    '2d67d9995d01017155532227ee03db34b04aadc48f4e75ce3b3220f370d94a34',
  ])],
]);
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
      const appliedName = existing.rows[0].name;
      const appliedChecksum = existing.rows[0].checksum;
      const isApprovedHistoricalChecksum = appliedName === name
        && approvedHistoricalChecksums.get(name)?.has(appliedChecksum);
      if (appliedName !== name || (appliedChecksum !== checksum && !isApprovedHistoricalChecksum)) {
        throw new Error(`Migration ${name} differs from the applied checksum; applied migrations are immutable, create a new forward migration`);
      }
      if (isApprovedHistoricalChecksum && appliedChecksum !== checksum) {
        console.warn(`Accepted approved historical checksum for ${name}; preserving the applied migration record and continuing forward`);
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
