import { readFile } from 'node:fs/promises';
import { Client } from 'pg';

const connectionString = process.env.DATABASE_URL;
if (!connectionString) throw new Error('DATABASE_URL is required; refusing to verify an implicit database target');
const manifest = JSON.parse(await readFile(new URL('../db/schema-manifest.json', import.meta.url), 'utf8'));
const parsed = new URL(connectionString);
const usesSystemRoot = parsed.searchParams.get('sslrootcert') === 'system';
if (usesSystemRoot) {
  parsed.searchParams.delete('sslrootcert');
  parsed.searchParams.delete('sslmode');
}
const client = new Client({ connectionString: parsed.toString(), ...(usesSystemRoot ? { ssl: { rejectUnauthorized: true } } : {}), application_name: 'earth-schema-manifest', connectionTimeoutMillis: 5000, query_timeout: 30000 });
await client.connect();
const failures = [];
try {
  const migrations = await client.query('select max(version)::int as version from earth_schema_migrations');
  if (migrations.rows[0]?.version !== manifest.migrationVersion) failures.push(`migration version ${migrations.rows[0]?.version ?? 'none'} != ${manifest.migrationVersion}`);

  const tableRows = await client.query("select table_name from information_schema.tables where table_schema = 'public' and table_type = 'BASE TABLE'");
  const tables = new Set(tableRows.rows.map((row) => row.table_name));
  const columnRows = await client.query("select table_name, column_name from information_schema.columns where table_schema = 'public'");
  const columns = new Map();
  for (const row of columnRows.rows) (columns.get(row.table_name) ?? columns.set(row.table_name, new Set()).get(row.table_name)).add(row.column_name);
  for (const [table, expectedColumns] of Object.entries(manifest.requiredTables)) {
    if (!tables.has(table)) { failures.push(`missing table ${table}`); continue; }
    for (const column of expectedColumns) if (!columns.get(table)?.has(column)) failures.push(`missing column ${table}.${column}`);
  }

  const uniqueRows = await client.query(`
    select tc.table_name, array_agg(kcu.column_name order by kcu.ordinal_position) as columns
    from information_schema.table_constraints tc
    join information_schema.key_column_usage kcu using (constraint_catalog, constraint_schema, constraint_name, table_name)
    where tc.table_schema = 'public' and tc.constraint_type in ('PRIMARY KEY', 'UNIQUE')
    group by tc.table_name, tc.constraint_name
  `);
  const uniqueKeys = new Set(uniqueRows.rows.map((row) => `${row.table_name}:${(Array.isArray(row.columns) ? row.columns : String(row.columns).replace(/[{}]/g, '').split(',')).join(',')}`));
  for (const expected of manifest.requiredUniqueConstraints) {
    const [table, ...columnsForKey] = expected;
    if (!uniqueKeys.has(`${table}:${columnsForKey.join(',')}`)) failures.push(`missing unique constraint ${table}(${columnsForKey.join(',')})`);
  }

  const indexRows = await client.query("select indexname from pg_indexes where schemaname = 'public'");
  const indexes = new Set(indexRows.rows.map((row) => row.indexname));
  for (const index of manifest.requiredIndexes) if (!indexes.has(index)) failures.push(`missing index ${index}`);
} finally { await client.end(); }
if (failures.length) throw new Error(`PostgreSQL schema manifest failed:\n- ${failures.join('\n- ')}`);
console.log(JSON.stringify({ ok: true, migrationVersion: manifest.migrationVersion, tables: Object.keys(manifest.requiredTables).length, uniqueConstraints: manifest.requiredUniqueConstraints.length, indexes: manifest.requiredIndexes.length }));
