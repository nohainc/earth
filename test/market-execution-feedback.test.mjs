import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const market = fs.readFileSync(new URL('../cloudflare/src/market-postgres.ts', import.meta.url), 'utf8');
const realtime = fs.readFileSync(new URL('../cloudflare/src/realtime-protocol.ts', import.meta.url), 'utf8');
const briefing = fs.readFileSync(new URL('../cloudflare/src/house-daily-summary-postgres.ts', import.meta.url), 'utf8');

test('market execution feedback has persistent outcome projections', () => {
  assert.match(market, /type MarketOutcome = 'FILLED' \| 'PARTIAL' \| 'EXPIRED' \| 'CANCELLED'/);
  assert.match(market, /const eventType = `MARKET_ORDER_\$\{input\.outcome\}`/);
  assert.match(market, /createNotification/);
  assert.match(market, /enqueueOutbox/);
  assert.match(market, /formatCreditUnits/);
  assert.match(market, /unitsToDisplayQuantity/);
  assert.match(market, /releasedCreditUnits/);
  assert.match(market, /releasedQuantityUnits/);
});

test('realtime exposes only the explicit public market outcome payload', () => {
  assert.match(realtime, /payload\.kind === 'MARKET_ORDER_OUTCOME'/);
  assert.match(realtime, /event\.event_key/);
  assert.match(realtime, /publicPayload/);
});

test('Daily Briefing consumes participant game events and notifications', () => {
  assert.match(briefing, /FROM game_events/);
  assert.match(briefing, /actor_house_id/);
  assert.match(briefing, /FROM notifications/);
});
