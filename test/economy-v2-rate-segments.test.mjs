import test from 'node:test';
import assert from 'node:assert/strict';
import { Client } from 'pg';

const connectionString = process.env.DATABASE_URL;

test('Economy V2 rate segments seed a minute-zero baseline', { skip: !connectionString }, async (t) => {
  const client = new Client({ connectionString, connectionTimeoutMillis: 3000 });
  await client.connect();
  t.after(() => client.end());

  const ready = await client.query(`
    SELECT to_regprocedure('earth_record_settlement_rate_segment(bigint,smallint,bigint,smallint,bigint,text,text)') AS record,
           to_regprocedure('earth_calculate_intraday_rate_units(bigint,smallint,bigint,smallint,smallint)') AS calculate
  `);
  if (!ready.rows[0].record || !ready.rows[0].calculate) {
    t.skip('Economy V2 rate-segment migration is not applied to DATABASE_URL');
    return;
  }

  const owner = await client.query('SELECT economic_id FROM owner_registry ORDER BY economic_id LIMIT 1');
  assert.equal(owner.rowCount, 1);
  const ownerId = owner.rows[0].economic_id;
  const gameDay = 900000000 + Math.floor(Math.random() * 1000000);

  await client.query('BEGIN');
  await client.query(
    'SELECT earth_record_settlement_rate_segment($1, 2, $2, 720, 24000000, $3, $4)',
    [ownerId, gameDay, 'test_activation', `plan24-${crypto.randomUUID()}`],
  );
  const segments = await client.query(
    'SELECT effective_from_minute, rate_units_per_day FROM settlement_rate_segments WHERE owner_economic_id = $1 AND asset_id = 2 AND game_day = $2 ORDER BY effective_from_minute',
    [ownerId, gameDay],
  );
  assert.deepEqual(segments.rows, [
    { effective_from_minute: 0, rate_units_per_day: 0 },
    { effective_from_minute: 720, rate_units_per_day: 24000000 },
  ]);
  const result = await client.query(
    'SELECT earth_calculate_intraday_rate_units($1, 2, $2, 0, 1440) AS units',
    [ownerId, gameDay],
  );
  assert.equal(result.rows[0].units, '12000000');
  await client.query('ROLLBACK');
});
