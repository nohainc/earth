import test from 'node:test';
import assert from 'node:assert/strict';
import pg from 'pg';

const connectionString = process.env.DATABASE_URL;

test('terminal settlement phase failure marks its parent day failed', { skip: !connectionString }, async () => {
  const client = new pg.Client({ connectionString, connectionTimeoutMillis: 3000 });
  await client.connect();
  try {
    const gameDay = 900000000 + Math.floor(Math.random() * 1000000);
    await client.query('BEGIN');
    await client.query(
      `INSERT INTO daily_settlement_runs (game_day, status, current_phase)
       VALUES ($1, 'running', 'recovery-test')`,
      [gameDay],
    );
    const work = await client.query(
      `INSERT INTO daily_settlement_phase_runs
         (game_day, phase_id, phase_order, shard, status, attempt_count, lease_owner, lease_expires_at, correlation_id)
       VALUES ($1, 'recovery-test', 1, 0, 'running', 5, 'recovery-worker', CURRENT_TIMESTAMP, $2)
       RETURNING id`,
      [gameDay, `recovery-test:${gameDay}`],
    );

    const result = await client.query(
      'SELECT earth_fail_settlement_day($1, $2, $3) AS updated',
      [work.rows[0].id, 'recovery-worker', 'terminal recovery test'],
    );
    assert.equal(result.rows[0].updated, true);

    const state = await client.query(
      'SELECT status, current_phase, error_message FROM daily_settlement_runs WHERE game_day = $1',
      [gameDay],
    );
    assert.deepEqual(state.rows[0], {
      status: 'failed',
      current_phase: 'recovery-test',
      error_message: 'terminal recovery test',
    });
    const phase = await client.query('SELECT status FROM daily_settlement_phase_runs WHERE id = $1', [work.rows[0].id]);
    assert.equal(phase.rows[0].status, 'failed');
    await client.query('ROLLBACK');
  } finally {
    await client.end();
  }
});
