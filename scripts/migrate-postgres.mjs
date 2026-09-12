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
const migrationTarget = process.env.MIGRATION_TARGET_VERSION ? Number(process.env.MIGRATION_TARGET_VERSION) : null;
if (migrationTarget !== null && (!Number.isInteger(migrationTarget) || migrationTarget < 1)) {
  throw new Error('MIGRATION_TARGET_VERSION must be a positive integer');
}
const migrationsToApply = migrationTarget === null
  ? names
  : names.filter((name) => Number(name.slice(0, name.indexOf('_'))) <= migrationTarget);
// These checksums identify historical migrations that were applied before the
// canonical files were restored. Reconcile metadata only; never rerun them.
const knownAppliedLegacyChecksums = new Map([
  [82, new Set(['a2823b34c6fcb946d18074df75693f9894bdf3839feeab85200d845ffc69ad15'])],
  [83, new Set(['5eddbfba8cb5e96eb21ca627250de3d825e97e789d678bd6891553c58241fcb9'])],
  [98, new Set(['e2718362ed4075091ac45a3256ccd83c68c37aa46cd2ddbab723383111c3a70a'])],
  [104, new Set(['bbbc3dbec5fef0860aafb8a7433e1ad7d302c1ea0babe28cf0945ce666985bf2'])],
  [165, new Set(['3ef8532f4d388cc44dd9c943457c5be1982f4e3c45c85366922334ed8ad4b624'])],
  [175, new Set(['5d34bf37ff2795c5653ee469526585c0d5132e2d2bf9a8cf7236aa50a4c863a9'])],
  [176, new Set(['bb7fa54e36f71f91660ed0119ee3ac00e11e7ce32263979900d4e900645fefa9'])],
  [197, new Set(['14053cd25fd295c33a5756cef21d17e9610ff2bbb084c8e80cf93732922c6d10'])],
  [200, new Set(['ea2ab11333adccab19f1a01f05b91610ecc8d949480f4ff5e966794340ec2b56'])],
  [211, new Set(['a2828e65b462e3f21fd8e7d7e33ec8ad6d4d9b19f82f2c4bf5750d3c114bb58b'])],
  [220, new Set(['a694e9b4507b4fdefda0dcdc2d1216d978782166aedb7ec693af0f9e08c13765'])],
  [249, new Set(['1f1aa58c514906faed759925ca0e50a20fb7973490aa9be9f16b786579738628'])],
  [293, new Set(['a92717bfcbac2684e4c834c0ab3375a6fee78ad8b1b45768d000780532e9d313'])],
  [294, new Set(['05bcd2d72cdd922991df78e24eedf7359e5ea29734228daf1867bdd636299ba2'])],
  [296, new Set(['3437496b26af0e3f97fc26bdda56d71b517ce5d4fb664ab010aaf935a3e3426c'])],
  [315, new Set(['e76eb173bb4e65c5088575363fd9ce33827303f2fbe5c25572fd849493c9e135'])],
  [318, new Set(['a9be67822dd525e6757617d838891e12f8fc12f2fbe80fd32b6a5e07b0d08be3'])],
  [319, new Set(['8f80792dfb8a7c59d6ced9ac80c294b3677c01376914d9f435f38c0ab26ed180'])],
  [340, new Set(['c3f74ed6cb172c1b5a0b03bc83cf53f4b805a48fcdf0bba871457a5f8e2dfe82'])],
  [349, new Set(['7efd8937a9e19556f766bf839bc3ab62f2efc9dd310b74dbd5fd44efd5d0bfc3'])],
  [213, new Set(['b22f2c33905aef30c4d8aa30bc7566d58014bb0293fd684279b31856719a8090'])],
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

  const allowRepair = process.env.ALLOW_MIGRATION_REPAIR === 'true' || process.argv.includes('--repair');

  for (const name of migrationsToApply) {
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
  await client.query('SELECT pg_advisory_unlock(hashtext($1))', ['earth-schema-migrations']).catch(() => undefined);
  await client.end();
}
