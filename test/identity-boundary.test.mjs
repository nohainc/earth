import assert from 'node:assert/strict';
import test from 'node:test';
import fs from 'node:fs';

const read = (path) => fs.readFileSync(path, 'utf8');

test('request identity exposes separate Human and House economic principals', () => {
  const auth = read('cloudflare/src/auth-session.ts');
  const finance = read('cloudflare/src/finance-routes.ts');
  const market = read('cloudflare/src/market-postgres.ts');

  assert.match(auth, /export async function currentHouse/);
  assert.match(auth, /export async function houseEconomicOwner/);
  assert.match(auth, /owner\.economic_id::TEXT AS economic_id/);
  assert.match(finance, /viewer\.house_id/);
  assert.match(finance, /personal_financial_states WHERE human_id = \$1/);
  assert.match(market, /owner\.economic_id FROM humans JOIN owner_registry owner ON owner\.id = humans\.house_id/);
});
