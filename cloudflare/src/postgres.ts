import { Client } from 'pg';
import { EARTH_SCHEMA_VERSION, REQUIRED_INDEXES, REQUIRED_SCHEMA_TABLES, REQUIRED_UNIQUE_CONSTRAINTS } from './schema-contract.ts';
import { isExactSchemaCompatible } from './schema-readiness.ts';

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
  expectedSchemaVersion: number;
  migrationVersion?: number;
  missingObjects?: string[];
};

function requiredColumns() {
  return Object.entries(REQUIRED_SCHEMA_TABLES).flatMap(([table, columns]) =>
    columns.map((column) => ({ table, column })));
}

/** Read-only connectivity check used by the PostgreSQL readiness endpoint. */
export async function probePostgres(binding?: HyperdriveBinding): Promise<PostgresProbe> {
  if (!binding?.connectionString) return { configured: false, reachable: false, schemaReady: false, dataReady: false, expectedSchemaVersion: EARTH_SCHEMA_VERSION };

  try {
    const probe = await withPostgres(binding, async (client) => {
      const result = await client.query<{ version: string }>(
      "SELECT current_setting('server_version') AS version",
      );
      const columns = requiredColumns();
      const schema = await client.query<{ table_name: string; column_name: string }>(
        `SELECT c.table_name, c.column_name
           FROM information_schema.columns c
          WHERE c.table_schema = 'public'
            AND (c.table_name, c.column_name) IN (SELECT * FROM UNNEST($1::text[], $2::text[]))`,
        [columns.map(({ table }) => table), columns.map(({ column }) => column)],
      );
      const presentColumns = new Set(schema.rows.map((row) => `${row.table_name}:${row.column_name}`));
      const missingObjects = columns
        .filter(({ table, column }) => !presentColumns.has(`${table}:${column}`))
        .map(({ table, column }) => `column ${table}.${column}`);
      const uniqueRows = await client.query<{ table_name: string; columns: string[] }>(`
        SELECT tc.table_name, array_agg(kcu.column_name ORDER BY kcu.ordinal_position) AS columns
          FROM information_schema.table_constraints tc
          JOIN information_schema.key_column_usage kcu USING (constraint_catalog, constraint_schema, constraint_name, table_name)
         WHERE tc.table_schema = 'public' AND tc.constraint_type IN ('PRIMARY KEY', 'UNIQUE')
         GROUP BY tc.table_name, tc.constraint_name`);
      const uniqueKeys = new Set(uniqueRows.rows.map((row) => `${row.table_name}:${row.columns.join(',')}`));
      for (const [table, ...constraintColumns] of REQUIRED_UNIQUE_CONSTRAINTS) {
        if (!uniqueKeys.has(`${table}:${constraintColumns.join(',')}`)) missingObjects.push(`unique ${table}(${constraintColumns.join(',')})`);
      }
      const indexRows = await client.query<{ indexname: string }>(`SELECT indexname FROM pg_indexes WHERE schemaname = 'public'`);
      const indexes = new Set(indexRows.rows.map((row) => row.indexname));
      for (const index of REQUIRED_INDEXES) if (!indexes.has(index)) missingObjects.push(`index ${index}`);
      const migration = await client.query<{ version: string }>('SELECT COALESCE(MAX(version), 0)::text AS version FROM earth_schema_migrations');
      const migrationVersion = Number(migration.rows[0]?.version ?? 0);
      const featureTableCount = new Set(schema.rows.map((row) => row.table_name)).size;
      const data = missingObjects.length === 0 && migrationVersion === EARTH_SCHEMA_VERSION
        ? await client.query<{ humans: string; world: string; ledger: string }>(
        `select
           (select count(*) from humans)::text as humans,
           (select count(*) from world_state where id = 'WORLD')::text as world,
           (select count(*) from ledger_entries)::text as ledger`,
        )
        : { rows: [] };
      const dataRow = data.rows[0];
      return {
        serverVersion: result.rows[0]?.version,
        featureTableCount,
        dataReady: isExactSchemaCompatible(migrationVersion, missingObjects, EARTH_SCHEMA_VERSION) && Number(dataRow?.humans ?? 0) > 0 && Number(dataRow?.world ?? 0) === 1 && Number(dataRow?.ledger ?? 0) >= 0,
        migrationVersion,
        missingObjects,
      };
    });
    const featureTableCount = probe?.featureTableCount ?? 0;
    return {
      configured: true,
      reachable: true,
      serverVersion: probe?.serverVersion,
      schemaReady: isExactSchemaCompatible(probe?.migrationVersion, probe?.missingObjects, EARTH_SCHEMA_VERSION),
      featureTableCount,
      dataReady: probe?.dataReady ?? false,
      expectedSchemaVersion: EARTH_SCHEMA_VERSION,
      migrationVersion: probe?.migrationVersion,
      missingObjects: probe?.missingObjects,
    };
  } catch {
    return { configured: true, reachable: false, schemaReady: false, dataReady: false, expectedSchemaVersion: EARTH_SCHEMA_VERSION };
  }
}
