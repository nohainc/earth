import { Client, type QueryResult, type QueryResultRow } from 'pg';

export type AuthorityMode = 'd1' | 'postgres';

export function authorityMode(env: Env): AuthorityMode {
  return (env.PERSISTENCE_AUTHORITY as string) === 'postgres' && env.HYPERDRIVE?.connectionString ? 'postgres' : 'd1';
}

function bindPlaceholders(sql: string): string {
  let index = 0;
  let quoted = false;
  let output = '';
  for (let cursor = 0; cursor < sql.length; cursor += 1) {
    const char = sql[cursor];
    if (char === "'") {
      if (quoted && sql[cursor + 1] === "'") { output += "''"; cursor += 1; continue; }
      quoted = !quoted;
      output += char;
    } else if (char === '?' && !quoted) {
      index += 1;
      output += `$${index}`;
    } else {
      output += char;
    }
  }
  return output;
}

export class PostgresRepository {
  constructor(private readonly client: Client) {}

  query<Row extends QueryResultRow = QueryResultRow>(sql: string, params: unknown[] = []): Promise<QueryResult<Row>> {
    return this.client.query<Row>(bindPlaceholders(sql), params);
  }

  async transaction<T>(work: (repository: PostgresRepository) => Promise<T>): Promise<T> {
    await this.client.query('BEGIN');
    try {
      const result = await work(this);
      await this.client.query('COMMIT');
      return result;
    } catch (error) {
      await this.client.query('ROLLBACK');
      throw error;
    }
  }
}

export async function withPostgresRepository<T>(env: Env, work: (repository: PostgresRepository) => Promise<T>): Promise<T | undefined> {
  if (!env.HYPERDRIVE?.connectionString) return undefined;
  const client = new Client({
    connectionString: env.HYPERDRIVE.connectionString,
    connectionTimeoutMillis: 3000,
    query_timeout: 5000,
    statement_timeout: 5000,
    application_name: 'earth-world-repository',
  });
  await client.connect();
  try {
    return await work(new PostgresRepository(client));
  } finally {
    await client.end().catch(() => undefined);
  }
}

export async function withRepository<T>(env: Env, work: (repository: PostgresRepository) => Promise<T>): Promise<T | undefined> {
  if (authorityMode(env) !== 'postgres') return undefined;
  return withPostgresRepository(env, work);
}
