import { Client } from 'pg';
import { API_ROUTES } from '../cloudflare/src/api-registry.ts';

const origin = process.env.EARTH_CLEAN_ROOM_API_ORIGIN?.replace(/\/$/, '');
const databaseUrl = process.env.DATABASE_URL;
const bearerToken = process.env.EARTH_CERTIFICATION_BEARER_TOKEN;
if (!origin) throw new Error('EARTH_CLEAN_ROOM_API_ORIGIN is required');
if (!databaseUrl) throw new Error('DATABASE_URL is required');
if (!bearerToken) throw new Error('EARTH_CERTIFICATION_BEARER_TOKEN is required for authenticated clean-room certification');

const client = new Client({ connectionString: databaseUrl, application_name: 'earth-clean-room-certification' });
await client.connect();
const headers = { authorization: `Bearer ${bearerToken}`, accept: 'application/json' };
const allowedDomainStatuses = new Set([200, 201, 202, 204, 400, 403, 404, 409, 422, 503]);
const undefinedObject = /(?:relation|column|function) .* does not exist|undefined table|undefined column|undefined function/i;

async function dbScalar(sql, params = []) {
  const result = await client.query(sql, params);
  return Number(result.rows[0]?.value ?? 0);
}

async function request(path, method = 'GET', body) {
  const response = await fetch(`${origin}${path}`, {
    method,
    headers: { ...headers, 'content-type': 'application/json' },
    body: body == null ? undefined : JSON.stringify(body),
  });
  const text = await response.text();
  if (undefinedObject.test(text)) throw new Error(`${method} ${path} exposed an undefined PostgreSQL object: ${text}`);
  if (response.status >= 500 && response.status !== 503) throw new Error(`${method} ${path} returned unexpected HTTP ${response.status}: ${text}`);
  if (!allowedDomainStatuses.has(response.status)) throw new Error(`${method} ${path} returned unclassified HTTP ${response.status}: ${text}`);
  return { response, text };
}

try {
  const before = {
    day: await dbScalar("SELECT game_day AS value FROM world_state WHERE id = 'WORLD'"),
    events: await dbScalar('SELECT COUNT(*) AS value FROM game_events'),
    outbox: await dbScalar('SELECT COUNT(*) AS value FROM event_outbox'),
  };
  const activeGets = API_ROUTES.filter((route) => route.status === 'ACTIVE' && route.method === 'GET' && !route.path.startsWith('/internal/'));
  for (const route of activeGets) {
    const path = route.path.replaceAll('{id}', 'clean-room-missing-id').replaceAll('{action}', 'status').replaceAll('{view}', 'status').replaceAll('{instrument}', 'SPOT-MATERIAL').replaceAll('{subaction}', 'status').replaceAll('{humanId}', 'clean-room-missing-human').replaceAll('{cityId}', 'clean-room-missing-city').replaceAll('{requestId}', 'clean-room-missing-request');
    await request(path);
  }
  for (const path of ['/api/world', '/api/events', '/api/house/daily-summary']) await request(path);
  const telemetry = await request('/api/telemetry/error', 'POST', { message: 'clean-room certification probe', endpoint: '/api/telemetry/error', errorCode: 'CERTIFICATION_PROBE', correlationId: `clean-room-${Date.now()}` });
  if (![202, 204].includes(telemetry.response.status)) throw new Error(`Telemetry contract returned ${telemetry.response.status}, expected 202 or 204`);

  const realtimeAbort = new AbortController();
  const realtimeTimer = setTimeout(() => realtimeAbort.abort(), 3000);
  try {
    const realtime = await fetch(`${origin}/api/realtime?format=sse`, { headers: { ...headers, accept: 'text/event-stream' }, signal: realtimeAbort.signal });
    if (realtime.status !== 200) throw new Error(`Realtime stream returned HTTP ${realtime.status}`);
    const reader = realtime.body?.getReader();
    const first = reader ? await reader.read() : { value: undefined };
    if (!first.value || !new TextDecoder().decode(first.value).includes('"type":"ready"')) throw new Error('Realtime stream did not emit a ready envelope');
    await reader?.cancel();
  } finally {
    clearTimeout(realtimeTimer);
  }

  const heartbeat = await request('/__scheduled');
  if (heartbeat.response.status >= 400) throw new Error(`Scheduler heartbeat returned HTTP ${heartbeat.response.status}`);
  await request('/api/house/motto', 'POST', { motto: 'Clean-room certification', correlationId: `clean-room-motto-${Date.now()}` });
  const after = {
    day: await dbScalar("SELECT game_day AS value FROM world_state WHERE id = 'WORLD'"),
    events: await dbScalar('SELECT COUNT(*) AS value FROM game_events'),
    outbox: await dbScalar('SELECT COUNT(*) AS value FROM event_outbox'),
  };
  if (after.events < before.events && after.outbox < before.outbox) throw new Error('Clean-room certification observed no durable database activity');
  console.log(JSON.stringify({ ok: true, before, after, certifiedRoutes: activeGets.length }, null, 2));
} finally {
  await client.end();
}
