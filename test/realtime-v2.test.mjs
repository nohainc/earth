import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { mapToRealtimeInvalidation } from '../cloudflare/src/realtime-protocol.ts';

const indexSource = fs.readFileSync(path.resolve('cloudflare/src/index.ts'), 'utf8');
const realtimeSource = fs.readFileSync(path.resolve('cloudflare/src/realtime.ts'), 'utf8');

test('Worker preserves Cloudflare WebSocket upgrade responses', () => {
  assert.match(indexSource, /if \(\(response as Response & \{ webSocket\?: WebSocket \}\)\.webSocket\) return response;/);
  assert.doesNotMatch(indexSource, /webSocket\) return new Response\(response\.body/);
});

test('realtime rejects disallowed WebSocket origins and does not resend close codes', () => {
  assert.match(realtimeSource, /Origin not allowed/);
  assert.match(realtimeSource, /Upgrade.*websocket/si);
  assert.match(indexSource, /webSocketClose\(_socket: WebSocket, _code: number, _reason: string\)/);
  assert.doesNotMatch(indexSource, /webSocketClose[\s\S]*?socket\.close\(code, reason\)/);
});

test('Realtime V2 maps outbox records to a versioned invalidation envelope', () => {
  const event = mapToRealtimeInvalidation({
    topic: 'market.settled',
    aggregate_type: 'market_batch',
    event_key: 'market.settled.private-id-123',
    payload: {
      gameDay: 218,
      gameMinute: 420,
      accountId: 'house-secret',
      privateBalance: 900000,
      rawOrderPayload: 'must-not-leak',
    },
  });

  assert.deepEqual(event, {
    version: 1,
    type: 'refresh_required',
    topics: ['market'],
    gameDay: 218,
    gameMinute: 420,
    eventKey: 'market.settled',
    at: event.at,
  });
  assert.equal(JSON.stringify(event).includes('private-id-123'), false);
  assert.equal(JSON.stringify(event).includes('house-secret'), false);
  assert.equal(JSON.stringify(event).includes('must-not-leak'), false);
});

test('Realtime V2 uses a safe world topic for unknown event types', () => {
  const event = mapToRealtimeInvalidation({
    topic: 'internal-secret-event',
    payload: { game_day: 12, game_minute: 3 },
  });

  assert.equal(event.version, 1);
  assert.equal(event.type, 'refresh_required');
  assert.deepEqual(event.topics, ['world']);
  assert.equal(event.eventKey, 'world.event');
});
