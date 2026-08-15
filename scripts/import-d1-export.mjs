import { readFile } from 'node:fs/promises';
import { Client } from 'pg';

const connectionString = process.env.DATABASE_URL;
const exportPath = process.env.D1_EXPORT;
if (!connectionString || !exportPath) {
  throw new Error('DATABASE_URL and D1_EXPORT are required');
}

const parsedConnection = new URL(connectionString);
const usesSystemRoot = parsedConnection.searchParams.get('sslrootcert') === 'system';
if (usesSystemRoot) {
  parsedConnection.searchParams.delete('sslrootcert');
  parsedConnection.searchParams.delete('sslmode');
}

const booleanColumns = new Set(['mfa_enabled', 'enabled', 'active']);
const skippedTables = new Set(['d1_migrations', 'sqlite_sequence']);

function statements(sql) {
  const result = [];
  let start = 0;
  let quote = false;
  for (let i = 0; i < sql.length; i += 1) {
    if (sql[i] === "'") {
      if (quote && sql[i + 1] === "'") { i += 1; continue; }
      quote = !quote;
    } else if (sql[i] === ';' && !quote) {
      const statement = sql.slice(start, i).trim();
      if (statement) result.push(statement);
      start = i + 1;
    }
  }
  return result;
}

function parseValues(input) {
  const values = [];
  let start = 0;
  let quote = false;
  for (let i = 0; i <= input.length; i += 1) {
    if (input[i] === "'") {
      if (quote && input[i + 1] === "'") { i += 1; continue; }
      quote = !quote;
    }
    if ((input[i] === ',' && !quote) || i === input.length) {
      const raw = input.slice(start, i).trim();
      if (/^null$/i.test(raw)) values.push(null);
      else if (raw.startsWith("'") && raw.endsWith("'")) values.push(raw.slice(1, -1).replaceAll("''", "'"));
      else values.push(Number(raw));
      start = i + 1;
    }
  }
  return values;
}

function parseInsert(statement) {
  const match = statement.match(/^INSERT INTO "([^"]+)" \(([^)]+)\) VALUES\((.*)\)$/s);
  if (!match) return undefined;
  const table = match[1];
  const columns = match[2].split(',').map((column) => column.trim().replaceAll('"', ''));
  return { table, columns, values: parseValues(match[3]) };
}

const sql = await readFile(exportPath, 'utf8');
const client = new Client({
  connectionString: parsedConnection.toString(),
  ...(usesSystemRoot ? { ssl: { rejectUnauthorized: true } } : {}),
  application_name: 'earth-world-d1-import',
  connectionTimeoutMillis: 5000,
  query_timeout: 30000,
  statement_timeout: 30000,
});

await client.connect();
let imported = 0;
try {
  await client.query('begin');
  for (const statement of statements(sql)) {
    const insert = parseInsert(statement);
    if (!insert || skippedTables.has(insert.table)) continue;
    const values = insert.values.map((value, index) => booleanColumns.has(insert.columns[index]) && value !== null ? Boolean(value) : value);
    const placeholders = values.map((_, index) => `$${index + 1}`).join(', ');
    await client.query(
      `insert into "${insert.table}" (${insert.columns.map((column) => `"${column}"`).join(', ')}) values (${placeholders}) on conflict do nothing`,
      values,
    );
    imported += 1;
  }
  await client.query('commit');
  console.log(JSON.stringify({ ok: true, importedStatements: imported }, null, 2));
} catch (error) {
  await client.query('rollback');
  throw error;
} finally {
  await client.end();
}
