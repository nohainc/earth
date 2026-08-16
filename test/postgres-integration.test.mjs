import test from 'node:test';
import assert from 'node:assert/strict';
import { Client } from 'pg';

const connectionString = process.env.DATABASE_URL;

test('PostgreSQL integration target is explicit when enabled', { skip: !connectionString }, async () => {
  const parsedConnection = new URL(connectionString);
  const usesSystemRoot = parsedConnection.searchParams.get('sslrootcert') === 'system';
  if (usesSystemRoot) {
    parsedConnection.searchParams.delete('sslrootcert');
    parsedConnection.searchParams.delete('sslmode');
  }
  const client = new Client({ connectionString: parsedConnection.toString(), ...(usesSystemRoot ? { ssl: { rejectUnauthorized: true } } : {}) });
  await client.connect();
  try {
    const result = await client.query("SELECT current_setting('server_version') AS version");
    assert.match(result.rows[0].version, /^\d+\./);
  } finally {
    await client.end();
  }
});
