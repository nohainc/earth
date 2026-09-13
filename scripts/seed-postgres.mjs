import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { Client } from 'pg';

const connectionString = process.env.DATABASE_URL;
if (!connectionString) throw new Error('DATABASE_URL is required; refusing to seed an implicit database target');

const seedFile = process.env.EARTH_SEED_FILE || 'db/seed.sql';
async function expandIncludes(file, seen = new Set()) {
  const absolute = path.resolve(new URL(`../${file}`, import.meta.url).pathname);
  if (seen.has(absolute)) throw new Error(`Recursive seed include: ${file}`);
  seen.add(absolute);
  const source = await readFile(absolute, 'utf8');
  const directory = path.dirname(absolute);
  const lines = source.split('\n');
  const expanded = [];
  for (const line of lines) {
    const include = line.match(/^\s*\\ir\s+(.+?)\s*$/);
    if (!include) {
      expanded.push(line);
      continue;
    }
    const child = path.relative(path.resolve(new URL('../', import.meta.url).pathname), path.resolve(directory, include[1]));
    expanded.push(await expandIncludes(child, new Set(seen)));
  }
  return expanded.join('\n');
}
const seed = await expandIncludes(seedFile);
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
  console.log(JSON.stringify({ ok: true, seeded: true, seedFile, humans: Number(result.rows[0]?.humans ?? 0) }));
} catch (error) {
  await client.query('ROLLBACK').catch(() => undefined);
  throw error;
} finally {
  await client.end();
}
