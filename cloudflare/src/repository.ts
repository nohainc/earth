import { Client, type QueryResult, type QueryResultRow } from 'pg';
import { workerConnectionString } from './postgres.ts';

const MAX_TRANSACTION_ATTEMPTS = 3;
const RETRY_BACKOFF_MS = 10;

export type RepositoryWorkload = 'api' | 'scheduler';
export type RepositoryOptions = { workload?: RepositoryWorkload };

export type AuthorityMode = 'postgres';

export function authorityMode(env: Env): AuthorityMode {
  if ((env.PERSISTENCE_AUTHORITY as string) !== 'postgres') throw new Error('PostgreSQL persistence authority is required');
  return 'postgres';
}

export function isRetryablePostgresError(error: unknown): boolean {
  const code = error && typeof error === 'object' && 'code' in error ? String((error as { code?: unknown }).code) : '';
  return code === '40001' || code === '40P01';
}

function waitForRetry(attempt: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, Math.min(100, RETRY_BACKOFF_MS * (2 ** (attempt - 1)))));
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
  private readonly client: Client;
  // A repository owns one PostgreSQL client.  PostgreSQL clients do not
  // support concurrent in-flight queries, while read models commonly use
  // Promise.all for composition.  Serialize repository queries here so a
  // composed read cannot interleave protocol messages or transaction state.
  private queryTail: Promise<void> = Promise.resolve();

  constructor(client: Client) {
    this.client = client;
  }

  async query<Row extends QueryResultRow = QueryResultRow>(sql: string, params: unknown[] = []): Promise<QueryResult<Row>> {
    const boundSql = bindPlaceholders(sql);
    const run = this.queryTail.then(async () => {
      try {
        return await this.client.query<Row>(boundSql, params);
      } catch (error) {
        // Keep production diagnostics useful without logging parameter values.
        if (error instanceof Error && !error.message.includes('[postgres query:')) {
          error.message = `${error.message} [postgres query: ${boundSql.slice(0, 240)}]`;
        }
        throw error;
      }
    });
    this.queryTail = run.then(() => undefined, () => undefined);
    return run;
  }

  async transaction<T>(work: (repository: PostgresRepository) => Promise<T>): Promise<T> {
    for (let attempt = 1; attempt <= MAX_TRANSACTION_ATTEMPTS; attempt += 1) {
      let transactionStarted = false;
      try {
        await this.client.query('BEGIN');
        transactionStarted = true;
        const result = await work(this);
        await this.client.query('COMMIT');
        return result;
      } catch (error) {
        if (transactionStarted) await this.client.query('ROLLBACK').catch(() => undefined);
        if (!isRetryablePostgresError(error) || attempt === MAX_TRANSACTION_ATTEMPTS) throw error;
        await waitForRetry(attempt);
      }
    }
    throw new Error('PostgreSQL transaction retry budget exhausted');
  }
}

export async function withPostgresRepository<T>(env: Env, work: (repository: PostgresRepository) => Promise<T>, options: RepositoryOptions = {}): Promise<T | undefined> {
  const config = env as unknown as Record<string, unknown>;
  const connectionString = env.HYPERDRIVE?.connectionString ?? (config.DATABASE_URL as string | undefined);
  if (!connectionString) return undefined;
  const scheduler = options.workload === 'scheduler';
  const client = new Client({
    connectionString: workerConnectionString(connectionString),
    ssl: { rejectUnauthorized: true },
    connectionTimeoutMillis: 3000,
    query_timeout: scheduler ? Number(config.EARTH_SCHEDULER_STATEMENT_TIMEOUT_MS ?? 30000) : Number(config.EARTH_API_STATEMENT_TIMEOUT_MS ?? 5000),
    statement_timeout: scheduler ? Number(config.EARTH_SCHEDULER_STATEMENT_TIMEOUT_MS ?? 30000) : Number(config.EARTH_API_STATEMENT_TIMEOUT_MS ?? 5000),
    application_name: 'earth-world-repository',
  });
  await client.connect();
  try {
    if (scheduler) await client.query('SELECT set_config(\'lock_timeout\',$1,false)', [`${Number(config.EARTH_SCHEDULER_LOCK_TIMEOUT_MS ?? 5000)}ms`]);
    return await work(new PostgresRepository(client));
  } finally {
    await client.end().catch(() => undefined);
  }
}

export async function withRepository<T>(env: Env, work: (repository: PostgresRepository) => Promise<T>, options: RepositoryOptions = {}): Promise<T | undefined> {
  authorityMode(env);
  const config = env as unknown as Record<string, unknown>;
  if (!env.HYPERDRIVE?.connectionString && !config.DATABASE_URL) throw new Error('PostgreSQL Hyperdrive binding is required');
  return withPostgresRepository(env, work, options);
}
