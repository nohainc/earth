import pg from 'pg';

const connectionString = process.env.DATABASE_URL || 'postgres://earth:earth_dev_only@localhost:5432/earth';
const client = new pg.Client({ connectionString });

await client.connect();
try {
  console.log('Connecting to PostgreSQL to check cosmic game time & recalculate profiles...');
  
  // 1. Get cosmic game time
  const timeRes = await client.query('SELECT * FROM earth_get_current_game_time()');
  const time = timeRes.rows[0];
  console.log(`Current Cosmic Clock: Game Day ${time.game_day}, Minute ${time.game_minute} (Elapsed: ${Math.round(time.elapsed_real_seconds)} real seconds since ${time.genesis_at})`);

  // 2. Rebuild all dirty profiles
  const dirtyRes = await client.query(`
    SELECT p.owner_id, (earth_rebuild_settlement_profile(p.owner_id, $1)).*
    FROM daily_settlement_profiles p
    WHERE p.status = 'dirty'
  `, [time.game_day]);
  console.log(`Rebuilt ${dirtyRes.rowCount} dirty settlement profiles.`);

  // 3. Catch up active human profiles
  const catchupRes = await client.query(`
    SELECT p.owner_id, (earth_catchup_owner_settlement(p.owner_id, $1)).*
    FROM daily_settlement_profiles p
    WHERE p.last_settled_game_day < $1
  `, [time.game_day]);
  console.log(`Caught up ${catchupRes.rowCount} owner settlement profiles to Game Day ${time.game_day}.`);

  console.log('Profile recalculation and catch-up completed successfully.');
} finally {
  await client.end();
}
