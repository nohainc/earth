import test from 'node:test';
import assert from 'node:assert/strict';
import { Client } from 'pg';

const connectionString = process.env.DATABASE_URL;

test('Economy V2 building calculator uses independent output and cost multipliers', { skip: !connectionString }, async (t) => {
  const client = new Client({ connectionString, connectionTimeoutMillis: 3000 });
  await client.connect();
  t.after(() => client.end());

  const ready = await client.query(`
    SELECT to_regprocedure('earth_calculate_building_economics(text)') AS calculator
  `);
  if (!ready.rows[0].calculator) {
    t.skip('Economy V2 building economics migration is not applied to DATABASE_URL');
    return;
  }

  const building = await client.query("SELECT id FROM buildings WHERE status = 'active' AND catalog_id IS NOT NULL LIMIT 1");
  if (building.rowCount === 0) {
    t.skip('An active catalog-backed building is required');
    return;
  }

  const rows = await client.query(
    'SELECT asset_code, output_units, upkeep_units, operating_units, effective_output_multiplier, effective_cost_multiplier FROM earth_calculate_building_economics($1) ORDER BY asset_id',
    [building.rows[0].id],
  );
  assert.equal(rows.rowCount, 6);
  assert.deepEqual(
    [...new Set(rows.rows.map((row) => row.effective_output_multiplier))].length,
    1,
  );
  assert.deepEqual(
    [...new Set(rows.rows.map((row) => row.effective_cost_multiplier))].length,
    1,
  );
});
