import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

test('Spot Market exposes canonical liquidity projections without a second matching authority', () => {
  const source = fs.readFileSync('cloudflare/src/market-api.ts', 'utf8');
  const matcher = fs.readFileSync('cloudflare/src/market-postgres.ts', 'utf8');
  assert.match(source, /resource === 'projection'/);
  assert.match(source, /STDDEV_POP/);
  assert.match(source, /SUM\(price_units \* quantity_units\)/);
  assert.match(source, /spreadUnits/);
  assert.match(source, /generatedFrom: 'postgres-canonical-facts'/);
  assert.match(matcher, /clearMarketAuction/);
});
