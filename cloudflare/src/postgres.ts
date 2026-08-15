import { Client } from 'pg';

type HyperdriveBinding = { connectionString?: string };
type PgClient = Client;

const clientOptions = (binding: HyperdriveBinding) => ({
  connectionString: binding.connectionString,
  connectionTimeoutMillis: 3000,
  query_timeout: 3000,
  statement_timeout: 3000,
  application_name: 'earth-world-worker',
});

export async function withPostgres<T>(binding: HyperdriveBinding | undefined, work: (client: PgClient) => Promise<T>): Promise<T | undefined> {
  if (!binding?.connectionString) return undefined;
  const client = new Client(clientOptions(binding));
  await client.connect();
  try {
    return await work(client);
  } finally {
    await client.end().catch(() => undefined);
  }
}

export type PostgresProbe = {
  configured: boolean;
  reachable: boolean;
  serverVersion?: string;
  schemaReady: boolean;
  featureTableCount?: number;
  dataReady: boolean;
};

/** Read-only connectivity check used by the PostgreSQL readiness endpoint. */
export async function probePostgres(binding?: HyperdriveBinding): Promise<PostgresProbe> {
  if (!binding?.connectionString) return { configured: false, reachable: false, schemaReady: false, dataReady: false };

  try {
    const probe = await withPostgres(binding, async (client) => {
      const result = await client.query<{ version: string }>(
      "SELECT current_setting('server_version') AS version",
      );
      const schema = await client.query<{ count: string }>(
      `SELECT COUNT(*)::text AS count
       FROM information_schema.tables
       WHERE table_schema = 'public'
         AND table_name IN (
           'humans', 'ledger_entries', 'market_orders', 'market_trades',
           'auth_credentials', 'auth_sessions', 'life_events',
           'ownership_events', 'authority_events', 'business_financials',
           'business_assets', 'negotiated_contracts', 'contract_disputes',
           'earth_schema_migrations'
         )`,
      );
      const featureTableCount = Number(schema.rows[0]?.count ?? 0);
      const data = await client.query<{ humans: string; world: string; ledger: string }>(
        `select
           (select count(*) from humans)::text as humans,
           (select count(*) from world_state where id = 'WORLD')::text as world,
           (select count(*) from ledger_entries)::text as ledger`,
      );
      const dataRow = data.rows[0];
      return {
        serverVersion: result.rows[0]?.version,
        featureTableCount,
        dataReady: Number(dataRow?.humans ?? 0) > 0 && Number(dataRow?.world ?? 0) === 1 && Number(dataRow?.ledger ?? 0) >= 0,
      };
    });
    const featureTableCount = probe?.featureTableCount ?? 0;
    return {
      configured: true,
      reachable: true,
      serverVersion: probe?.serverVersion,
      schemaReady: featureTableCount === 14,
      featureTableCount,
      dataReady: probe?.dataReady ?? false,
    };
  } catch {
    return { configured: true, reachable: false, schemaReady: false, dataReady: false };
  }
}
