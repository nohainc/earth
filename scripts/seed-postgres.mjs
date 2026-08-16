import { readFile } from 'node:fs/promises';
import { Client } from 'pg';

const connectionString = process.env.DATABASE_URL;
if (!connectionString) throw new Error('DATABASE_URL is required; refusing to seed an implicit database target');

const seed = await readFile(new URL('../db/seed.sql', import.meta.url), 'utf8');
const parsedConnection = new URL(connectionString);
const usesSystemRoot = parsedConnection.searchParams.get('sslrootcert') === 'system';
if (usesSystemRoot) {
  parsedConnection.searchParams.delete('sslrootcert');
  parsedConnection.searchParams.delete('sslmode');
}

const client = new Client({
  connectionString: parsedConnection.toString(),
  ...(usesSystemRoot ? { ssl: { rejectUnauthorized: true } } : {}),
  application_name: 'earth-world-seeder',
  connectionTimeoutMillis: 5000,
  query_timeout: 30000,
  statement_timeout: 30000,
});

await client.connect();
try {
  await client.query('BEGIN');
  await client.query(seed);
  await client.query('COMMIT');
  const result = await client.query('SELECT COUNT(*)::integer AS humans FROM humans');
  console.log(JSON.stringify({ ok: true, seeded: true, humans: Number(result.rows[0]?.humans ?? 0) }));
} catch (error) {
  await client.query('ROLLBACK').catch(() => undefined);
  throw error;
} finally {
  await client.end();
}
