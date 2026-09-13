import { Client } from 'pg';

export function postgresClient(connectionString, applicationName) {
  const parsed = new URL(connectionString);
  const usesSystemRoot = parsed.searchParams.get('sslrootcert') === 'system';
  if (usesSystemRoot) {
    parsed.searchParams.delete('sslrootcert');
    parsed.searchParams.delete('sslmode');
  }
  return new Client({
    connectionString: parsed.toString(),
    ...(usesSystemRoot ? { ssl: { rejectUnauthorized: true } } : {}),
    application_name: applicationName,
  });
}
