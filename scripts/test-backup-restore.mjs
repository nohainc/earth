import { createHash } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { Client } from 'pg';

const connectionString = process.env.DATABASE_URL;
const exportPath = process.env.D1_EXPORT;
if (!connectionString || !exportPath) throw new Error('DATABASE_URL and D1_EXPORT are required');

const parsed = new URL(connectionString);
const systemRoot = parsed.searchParams.get('sslrootcert') === 'system';
if (systemRoot) { parsed.searchParams.delete('sslrootcert'); parsed.searchParams.delete('sslmode'); }
const sql = await readFile(exportPath, 'utf8');
const inserts = sql.split('\n').filter((line) => /^INSERT INTO "[^"]+"/.test(line) && !/^INSERT INTO "(?:d1_migrations|sqlite_sequence)"/.test(line));
const tables = [...new Set(inserts.map((line) => line.match(/^INSERT INTO "([^"]+)"/)?.[1]).filter(Boolean))];
const schema = `restore_test_${crypto.randomUUID().replaceAll('-', '')}`;
const client = new Client({ connectionString: parsed.toString(), ...(systemRoot ? { ssl: { rejectUnauthorized: true } } : {}), application_name: 'earth-world-backup-restore-test', connectionTimeoutMillis: 5000, query_timeout: 30000, statement_timeout: 30000 });
await client.connect();
try {
  await client.query('BEGIN');
  await client.query(`CREATE SCHEMA "${schema}"`);
  for (const table of tables) {
    await client.query(`CREATE TABLE "${schema}"."${table}" (LIKE public."${table}" INCLUDING DEFAULTS)`);
    const booleanColumns = await client.query("SELECT column_name FROM information_schema.columns WHERE table_schema = 'public' AND table_name = $1 AND data_type = 'boolean'", [table]);
    for (const column of booleanColumns.rows) {
      await client.query(`ALTER TABLE "${schema}"."${table}" ALTER COLUMN "${column.column_name}" DROP DEFAULT`);
      await client.query(`ALTER TABLE "${schema}"."${table}" ALTER COLUMN "${column.column_name}" TYPE integer USING CASE WHEN "${column.column_name}" THEN 1 ELSE 0 END`);
    }
  }
  await client.query(`SET LOCAL search_path TO "${schema}"`);
  for (const line of inserts) {
    await client.query(line);
  }
  const counts = {};
  for (const table of tables) counts[table] = Number((await client.query(`SELECT COUNT(*)::integer AS count FROM "${schema}"."${table}"`)).rows[0].count);
  const result = { ok: inserts.length > 0 && tables.every((table) => counts[table] > 0), schema, insertStatements: inserts.length, tables: counts, backupSha256: createHash('sha256').update(sql).digest('hex') };
  console.log(JSON.stringify(result, null, 2));
  await client.query('ROLLBACK');
  if (!result.ok) process.exitCode = 1;
} catch (error) {
  await client.query('ROLLBACK').catch(() => undefined);
  throw error;
} finally { await client.end(); }
