import { Client } from 'pg';

const command = process.argv[2];
const databaseUrl = process.env.DATABASE_URL ?? 'postgres://earth:earth_dev_only@localhost:5432/earth';
const isLocal = /localhost|127\.0\.0\.1|::1/.test(databaseUrl);
if (!isLocal && process.env.EARTH_ALLOW_REMOTE_MUTATION !== 'true') {
  throw new Error('Refusing local game command against a remote DATABASE_URL. Set EARTH_ALLOW_REMOTE_MUTATION=true only for staging.');
}

if (command === 'heartbeat') {
  const origin = process.env.EARTH_LOCAL_API_ORIGIN ?? 'http://127.0.0.1:8788';
  const response = await fetch(`${origin}/__scheduled`);
  if (!response.ok) throw new Error(`Scheduled Worker returned HTTP ${response.status}`);
  console.log('Worker scheduled heartbeat completed.');
  process.exit(0);
}

if (command === 'time' || command === 'status') {
  const client = new Client({ connectionString: databaseUrl });
  await client.connect();
  try {
    const result = await client.query('SELECT game_day, game_minute, total_game_minutes, genesis_at FROM earth_get_current_game_time()');
    const row = result.rows[0];
    console.log(`Authoritative game time: Day ${row.game_day}, Minute ${row.game_minute} (Total minutes: ${row.total_game_minutes}, Genesis: ${row.genesis_at}).`);
  } finally {
    await client.end();
  }
  process.exit(0);
}

throw new Error('Usage: status | time | heartbeat (Note: World time is continuously derived from genesis_at; direct clock advancement is obsolete)');
