const connectionString = process.env.DATABASE_URL;
if (!connectionString) {
  console.error('DATABASE_URL is required. Refusing to start without an explicit database target.');
  process.exit(1);
}

const url = new URL(connectionString);
// libpq accepts sslrootcert=system, but node-postgres interprets the value as a
// literal certificate filename. With sslmode=verify-full, Node's default CA
// store provides the equivalent system trust behavior.
if (url.searchParams.get('sslrootcert') === 'system') {
  url.searchParams.delete('sslrootcert');
  process.env.DATABASE_URL = url.toString();
}
const isLocal = ['localhost', '127.0.0.1', '::1'].includes(url.hostname);
const readOnly = process.env.DATABASE_READ_ONLY !== 'false';
if (!isLocal && !readOnly && process.env.CONFIRM_PRODUCTION_DB_WRITES !== 'I_UNDERSTAND_PRODUCTION_WRITES') {
  console.error('Refusing non-local database writes. Set DATABASE_READ_ONLY=true or explicitly confirm production writes.');
  process.exit(1);
}

process.env.DATABASE_READ_ONLY = String(readOnly);
console.log(`Starting local EARTH server against ${url.hostname} (${readOnly ? 'read-only database / in-memory mutations' : 'database writes enabled'})`);
await import('../server.js');
