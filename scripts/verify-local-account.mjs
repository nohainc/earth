import pg from 'pg';

const connectionString = process.env.DATABASE_URL || 'postgres://earth:earth_dev_only@localhost:5432/earth';
const client = new pg.Client({ connectionString });

await client.connect();
try {
  console.log('=== 1. Inspecting Cities ===');
  for (const cityId of ['CITY-0084', 'CITY-7B64B906']) {
    console.log(`\n--- City: ${cityId} ---`);
    const before = await client.query('SELECT resource, amount FROM resource_balances WHERE owner_id = $1 ORDER BY resource', [cityId]);
    console.log('Resource Balances (Before):');
    console.table(before.rows);

    const reb = await client.query('SELECT * FROM earth_rebuild_settlement_profile($1)', [cityId]);
    console.log('Rebuilt City Profile:');
    console.table(reb.rows);

    const catchup = await client.query('SELECT * FROM earth_catchup_owner_settlement($1)', [cityId]);
    console.log('Catch-up Result:');
    console.table(catchup.rows);

    const after = await client.query('SELECT resource, amount FROM resource_balances WHERE owner_id = $1 ORDER BY resource', [cityId]);
    console.log('Resource Balances (After):');
    console.table(after.rows);
  }

  console.log('\n=== 2. Activating Building for User H-80ACE56E to Test Production ===');
  // Complete construction of building BLD-B7A42FD6 for user H-80ACE56E
  await client.query(`
    UPDATE buildings
    SET status = 'active', construction_progress = 100.0, condition = 100.0
    WHERE id = 'BLD-B7A42FD6'
  `);

  console.log('\n--- User: Vitalii (H-80ACE56E) ---');
  const userBefore = await client.query('SELECT resource, amount FROM resource_balances WHERE owner_id = $1 ORDER BY resource', ['H-80ACE56E']);
  console.log('User Resource Balances (Before):');
  console.table(userBefore.rows);

  const userReb = await client.query('SELECT * FROM earth_rebuild_settlement_profile($1)', ['H-80ACE56E']);
  console.log('User Rebuilt Profile:');
  console.table(userReb.rows);

  // Advance last_settled_game_day by simulating 1 day elapsed
  await client.query(`
    UPDATE daily_settlement_profiles
    SET last_settled_game_day = last_settled_game_day - 5
    WHERE owner_id = 'H-80ACE56E'
  `);

  const userCatchup = await client.query('SELECT * FROM earth_catchup_owner_settlement($1)', ['H-80ACE56E']);
  console.log('User Catch-up Result (5 Days Settled):');
  console.table(userCatchup.rows);

  const userAfter = await client.query('SELECT resource, amount FROM resource_balances WHERE owner_id = $1 ORDER BY resource', ['H-80ACE56E']);
  console.log('User Resource Balances (After):');
  console.table(userAfter.rows);

} finally {
  await client.end();
}
