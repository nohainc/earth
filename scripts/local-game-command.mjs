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

const minutes = command === 'advance-hour' ? 60 : command === 'advance-day' ? 1440 : null;
if (minutes === null) throw new Error('Usage: advance-hour | advance-day | heartbeat | settle');
const client = new Client({ connectionString: databaseUrl });
await client.connect();
try {
  const result = await client.query('SELECT earth_local_advance_minutes($1) AS total_game_minutes', [minutes]);
  console.log(`Manual clock advanced to ${result.rows[0].total_game_minutes} game minutes.`);
} finally {
  await client.end();
}
