import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { Client } from 'pg';

const connectionString = process.env.DATABASE_URL;
if (!connectionString) throw new Error('DATABASE_URL is required; refusing to inspect an implicit database target');

const manifest = JSON.parse(await readFile(new URL('../db/schema-manifest.json', import.meta.url), 'utf8'));
const client = new Client({ connectionString, application_name: 'earth-postgres-surface-verifier', connectionTimeoutMillis: 5000, query_timeout: 30000 });
await client.connect();

try {
  const tables = await client.query(`
    SELECT table_name, column_name
      FROM information_schema.columns
     WHERE table_schema = 'public'
  `);
  const presentColumns = new Set(tables.rows.map((row) => `${row.table_name}:${row.column_name}`));
  const missingColumns = Object.entries(manifest.requiredTables).flatMap(([table, columns]) =>
    columns.filter((column) => !presentColumns.has(`${table}:${column}`)).map((column) => `${table}.${column}`));

  const uniqueConstraints = await client.query(`
    SELECT tc.table_name, array_agg(kcu.column_name ORDER BY kcu.ordinal_position) AS columns
      FROM information_schema.table_constraints tc
      JOIN information_schema.key_column_usage kcu USING (constraint_catalog, constraint_schema, constraint_name, table_name)
     WHERE tc.table_schema = 'public' AND tc.constraint_type IN ('PRIMARY KEY', 'UNIQUE')
     GROUP BY tc.table_name, tc.constraint_name
  `);
  const presentUnique = new Set(uniqueConstraints.rows.map((row) => `${row.table_name}(${row.columns.join(',')})`));
  const missingUnique = manifest.requiredUniqueConstraints
    .filter(([table, ...columns]) => !presentUnique.has(`${table}(${columns.join(',')})`))
    .map(([table, ...columns]) => `${table}(${columns.join(',')})`);

  const indexes = await client.query("SELECT indexname FROM pg_indexes WHERE schemaname = 'public'");
  const presentIndexes = new Set(indexes.rows.map((row) => row.indexname));
  const missingIndexes = manifest.requiredIndexes.filter((index) => !presentIndexes.has(index));

  const constraints = await client.query(`
    SELECT COUNT(*) FILTER (WHERE contype = 'c')::integer AS check_constraints,
           COUNT(*) FILTER (WHERE contype = 'f')::integer AS foreign_keys
      FROM pg_constraint
     WHERE connamespace = 'public'::regnamespace
  `);
  const functions = await client.query(`
    SELECT p.proname
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
  `);
  const presentFunctions = new Set(functions.rows.map((row) => row.proname));
  const requiredFunctions = ['earth_integrity_report', 'earth_market_integrity_report', 'earth_get_current_game_time', 'earth_post_transaction', 'earth_post_settlement_batch'];
  const missingFunctions = requiredFunctions.filter((name) => !presentFunctions.has(name));
  const triggers = await client.query("SELECT COUNT(*)::integer AS count FROM pg_trigger WHERE NOT tgisinternal AND tgrelid IN (SELECT oid FROM pg_class WHERE relnamespace = 'public'::regnamespace)");
  const views = await client.query("SELECT COUNT(*)::integer AS count FROM pg_class WHERE relnamespace = 'public'::regnamespace AND relkind IN ('v', 'm')");
  const seed = await client.query(`
    SELECT
      (SELECT COUNT(*) FROM earth_schema_migrations)::integer AS migrations,
      (SELECT COALESCE(MAX(version), 0) FROM earth_schema_migrations)::integer AS migration_version,
      (SELECT COUNT(*) FROM world_state WHERE id = 'WORLD')::integer AS world_rows,
      (SELECT COUNT(*) FROM humans)::integer AS humans,
      (SELECT COUNT(*) FROM economic_assets)::integer AS economic_assets
  `);
  const seedRow = seed.rows[0];
  const failures = [
    ...missingColumns.map((name) => `missing column ${name}`),
    ...missingUnique.map((name) => `missing unique constraint ${name}`),
    ...missingIndexes.map((name) => `missing index ${name}`),
    ...missingFunctions.map((name) => `missing function ${name}`),
  ];
  if (Number(constraints.rows[0]?.check_constraints ?? 0) === 0) failures.push('no CHECK constraints found');
  if (Number(constraints.rows[0]?.foreign_keys ?? 0) === 0) failures.push('no foreign keys found');
  if (Number(triggers.rows[0]?.count ?? 0) === 0) failures.push('no user triggers found');
  if (Number(views.rows[0]?.count ?? 0) === 0) failures.push('no views or materialized views found');
  if (Number(seedRow?.migration_version ?? 0) !== manifest.migrationVersion) failures.push(`migration version ${seedRow?.migration_version ?? 0} != ${manifest.migrationVersion}`);
  if (Number(seedRow?.world_rows ?? 0) !== 1) failures.push('WORLD row is not initialized');
  if (Number(seedRow?.humans ?? 0) === 0) failures.push('seed did not create humans');
  if (Number(seedRow?.economic_assets ?? 0) === 0) failures.push('seed did not create economic assets');

  const result = {
    ok: failures.length === 0,
    migrationVersion: Number(seedRow?.migration_version ?? 0),
    expectedMigrationVersion: manifest.migrationVersion,
    tablesChecked: Object.keys(manifest.requiredTables).length,
    indexesChecked: manifest.requiredIndexes.length,
    uniqueConstraintsChecked: manifest.requiredUniqueConstraints.length,
    checkConstraints: Number(constraints.rows[0]?.check_constraints ?? 0),
    foreignKeys: Number(constraints.rows[0]?.foreign_keys ?? 0),
    triggers: Number(triggers.rows[0]?.count ?? 0),
    views: Number(views.rows[0]?.count ?? 0),
    failures,
  };
  console.log(JSON.stringify(result, null, 2));
  assert.equal(result.ok, true, failures.join('; '));
} finally {
  await client.end();
}
