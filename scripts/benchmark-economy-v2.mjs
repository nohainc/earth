import { Client } from 'pg';

const connectionString = process.env.DATABASE_URL;
if (!connectionString) throw new Error('DATABASE_URL is required; refusing to benchmark an implicit database target');

const requestedScales = (process.env.ECONOMY_PERF_SCALES ?? '100,1000,10000,100000,1000000')
  .split(',').map((value) => Number(value.trim())).filter((value) => Number.isInteger(value) && value > 0);
if (!requestedScales.length) throw new Error('ECONOMY_PERF_SCALES must contain at least one positive integer');

const client = new Client({ connectionString, application_name: 'earth-economy-v2-benchmark', connectionTimeoutMillis: 5000, query_timeout: 300000 });
let queryCount = 0;
const query = (text, values) => { queryCount += 1; return client.query(text, values); };
const timed = async (name, work) => {
  const before = queryCount;
  const started = performance.now();
  const result = await work();
  return { name, durationMs: Number((performance.now() - started).toFixed(2)), queries: queryCount - before, rows: result?.rowCount ?? null };
};

async function lockContentionProbe() {
  const accounts = await query('SELECT id FROM economic_accounts WHERE status = \'active\' ORDER BY id LIMIT 2');
  if (accounts.rowCount < 2) return { skipped: true, reason: 'fewer than two active economic accounts' };
  const [first, second] = accounts.rows.map((row) => Number(row.id));
  const left = new Client({ connectionString, application_name: 'earth-economy-v2-lock-probe-a', connectionTimeoutMillis: 5000, query_timeout: 30000 });
  const right = new Client({ connectionString, application_name: 'earth-economy-v2-lock-probe-b', connectionTimeoutMillis: 5000, query_timeout: 30000 });
  await Promise.all([left.connect(), right.connect()]);
  const started = performance.now();
  try {
    await left.query('BEGIN');
    await left.query('SELECT id FROM economic_accounts WHERE id = $1 FOR UPDATE', [first]);
    const waiter = right.query('BEGIN').then(() => right.query('SELECT id FROM economic_accounts WHERE id = $1 FOR UPDATE', [first]));
    await new Promise((resolve) => setTimeout(resolve, 25));
    await left.query('SELECT id FROM economic_accounts WHERE id = $1 FOR UPDATE', [second]);
    await left.query('ROLLBACK');
    await waiter;
    await right.query('ROLLBACK');
    return { skipped: false, lockWaitMs: Number((performance.now() - started).toFixed(2)), deadlocks: 0, ordering: 'ascending account_id' };
  } finally {
    await left.query('ROLLBACK').catch(() => undefined);
    await right.query('ROLLBACK').catch(() => undefined);
    await Promise.all([left.end(), right.end()]);
  }
}

await client.connect();
try {
  const results = [];
  for (const scale of requestedScales) {
    queryCount = 0;
    await query('BEGIN');
    try {
      await query(`
        CREATE TEMP TABLE perf_accounts ON COMMIT DROP AS
        SELECT owner_id, (owner_id * 6 + asset_id)::BIGINT AS account_id, asset_id::SMALLINT,
               100000000::BIGINT AS balance
        FROM generate_series(1, $1::BIGINT) owner_id CROSS JOIN generate_series(1, 6) asset_id`, [scale]);
      await query('CREATE INDEX perf_accounts_owner_asset_idx ON perf_accounts(owner_id, asset_id)');
      await query('CREATE INDEX perf_accounts_id_idx ON perf_accounts(account_id)');

      const timings = [];
      timings.push(await timed('profile_rebuild', () => query(`
        CREATE TEMP TABLE perf_profiles ON COMMIT DROP AS
        SELECT owner_id, SUM(CASE WHEN asset_id = 1 THEN 0 ELSE 100 END)::BIGINT AS physical_effect
        FROM perf_accounts GROUP BY owner_id`, [])));
      timings.push(await timed('effect_generation', () => query(`
        CREATE TEMP TABLE perf_effects ON COMMIT DROP AS
        SELECT owner_id, account_id, asset_id, CASE WHEN asset_id % 2 = 0 THEN 100 ELSE -25 END::BIGINT AS delta
        FROM perf_accounts`, [])));
      await query('CREATE INDEX perf_effects_account_idx ON perf_effects(account_id, asset_id)');
      timings.push(await timed('netting', () => query(`
        CREATE TEMP TABLE perf_nets ON COMMIT DROP AS
        SELECT account_id, asset_id, SUM(delta)::BIGINT AS delta
        FROM perf_effects GROUP BY account_id, asset_id`, [])));
      await query('CREATE INDEX perf_nets_account_idx ON perf_nets(account_id)');
      timings.push(await timed('posting', () => query(`
        UPDATE perf_accounts a SET balance = a.balance + n.delta
        FROM perf_nets n WHERE n.account_id = a.account_id`, [])));
      const entryVolume = await query('SELECT COUNT(*)::BIGINT AS count FROM perf_effects');
      const memory = await query("SELECT COALESCE(SUM(total_bytes), 0)::BIGINT AS bytes FROM pg_backend_memory_contexts").catch(() => ({ rows: [{ bytes: null }] }));
      const plan = await query(`
        EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
        SELECT account_id, SUM(delta) FROM perf_effects GROUP BY account_id`, []);
      await query('ROLLBACK');
      results.push({ scale, timings, entryVolume: Number(entryVolume.rows[0].count), memoryBytes: memory.rows[0].bytes === null ? null : Number(memory.rows[0].bytes), queryCount, plan: plan.rows[0]['QUERY PLAN'] });
    } catch (error) {
      await query('ROLLBACK').catch(() => undefined);
      throw error;
    }
  }
  const lockProbe = await lockContentionProbe();
  const partitionPlan = await query(`
    EXPLAIN (FORMAT JSON)
    SELECT account_id, delta FROM economic_entries
    WHERE game_day = (SELECT COALESCE(MAX(game_day), 0) FROM daily_settlement_runs)
    ORDER BY account_id LIMIT 100`);
  console.log(JSON.stringify({ ok: true, scales: results, concurrency: lockProbe, partitionPlan: partitionPlan.rows[0]['QUERY PLAN'] }, null, 2));
} finally {
  await client.end();
}
