import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const source = fs.readFileSync(new URL('../cloudflare/src/index.ts', import.meta.url), 'utf8');

test('MarketCoordinator is a realtime connection coordinator, not market storage', () => {
  const coordinator = source.slice(source.indexOf('export class MarketCoordinator'), source.indexOf('async function productionEventsFromPostgres'));
  assert.doesNotMatch(coordinator, /ctx\.storage|submitCommand|lastCommand|snapshot/);
  assert.match(coordinator, /refresh_required/);
  assert.match(coordinator, /market_state_is_postgres_authoritative/);
  assert.match(source, /MARKET_COORDINATOR.*broadcast|\.broadcast\(/s);
});
