import { Client } from 'pg';

const connectionString = process.env.DATABASE_URL;
if (!connectionString) throw new Error('DATABASE_URL is required');

const url = new URL(connectionString);
// libpq accepts sslrootcert=system, while node-postgres treats it as a
// literal filename. Removing it lets Node use its system CA store instead.
if (url.searchParams.get('sslrootcert') === 'system') {
  url.searchParams.delete('sslrootcert');
}

const client = new Client({
  connectionString: url.toString(),
  connectionTimeoutMillis: 5000,
});

try {
  await client.connect();
  await client.query('SELECT 1');
  console.log('PostgreSQL reachable');
} finally {
  await client.end().catch(() => undefined);
}
