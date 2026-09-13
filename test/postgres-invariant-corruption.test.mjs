import test from 'node:test';
import assert from 'node:assert/strict';
import { Client } from 'pg';

test('canonical Economy V2 integrity report is executable on the clean baseline', { skip: !process.env.DATABASE_URL }, async () => {
  const client = new Client({ connectionString: process.env.DATABASE_URL, application_name: 'earth-invariant-certification' });
  await client.connect();
  try {
    const result = await client.query('SELECT check_name, invalid_count FROM earth_integrity_report() ORDER BY check_name');
    assert.ok(result.rows.length >= 4);
    assert.ok(result.rows.every((row) => Number(row.invalid_count) === 0));
  } finally { await client.end(); }
});
