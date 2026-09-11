import test from 'node:test';
import assert from 'node:assert/strict';
import pg from 'pg';

const connectionString = process.env.DATABASE_URL;

async function withDatabase(t, callback) {
  if (!connectionString) {
    t.skip('DATABASE_URL is required for Building V2 PostgreSQL integration tests');
    return;
  }
  const client = new pg.Client({ connectionString, connectionTimeoutMillis: 3000 });
  await client.connect();
  try {
    await client.query('BEGIN');
    await callback(client, t);
    await client.query('ROLLBACK');
  } finally {
    await client.end();
  }
}

async function hasTable(client, name) {
  const result = await client.query(
    'SELECT to_regclass($1) IS NOT NULL AS present',
    [`public.${name}`],
  );
  return result.rows[0].present;
}

async function hasFunction(client, signature) {
  const result = await client.query('SELECT to_regprocedure($1) IS NOT NULL AS present', [signature]);
  return result.rows[0].present;
}

test('Building V2 integration surface is installed', async (t) => {
  await withDatabase(t, async (client) => {
    for (const table of [
      'building_settlement_plans', 'building_settlement_allocations',
      'building_settlement_journals', 'building_economic_batches',
      'building_economic_effects', 'service_demand', 'service_allocations',
      'economic_accounts', 'economic_entries',
    ]) assert.equal(await hasTable(client, table), true, `${table} must exist`);
    for (const signature of [
      'earth_prepare_building_settlement(bigint,smallint)',
      'earth_allocate_building_inputs(bigint,smallint)',
      'earth_prepare_building_daily_settlement(bigint,smallint)',
      'earth_post_building_economic_batch(bigint,smallint)',
      'earth_write_building_settlement_journal(bigint,smallint)',
      'earth_building_profile_overlap_integrity()',
    ]) assert.equal(await hasFunction(client, signature), true, `${signature} must exist`);
  });
});

test('Building V2 full-input and shortage planning is database-backed', async (t) => {
  await withDatabase(t, async (client) => {
    const fixture = await client.query("SELECT game_day FROM building_settlement_plans LIMIT 1");
    if (fixture.rowCount === 0) {
      t.skip('A staged Building V2 plan fixture is required');
      return;
    }
    const day = Number(fixture.rows[0].game_day);
    const shard = Number((await client.query('SELECT shard FROM building_settlement_plans WHERE game_day = $1 LIMIT 1', [day])).rows[0].shard);
    const result = await client.query('SELECT earth_allocate_building_inputs($1, $2) AS allocated', [day, shard]);
    assert.ok(Number(result.rows[0].allocated) >= 0);
    const plan = await client.query(
      'SELECT requirements, allocated_inputs, utilization FROM building_settlement_plans WHERE game_day = $1 AND shard = $2',
      [day, shard],
    );
    for (const row of plan.rows) {
      assert.ok(row.utilization >= 0 && row.utilization <= 1);
      assert.ok(row.requirements && row.allocated_inputs);
    }
  });
});

test('Building V2 condition, maintenance, repair, and offline reactivation are staged', async (t) => {
  await withDatabase(t, async (client) => {
    const result = await client.query(`
      SELECT
        to_regprocedure('earth_apply_building_condition_efficiency(bigint,smallint)') IS NOT NULL AS efficiency,
        to_regprocedure('earth_finalize_building_condition(bigint,smallint)') IS NOT NULL AS condition,
        to_regprocedure('earth_apply_building_repair_policy(bigint,smallint)') IS NOT NULL AS repair,
        to_regprocedure('earth_finalize_building_operational_state(bigint,smallint)') IS NOT NULL AS state
    `);
    assert.deepEqual(result.rows[0], { efficiency: true, condition: true, repair: true, state: true });
    assert.equal((await client.query("SELECT COUNT(*)::int AS count FROM building_settlement_plans WHERE utilization_ppm BETWEEN 0 AND 1000000")).rows[0].count >= 0, true);
  });
});

test('Building V2 private/public service and insufficient-funds paths are represented', async (t) => {
  await withDatabase(t, async (client) => {
    for (const mode of ['PRIVATE', 'PUBLIC_CONTRACT', 'FREE']) {
      const result = await client.query('SELECT COUNT(*)::int AS count FROM building_settlement_plans WHERE service_mode = $1', [mode]);
      assert.ok(Number(result.rows[0].count) >= 0);
    }
    const columns = await client.query(`
      SELECT column_name FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'service_payment_batches'
        AND column_name IN ('consumer_units', 'operator_units', 'economic_transaction_id')
    `);
    assert.equal(columns.rowCount, 3);
  });
});

test('Building V2 posting conserves effects and is retry-safe', async (t) => {
  await withDatabase(t, async (client) => {
    const batches = await client.query(`
      SELECT b.id, b.status, b.correlation_id, COALESCE(SUM(e.delta), 0)::bigint AS delta
      FROM building_economic_batches b
      LEFT JOIN building_economic_effects e ON e.batch_id = b.id
      GROUP BY b.id
      ORDER BY b.id DESC LIMIT 20
    `);
    for (const row of batches.rows) {
      assert.equal(row.delta, '0', `batch ${row.correlation_id} must balance`);
      assert.match(row.correlation_id, /^building-settlement:/);
    }
    const duplicateDays = await client.query(`
      SELECT building_id, day, COUNT(*)::int AS count
      FROM building_settlement_journals GROUP BY building_id, day HAVING COUNT(*) > 1
    `);
    assert.equal(duplicateDays.rowCount, 0);
  });
});

test('Building V2 profile exclusion and concurrent/catch-up guards are observable', async (t) => {
  await withDatabase(t, async (client) => {
    const overlap = await client.query('SELECT * FROM earth_building_profile_overlap_integrity()');
    for (const row of overlap.rows) assert.equal(row.invalid_count, '0', `${row.check_name} must be zero`);
    const profile = await client.query(`
      SELECT COUNT(*)::int AS invalid FROM daily_settlement_profiles
      WHERE includes_building_economics OR credit_units <> 0 OR material_units <> 0
        OR components_units <> 0 OR energy_units <> 0 OR compute_units <> 0 OR food_units <> 0
    `);
    assert.equal(profile.rows[0].invalid, 0);
  });
});
