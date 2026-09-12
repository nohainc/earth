import test from 'node:test';
import assert from 'node:assert/strict';
import { Client } from 'pg';

test('deliberate Economy V2 projection corruption is detected as critical', async (t) => {
  if (!process.env.DATABASE_URL) {
    t.skip('DATABASE_URL is required for PostgreSQL corruption certification');
    return;
  }
  const client = new Client({ connectionString: process.env.DATABASE_URL, application_name: 'earth-invariant-corruption-test' });
  await client.connect();
  try {
    const owner = await client.query('SELECT owner_economic_id FROM economic_owner_totals LIMIT 1');
    if (!owner.rows[0]) {
      t.skip('seed contains no owner totals to corrupt');
      return;
    }
    await client.query('BEGIN');
    await client.query('UPDATE economic_owner_totals SET credit_received = credit_received + 1 WHERE owner_economic_id = $1', [owner.rows[0].owner_economic_id]);
    const report = await client.query("SELECT severity, check_name, invalid_count FROM earth_integrity_report_detailed() WHERE check_name = 'totals_mismatch'");
    assert.ok(report.rows.some((row) => row.severity === 'critical' && Number(row.invalid_count) > 0));
    await client.query('ROLLBACK');
  } finally {
    await client.end();
  }
});
